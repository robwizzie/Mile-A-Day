import { PostgresService } from "./DbService.js";
import {
  streakFeaturesGloballyEnabled,
  getStreakFeatureRow,
  dateStrMinus,
  streakEndingAt,
  StreakFeatureUserRow,
} from "./streakFeatureCore.js";
import { getUserLocalToday, getMilesOnLocalDate } from "./workoutService.js";
import { refreshCurrentStreak } from "./leaderboardService.js";
import { sendPush } from "./pushNotificationService.js";

const db = PostgresService.getInstance();

/**
 * The three streak tokens, all earned through activity meters and all writing
 * the same substrate (streak_coverage) when spent:
 *
 *   🔥 Double Down    — meter: 14 mile-completing days (run OR walk). Held at
 *                       14. Spend: miss yesterday, run 2× your goal today →
 *                       yesterday is covered. Detected on the upload path.
 *   ❄️ Streak Save    — meter: 7 mile-completing RUN days (walks and short
 *                       jogs don't tick it). Held at 7. Spent automatically by
 *                       the sweep when a miss can't be (or wasn't) Double
 *                       Downed.
 *   🤝 Streak Assist  — meter: 20 miles run/walked BEYOND the daily goal.
 *                       Held at 20. Spent manually on a friend whose streak
 *                       broke yesterday.
 *
 * Meters are DERIVED — counted from workouts since the token's last-used date
 * — never stored, so retries/edits/deletes can't drift a counter. The window
 * opens at GREATEST(last use, enrollment − 30d lookback, today − 90d), which
 * both grants retroactive credit at enrollment and bounds the query.
 *
 * Everything here no-ops unless STREAK_FEATURES_ENABLED=true AND the user has
 * the (new-build-only) enrollment stamp.
 */

// Meter targets (product-locked; see docs). The Assist threshold is the dial
// most likely to need tuning after launch.
export const DOUBLE_DOWN_TARGET_DAYS = 14;
export const STREAK_SAVE_TARGET_RUN_DAYS = 7;
export const STREAK_ASSIST_TARGET_MILES = 20;
// Double Down completion threshold mirrors the 0.95 display tolerance.
const DOUBLE_DOWN_GOAL_MULTIPLIER = 2;
const DOUBLE_DOWN_TOLERANCE = 0.05;
// Meter windows: retroactive credit at enrollment + a hard query bound.
const ENROLL_LOOKBACK_DAYS = 30;
const METER_WINDOW_DAYS = 90;
// Assist-opportunity pushes only fire for streaks worth mourning.
const MIN_NOTIFY_PRIOR_STREAK = 3;
// A break stays rescuable for this many days after the missed day.
const ASSIST_RESCUE_WINDOW_DAYS = 2;

export interface MeterState {
  progress: number;
  target: number;
  held: boolean;
  last_used: string | null;
}

export interface StreakFeatureMeters {
  double_down: MeterState;
  streak_save: MeterState;
  streak_assist: MeterState;
  goalMiles: number;
}

/** Window floor for one meter: last use vs enrollment lookback vs hard bound. */
function meterFloor(
  lastUsed: string | null,
  enrolledAt: string,
  userToday: string,
): string {
  const enrollFloor = dateStrMinus(
    enrolledAt.slice(0, 10),
    ENROLL_LOOKBACK_DAYS,
  );
  const hardFloor = dateStrMinus(userToday, METER_WINDOW_DAYS);
  let floor = enrollFloor > hardFloor ? enrollFloor : hardFloor;
  if (lastUsed && lastUsed > floor) floor = lastUsed;
  return floor;
}

/**
 * Derive all three meters in one query. "Day counts" uses the same flat
 * 0.95-mile rule as the streak walks; the Save meter additionally requires the
 * RUNNING workouts alone to complete the mile (the "7 days of running a mile"
 * rule — a short jog alongside a long walk does not tick it).
 */
export async function getMeters(
  userId: string,
  row: StreakFeatureUserRow,
  userToday: string,
): Promise<StreakFeatureMeters> {
  const enrolledAt = row.streak_features_at ?? userToday;
  const ddFloor = meterFloor(row.double_down_last_used, enrolledAt, userToday);
  const saveFloor = meterFloor(
    row.streak_save_last_used,
    enrolledAt,
    userToday,
  );
  const assistFloor = meterFloor(
    row.streak_assist_last_used,
    enrolledAt,
    userToday,
  );
  const goalMiles = Number(row.goal_miles) || 1.0;

  const rows = await db.query<{
    dd_days: string | number;
    save_days: string | number;
    assist_miles: string | number;
  }>(
    `SELECT
      (SELECT COUNT(*) FROM (
        SELECT local_date FROM workouts
        WHERE user_id = $1 AND deleted_at IS NULL AND exclusion_reason IS NULL
          AND local_date > $2::date AND local_date <= $5::date
        GROUP BY local_date HAVING SUM(distance) >= 0.95
      ) dd) AS dd_days,
      (SELECT COUNT(*) FROM (
        SELECT local_date FROM workouts
        WHERE user_id = $1 AND deleted_at IS NULL AND exclusion_reason IS NULL
          AND workout_type = 'running'
          AND local_date > $3::date AND local_date <= $5::date
        GROUP BY local_date HAVING SUM(distance) >= 0.95
      ) sv) AS save_days,
      COALESCE((SELECT SUM(GREATEST(day_total - $6::double precision, 0)) FROM (
        SELECT SUM(distance) AS day_total FROM workouts
        WHERE user_id = $1 AND deleted_at IS NULL AND exclusion_reason IS NULL
          AND local_date > $4::date AND local_date <= $5::date
        GROUP BY local_date
      ) a), 0) AS assist_miles`,
    [userId, ddFloor, saveFloor, assistFloor, userToday, goalMiles],
  );

  const ddDays = Number(rows[0]?.dd_days ?? 0);
  const saveDays = Number(rows[0]?.save_days ?? 0);
  const assistMiles = Number(rows[0]?.assist_miles ?? 0);

  return {
    double_down: {
      progress: Math.min(ddDays, DOUBLE_DOWN_TARGET_DAYS),
      target: DOUBLE_DOWN_TARGET_DAYS,
      held: ddDays >= DOUBLE_DOWN_TARGET_DAYS,
      last_used: row.double_down_last_used,
    },
    streak_save: {
      progress: Math.min(saveDays, STREAK_SAVE_TARGET_RUN_DAYS),
      target: STREAK_SAVE_TARGET_RUN_DAYS,
      held: saveDays >= STREAK_SAVE_TARGET_RUN_DAYS,
      last_used: row.streak_save_last_used,
    },
    streak_assist: {
      progress: Math.min(
        Math.round(assistMiles * 100) / 100,
        STREAK_ASSIST_TARGET_MILES,
      ),
      target: STREAK_ASSIST_TARGET_MILES,
      held: assistMiles >= STREAK_ASSIST_TARGET_MILES,
      last_used: row.streak_assist_last_used,
    },
    goalMiles,
  };
}

/** Qualifying + covered day lookups for a small recent window. */
async function recentDayFacts(
  userId: string,
  fromDate: string,
): Promise<{ qualified: Set<string>; covered: Set<string> }> {
  const [qual, cov] = await Promise.all([
    db.query<{ d: string }>(
      `SELECT to_char(local_date, 'YYYY-MM-DD') AS d FROM workouts
       WHERE user_id = $1 AND local_date >= $2::date
         AND deleted_at IS NULL AND exclusion_reason IS NULL
       GROUP BY local_date HAVING SUM(distance) >= 0.95`,
      [userId, fromDate],
    ),
    db.query<{ d: string }>(
      `SELECT to_char(local_date, 'YYYY-MM-DD') AS d FROM streak_coverage
       WHERE user_id = $1 AND local_date >= $2::date`,
      [userId, fromDate],
    ),
  ]);
  return {
    qualified: new Set(qual.map((r) => r.d)),
    covered: new Set(cov.map((r) => r.d)),
  };
}

/** Insert one coverage row; true when THIS call inserted it (race-safe). */
async function insertCoverage(
  userId: string,
  localDate: string,
  kind: string,
  triggerDate: string,
  sourceUser: string | null = null,
): Promise<boolean> {
  const rows = await db.query(
    `INSERT INTO streak_coverage (user_id, local_date, kind, trigger_date, source_user)
     VALUES ($1, $2::date, $3, $4::date, $5)
     ON CONFLICT (user_id, local_date) DO NOTHING
     RETURNING local_date`,
    [userId, localDate, kind, triggerDate, sourceUser],
  );
  return rows.length > 0;
}

/**
 * Upload-path hook: detect a completed Double Down. Called fire-and-forget
 * after every workout upload; the first two checks make it a cheap no-op for
 * everyone until the feature is live (env switch) and the user enrolled.
 */
export async function reconcileStreakFeaturesOnUpload(
  userId: string,
): Promise<void> {
  if (!streakFeaturesGloballyEnabled()) return;
  const row = await getStreakFeatureRow(userId);
  if (!row?.streak_features_at) return;

  const userToday = await getUserLocalToday(userId);
  const missedDay = dateStrMinus(userToday, 1);
  const dayBefore = dateStrMinus(userToday, 2);

  const facts = await recentDayFacts(userId, dateStrMinus(userToday, 3));
  const ok = (d: string) => facts.qualified.has(d) || facts.covered.has(d);

  // Only the classic shape: yesterday missed, an older streak to reconnect.
  if (ok(missedDay) || !ok(dayBefore)) return;

  const meters = await getMeters(userId, row, userToday);
  if (!meters.double_down.held) return;

  const todayMiles = await getMilesOnLocalDate(userId, userToday);
  const threshold =
    meters.goalMiles * DOUBLE_DOWN_GOAL_MULTIPLIER - DOUBLE_DOWN_TOLERANCE;
  if (todayMiles < threshold) return;

  const inserted = await insertCoverage(
    userId,
    missedDay,
    "double_down_recover",
    userToday,
  );
  if (!inserted) return;

  await db.query(
    `UPDATE users SET double_down_last_used = $1::date WHERE user_id = $2`,
    [userToday, userId],
  );
  const streak = await refreshCurrentStreak(userId);
  sendPush(userId, {
    title: "\u{1F525} Double Down complete!",
    body: `You ran it back — yesterday counts and your ${streak}-day streak lives on.`,
    type: "streak_double_down",
    data: { local_date: missedDay },
  }).catch((e: any) =>
    console.error("[StreakFeatures] double-down push failed:", e?.message ?? e),
  );
}

/**
 * Hourly sweep, processing each enrolled user during their local morning
 * (6–11). Every action is idempotent (coverage/event PKs), so re-processing
 * the same user across those hours is harmless.
 *
 * Per user it settles YESTERDAY (and the day before, for a Double Down window
 * that expired unused): wait if the Double Down window is open and the token
 * is held; otherwise auto-consume a held Streak Save; otherwise stamp the
 * break and offer the rescue to assist-holding friends.
 */
export async function runStreakFeaturesSweep(): Promise<{
  processed: number;
  saved: number;
  breaks: number;
}> {
  if (!streakFeaturesGloballyEnabled())
    return { processed: 0, saved: 0, breaks: 0 };

  const candidates = await db.query<{ user_id: string; user_today: string }>(
    `SELECT u.user_id, to_char(t.local_now::date, 'YYYY-MM-DD') AS user_today
     FROM users u
     CROSS JOIN LATERAL (
       SELECT NOW() + (COALESCE(
         (SELECT timezone_offset FROM workouts w
          WHERE w.user_id = u.user_id ORDER BY device_end_date DESC LIMIT 1),
         0
       ) || ' minutes')::interval AS local_now
     ) t
     WHERE u.streak_features_at IS NOT NULL
       AND EXTRACT(HOUR FROM t.local_now) BETWEEN 6 AND 11`,
  );

  let saved = 0;
  let breaks = 0;
  for (const { user_id, user_today } of candidates) {
    try {
      const result = await sweepOneUser(user_id, user_today);
      if (result === "saved") saved++;
      if (result === "break") breaks++;
    } catch (err: any) {
      // Isolate per-user failures so one bad row doesn't abort the sweep.
      console.error(
        `[StreakFeatures] sweep failed for ${user_id}:`,
        err?.message ?? err,
      );
    }
  }
  return { processed: candidates.length, saved, breaks };
}

async function sweepOneUser(
  userId: string,
  userToday: string,
): Promise<"none" | "waiting" | "saved" | "break"> {
  const row = await getStreakFeatureRow(userId);
  if (!row?.streak_features_at) return "none";

  const d1 = dateStrMinus(userToday, 1);
  const d2 = dateStrMinus(userToday, 2);
  const d3 = dateStrMinus(userToday, 3);
  const facts = await recentDayFacts(userId, dateStrMinus(userToday, 4));
  const ok = (d: string) => facts.qualified.has(d) || facts.covered.has(d);

  // Which missed day are we settling?
  //  - d1 missed with d2 intact  → fresh miss; Double Down window is OPEN today.
  //  - d1 intact, d2 missed, d3 intact → the hole a DD window left behind
  //    (user ran a normal mile yesterday instead of 2×) → window CLOSED.
  //  - d1 AND d2 missed → 2-day gap: tokens never partially bridge; the streak
  //    (if d3 was intact) broke at d2.
  let missedDay: string | null = null;
  let ddWindowOpen = false;
  if (!ok(d1) && ok(d2)) {
    missedDay = d1;
    ddWindowOpen = true;
  } else if (ok(d1) && !ok(d2) && ok(d3)) {
    missedDay = d2;
  } else if (!ok(d1) && !ok(d2)) {
    // Unsalvageable gap — stamp the break at its first missed day if the
    // streak actually ended here (d3 intact); older breaks were stamped on
    // previous sweeps.
    if (ok(d3)) return recordBreak(userId, d2);
    return "none";
  } else {
    return "none";
  }

  const meters = await getMeters(userId, row, userToday);

  // Effort first: while the Double Down window is open and the token is held,
  // give the runner their shot at earning it back before burning a Save.
  if (ddWindowOpen && meters.double_down.held) return "waiting";

  if (meters.streak_save.held) {
    const inserted = await insertCoverage(
      userId,
      missedDay,
      "streak_save",
      userToday,
    );
    if (!inserted) return "none"; // raced with another writer — already covered
    await db.query(
      `UPDATE users SET streak_save_last_used = $1::date WHERE user_id = $2`,
      [userToday, userId],
    );
    const streak = await refreshCurrentStreak(userId);
    sendPush(userId, {
      title: "❄️ Streak Save used",
      body: `Life happened — we covered the miss and your ${streak}-day streak lives on.`,
      type: "streak_saved",
      data: { local_date: missedDay },
    }).catch((e: any) =>
      console.error("[StreakFeatures] save push failed:", e?.message ?? e),
    );
    return "saved";
  }

  // No token could (or should) cover it → the streak broke at missedDay.
  return recordBreak(userId, missedDay);
}

/** Stamp a break event once, and offer the rescue to assist-holding friends. */
async function recordBreak(
  userId: string,
  missedDay: string,
): Promise<"none" | "break"> {
  const prior = await streakEndingAt(userId, dateStrMinus(missedDay, 1));
  if (prior < 1) return "none";

  const rows = await db.query(
    `INSERT INTO streak_events (user_id, local_date, kind, prior_streak)
     VALUES ($1, $2::date, 'break', $3)
     ON CONFLICT (user_id, local_date, kind) DO NOTHING
     RETURNING local_date`,
    [userId, missedDay, prior],
  );
  if (rows.length === 0) return "none"; // already stamped by an earlier run

  if (prior >= MIN_NOTIFY_PRIOR_STREAK) {
    notifyAssistHolders(userId, missedDay, prior).catch((e: any) =>
      console.error(
        "[StreakFeatures] assist-opportunity notify failed:",
        e?.message ?? e,
      ),
    );
  }
  return "break";
}

/** Push "you can save them" to enrolled friends currently holding an Assist. */
async function notifyAssistHolders(
  brokenUserId: string,
  missedDay: string,
  priorStreak: number,
): Promise<void> {
  const nameRows = await db.query<{
    username: string | null;
    first_name: string | null;
  }>(`SELECT username, first_name FROM users WHERE user_id = $1`, [
    brokenUserId,
  ]);
  const display =
    nameRows[0]?.username || nameRows[0]?.first_name || "A friend";

  const friends = await db.query<{ friend_id: string }>(
    `SELECT f.friend_id
     FROM friendships f
     JOIN users fu ON fu.user_id = f.friend_id
     WHERE f.user_id = $1 AND f.status = 'accepted'
       AND fu.streak_features_at IS NOT NULL
       AND NOT EXISTS (
         SELECT 1 FROM user_blocks b
         WHERE (b.blocker_id = $1 AND b.blocked_id = f.friend_id)
            OR (b.blocker_id = f.friend_id AND b.blocked_id = $1)
       )`,
    [brokenUserId],
  );

  for (const { friend_id } of friends) {
    try {
      const row = await getStreakFeatureRow(friend_id);
      if (!row?.streak_features_at) continue;
      const friendToday = await getUserLocalToday(friend_id);
      const meters = await getMeters(friend_id, row, friendToday);
      if (!meters.streak_assist.held) continue;
      await sendPush(friend_id, {
        title: `\u{1F525} ${display}'s ${priorStreak}-day streak just broke`,
        body: "You're holding a Streak Assist — you can save it from their profile today.",
        type: "streak_assist_opportunity",
        data: {
          user_id: brokenUserId,
          local_date: missedDay,
          prior_streak: String(priorStreak),
        },
      });
    } catch (err: any) {
      console.error(
        `[StreakFeatures] opportunity push to ${friend_id} failed:`,
        err?.message ?? err,
      );
    }
  }
}

export type GiveAssistResult =
  | { status: "ok"; restored_streak: number }
  | {
      status:
        | "disabled"
        | "not_enrolled"
        | "friend_not_enrolled"
        | "forbidden"
        | "no_token"
        | "no_recent_break"
        | "window_passed"
        | "gap_too_wide"
        | "already_saved";
    };

/**
 * Spend the giver's Streak Assist to restore a friend's just-broken streak.
 * Guards mirror the story-reaction pattern: accepted friendship, no block in
 * either direction — plus BOTH sides must be enrolled (covering an un-enrolled
 * user's day would change streak math the legacy walk can't see).
 */
export async function giveStreakAssist(
  giverId: string,
  friendId: string,
): Promise<GiveAssistResult> {
  if (!streakFeaturesGloballyEnabled()) return { status: "disabled" };
  if (giverId === friendId) return { status: "forbidden" };

  const [giverRow, friendRow] = await Promise.all([
    getStreakFeatureRow(giverId),
    getStreakFeatureRow(friendId),
  ]);
  if (!giverRow?.streak_features_at) return { status: "not_enrolled" };
  if (!friendRow?.streak_features_at) return { status: "friend_not_enrolled" };

  const allowed = await db.query(
    `SELECT 1 FROM friendships f
     WHERE f.user_id = $1 AND f.friend_id = $2 AND f.status = 'accepted'
       AND NOT EXISTS (
         SELECT 1 FROM user_blocks b
         WHERE (b.blocker_id = $1 AND b.blocked_id = $2)
            OR (b.blocker_id = $2 AND b.blocked_id = $1)
       )`,
    [giverId, friendId],
  );
  if (allowed.length === 0) return { status: "forbidden" };

  const giverToday = await getUserLocalToday(giverId);
  const giverMeters = await getMeters(giverId, giverRow, giverToday);
  if (!giverMeters.streak_assist.held) return { status: "no_token" };

  const friendToday = await getUserLocalToday(friendId);
  const events = await db.query<{ local_date: string; prior_streak: number }>(
    `SELECT to_char(local_date, 'YYYY-MM-DD') AS local_date, prior_streak
     FROM streak_events
     WHERE user_id = $1 AND kind = 'break' AND local_date >= $2::date
     ORDER BY local_date DESC LIMIT 1`,
    [friendId, dateStrMinus(friendToday, ASSIST_RESCUE_WINDOW_DAYS + 1)],
  );
  if (events.length === 0) return { status: "no_recent_break" };
  const missedDay = events[0].local_date;
  if (missedDay < dateStrMinus(friendToday, ASSIST_RESCUE_WINDOW_DAYS)) {
    return { status: "window_passed" };
  }

  // The bridge must reconnect: every day between the miss and the friend's
  // today has to be intact, or covering one day still leaves a hole (tokens
  // never partially bridge).
  const facts = await recentDayFacts(friendId, missedDay);
  let cursor = dateStrMinus(friendToday, 1);
  while (cursor > missedDay) {
    if (!facts.qualified.has(cursor) && !facts.covered.has(cursor)) {
      return { status: "gap_too_wide" };
    }
    cursor = dateStrMinus(cursor, 1);
  }

  const inserted = await insertCoverage(
    friendId,
    missedDay,
    "streak_assist",
    giverToday,
    giverId,
  );
  if (!inserted) return { status: "already_saved" };

  await db.query(
    `UPDATE users SET streak_assist_last_used = $1::date WHERE user_id = $2`,
    [giverToday, giverId],
  );
  const restored = await refreshCurrentStreak(friendId);

  const giverName = await db.query<{
    username: string | null;
    first_name: string | null;
  }>(`SELECT username, first_name FROM users WHERE user_id = $1`, [giverId]);
  const display =
    giverName[0]?.username || giverName[0]?.first_name || "A friend";
  sendPush(friendId, {
    title: `\u{1F91D} ${display} saved your streak!`,
    body: `Your ${restored}-day streak is back — go keep it alive.`,
    type: "streak_assisted",
    data: { user_id: giverId, local_date: missedDay },
  }).catch((e: any) =>
    console.error("[StreakFeatures] assisted push failed:", e?.message ?? e),
  );

  return { status: "ok", restored_streak: restored };
}

/** Idempotent enrollment stamp — the new build calls this once on launch. */
export async function enrollStreakFeatures(
  userId: string,
): Promise<{ enrolled: boolean; enrolled_at: string | null }> {
  const rows = await db.query<{ streak_features_at: string }>(
    `UPDATE users
     SET streak_features_at = COALESCE(streak_features_at, NOW())
     WHERE user_id = $1
     RETURNING streak_features_at`,
    [userId],
  );
  return {
    enrolled: rows.length > 0,
    enrolled_at: rows[0]?.streak_features_at ?? null,
  };
}

export interface StreakFeaturesPayload {
  double_down: MeterState & { recover_miles: number };
  streak_save: MeterState;
  streak_assist: MeterState;
  frozen_dates: { local_date: string; kind: string }[];
  natural_streak: boolean;
  streak_at_risk: boolean;
}

/**
 * The gated per-user payload for getUserStats / the status endpoint. Returns
 * null when the gate is off for this user — callers OMIT the field entirely,
 * keeping un-enrolled responses byte-identical.
 *
 * `natural_streak` is strict on purpose: ANY coverage inside the current
 * streak span (a Save, a Double Down recovery, or a received Assist) makes
 * the streak non-natural. GIVING an assist writes coverage on the friend's
 * row, so it never taints the giver.
 */
export async function getStreakFeaturesPayload(
  userId: string,
  streak: number,
  streakStart: string | undefined,
): Promise<StreakFeaturesPayload | null> {
  if (!streakFeaturesGloballyEnabled()) return null;
  const row = await getStreakFeatureRow(userId);
  if (!row?.streak_features_at) return null;

  const userToday = await getUserLocalToday(userId);
  const meters = await getMeters(userId, row, userToday);

  const coverage = await db.query<{ local_date: string; kind: string }>(
    `SELECT to_char(local_date, 'YYYY-MM-DD') AS local_date, kind
     FROM streak_coverage
     WHERE user_id = $1 AND local_date >= $2::date
     ORDER BY local_date DESC`,
    [userId, dateStrMinus(userToday, METER_WINDOW_DAYS)],
  );

  const natural =
    streak === 0 ||
    !streakStart ||
    !coverage.some((c) => c.local_date >= streakStart);

  // At risk = yesterday missed, older streak intact, and a held Double Down
  // could still bring it back with a 2× run today.
  let atRisk = false;
  if (meters.double_down.held) {
    const facts = await recentDayFacts(userId, dateStrMinus(userToday, 3));
    const okDay = (d: string) => facts.qualified.has(d) || facts.covered.has(d);
    const d1 = dateStrMinus(userToday, 1);
    const d2 = dateStrMinus(userToday, 2);
    atRisk = !okDay(d1) && okDay(d2);
  }

  return {
    double_down: {
      ...meters.double_down,
      recover_miles:
        Math.round(
          (meters.goalMiles * DOUBLE_DOWN_GOAL_MULTIPLIER -
            DOUBLE_DOWN_TOLERANCE) *
            100,
        ) / 100,
    },
    streak_save: meters.streak_save,
    streak_assist: meters.streak_assist,
    frozen_dates: coverage,
    natural_streak: natural,
    streak_at_risk: atRisk,
  };
}

export interface AssistableFriend {
  user_id: string;
  username: string | null;
  first_name: string | null;
  last_name: string | null;
  profile_image_url: string | null;
  broke_date: string;
  prior_streak: number;
}

/**
 * Friends with a fresh, still-uncovered break the caller could rescue.
 * Approximate window here (the give call re-validates strictly against each
 * friend's own local today).
 */
export async function getAssistableFriends(
  userId: string,
): Promise<AssistableFriend[]> {
  return db.query<AssistableFriend>(
    `SELECT e.user_id, u.username, u.first_name, u.last_name,
            u.profile_image_url,
            to_char(e.local_date, 'YYYY-MM-DD') AS broke_date,
            e.prior_streak
     FROM streak_events e
     JOIN users u ON u.user_id = e.user_id
     WHERE e.kind = 'break'
       AND e.local_date >= (CURRENT_DATE - ${ASSIST_RESCUE_WINDOW_DAYS + 1})
       AND e.prior_streak >= 1
       AND u.streak_features_at IS NOT NULL
       AND e.user_id IN (
         SELECT friend_id FROM friendships
         WHERE user_id = $1 AND status = 'accepted'
       )
       AND NOT EXISTS (
         SELECT 1 FROM streak_coverage sc
         WHERE sc.user_id = e.user_id AND sc.local_date = e.local_date
       )
       AND NOT EXISTS (
         SELECT 1 FROM user_blocks b
         WHERE (b.blocker_id = $1 AND b.blocked_id = e.user_id)
            OR (b.blocker_id = e.user_id AND b.blocked_id = $1)
       )
     ORDER BY e.created_at DESC
     LIMIT 20`,
    [userId],
  );
}
