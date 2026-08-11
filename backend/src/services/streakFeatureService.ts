import { PostgresService } from "./DbService.js";
import {
  streakFeaturesGloballyEnabled,
  getStreakFeatureRow,
  dateStrMinus,
  dateStrPlus,
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
 *   🤝 Streak Assist  — meter: TIME, not effort. One every 30 days, counted
 *                       from the day you last spent one; never spent one and
 *                       you're already holding it. Spent on YOUR OWN broken
 *                       day, but only with a friend's donated mile — see
 *                       below.
 *
 * The Assist is the one token you cannot spend alone. It costs two things from
 * two people: the RECIPIENT's held token, and one mile the DONOR ran past
 * their own goal that day (two friends in a day = two miles past goal, three =
 * three). Either side may open the exchange — donate a mile you've already
 * run, or ask a friend for one — but it always takes both answers, so a
 * streak_assist coverage row can only appear after an accept.
 *
 * Meters are DERIVED — never stored, so retries/edits/deletes can't drift a
 * counter. Double Down and Streak Save count workouts since the token's
 * last-used date, over a window opening at GREATEST(last use, enrollment −
 * 365d, today − 365d), which both grants retroactive credit at enrollment and
 * bounds the query. The Assist counts DAYS since its last use instead, so it
 * reads no workouts at all.
 *
 * Everything here no-ops unless the user has the (new-build-only) enrollment
 * stamp — and freezes entirely if the STREAK_FEATURES_DISABLED kill switch is
 * set (normally unset).
 */

// Meter targets (product-locked; see docs). The Assist threshold is the dial
// most likely to need tuning after launch.
export const DOUBLE_DOWN_TARGET_DAYS = 14;
export const STREAK_SAVE_TARGET_RUN_DAYS = 7;
// The Assist is the one meter that isn't earned by running. It's a 30-day
// allowance measured from the last spend, so a new account holds one on day
// one (nothing spent yet) and spending one starts a visible countdown. That
// also makes it the only meter needing no query at all — just two dates.
export const STREAK_ASSIST_TARGET_DAYS = 30;
// Double Down completion threshold mirrors the 0.95 display tolerance.
const DOUBLE_DOWN_GOAL_MULTIPLIER = 2;
const DOUBLE_DOWN_TOLERANCE = 0.05;
// Meter windows: retroactive credit at enrollment + a hard query bound.
// A FULL YEAR on purpose — a 400-day streaker must enroll fully loaded
// (all three tokens held), not start from scratch like a new runner. The
// original 30/90 made long streaks count the same as one month. Post-launch
// the window is naturally bounded by each token's last-used date anyway.
const ENROLL_LOOKBACK_DAYS = 365;
const METER_WINDOW_DAYS = 365;
// Assist-opportunity pushes only fire for streaks worth mourning.
const MIN_NOTIFY_PRIOR_STREAK = 3;
// A break stays rescuable for this many days after the missed day.
const ASSIST_RESCUE_WINDOW_DAYS = 2;
// One donation per whole mile past the donor's goal that day. Same 0.05 grace
// as Double Down, so a GPS-shy 1.98 still buys the second one.
const DONATION_MILE_COST = 1;
const DONATION_TOLERANCE = DOUBLE_DOWN_TOLERANCE;

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

/** "YYYY-MM-DD" from either pg shape: `date` → string, timestamptz → Date. */
function dateOnly(value: string | Date | null): string | null {
  if (!value) return null;
  if (value instanceof Date) return value.toISOString().slice(0, 10);
  return String(value).slice(0, 10);
}

/**
 * Days of the Assist allowance accrued: the whole earn rule, in two dates.
 *
 * Never spent one → already at target, which is deliberate. A brand-new
 * account is exactly the case with no history to earn from, and the first
 * miss is the one most worth catching; making them wait 30 days for their
 * first token would mean the feature simply doesn't exist for a new user's
 * first month.
 *
 * Clamped at 0 because `streak_assist_last_used` is stamped in the SPENDER's
 * local today, which can legitimately read a day ahead of a caller further
 * west — a negative here would render as a countdown longer than 30.
 */
function assistDaysElapsed(
  lastUsed: string | null,
  userToday: string,
): number {
  if (!lastUsed) return STREAK_ASSIST_TARGET_DAYS;
  const from = Date.parse(`${lastUsed.slice(0, 10)}T00:00:00Z`);
  const to = Date.parse(`${userToday}T00:00:00Z`);
  if (Number.isNaN(from) || Number.isNaN(to)) return 0;
  return Math.max(0, Math.round((to - from) / 86_400_000));
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
  // streak_features_at is a timestamptz → node-pg hands back a JS Date (not a
  // string like `date` columns). Calling .slice() on it was a TypeError that
  // 500'd the status endpoint (and silently killed Double Down detection and
  // the sweep) for every enrolled user.
  const enrolledAt = dateOnly(row.streak_features_at) ?? userToday;
  const ddFloor = meterFloor(row.double_down_last_used, enrolledAt, userToday);
  const saveFloor = meterFloor(
    row.streak_save_last_used,
    enrolledAt,
    userToday,
  );
  const goalMiles = Number(row.goal_miles) || 1.0;

  const rows = await db.query<{
    dd_days: string | number;
    save_days: string | number;
  }>(
    `SELECT
      (SELECT COUNT(*) FROM (
        SELECT local_date FROM workouts
        WHERE user_id = $1 AND deleted_at IS NULL AND exclusion_reason IS NULL
          AND local_date > $2::date AND local_date <= $4::date
        GROUP BY local_date HAVING SUM(distance) >= 0.95
      ) dd) AS dd_days,
      (SELECT COUNT(*) FROM (
        SELECT local_date FROM workouts
        WHERE user_id = $1 AND deleted_at IS NULL AND exclusion_reason IS NULL
          AND workout_type = 'running'
          AND local_date > $3::date AND local_date <= $4::date
        GROUP BY local_date HAVING SUM(distance) >= 0.95
      ) sv) AS save_days`,
    [userId, ddFloor, saveFloor, userToday],
  );

  const ddDays = Number(rows[0]?.dd_days ?? 0);
  const saveDays = Number(rows[0]?.save_days ?? 0);
  const assistDays = assistDaysElapsed(row.streak_assist_last_used, userToday);

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
      progress: Math.min(assistDays, STREAK_ASSIST_TARGET_DAYS),
      target: STREAK_ASSIST_TARGET_DAYS,
      held: assistDays >= STREAK_ASSIST_TARGET_DAYS,
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
    notifyBrokenTokenHolder(userId, missedDay, prior).catch((e: any) =>
      console.error(
        "[StreakFeatures] assist-available notify failed:",
        e?.message ?? e,
      ),
    );
  }
  return "break";
}

/**
 * Tell the person who just broke that they hold the token to fix it.
 *
 * This push used to fan out to every friend holding an Assist. That made sense
 * when a friend could spend their own token unilaterally; now the token is the
 * BROKEN user's and the friend's half is a mile they may not have run yet, so
 * a 7am blast to the whole friend list would ask most of them for something
 * they can't give. The one person who can always act is the recipient — they
 * ask, and the ask reaches friends who are actually holding a spare mile.
 */
async function notifyBrokenTokenHolder(
  brokenUserId: string,
  missedDay: string,
  priorStreak: number,
): Promise<void> {
  const row = await getStreakFeatureRow(brokenUserId);
  if (!row?.streak_features_at) return;
  const userToday = await getUserLocalToday(brokenUserId);
  const meters = await getMeters(brokenUserId, row, userToday);
  if (!meters.streak_assist.held) return;

  await sendPush(brokenUserId, {
    title: `\u{1F91D} Your ${priorStreak}-day streak needs a hand`,
    body: "You're holding a Streak Assist. Ask a friend to donate a mile and it's saved.",
    type: "streak_assist_available",
    data: {
      local_date: missedDay,
      prior_streak: String(priorStreak),
    },
  });
}

export type AssistExchangeResult =
  | {
      status: "ok";
      offer_id: string;
      target_date: string;
      /** What the recipient's streak becomes/stays once the day is covered. */
      restored_streak: number;
      /** True once coverage was actually written (accept), false for a pending offer. */
      applied: boolean;
    }
  | {
      status:
        | "disabled"
        | "not_enrolled"
        | "friend_not_enrolled"
        | "forbidden"
        | "no_token"
        | "friend_no_token"
        | "no_miles"
        | "no_savable_day"
        | "window_passed"
        | "gap_too_wide"
        | "already_saved"
        | "already_pending"
        | "not_found";
    };

type AssistExchangeError = Exclude<
  AssistExchangeResult,
  { status: "ok" }
>["status"];

/** Accepted friendship in the caller's direction, with no block either way. */
async function friendshipAllowed(
  userId: string,
  friendId: string,
): Promise<boolean> {
  const rows = await db.query(
    `SELECT 1 FROM friendships f
     WHERE f.user_id = $1 AND f.friend_id = $2 AND f.status = 'accepted'
       AND NOT EXISTS (
         SELECT 1 FROM user_blocks b
         WHERE (b.blocker_id = $1 AND b.blocked_id = $2)
            OR (b.blocker_id = $2 AND b.blocked_id = $1)
       )`,
    [userId, friendId],
  );
  return rows.length > 0;
}

export interface DonationBudget {
  goal_miles: number;
  today_miles: number;
  /** Whole miles past goal today — one buys one friend's day. */
  allowed: number;
  /** Already committed from today's miles (pending offers + accepted ones). */
  used: number;
  remaining: number;
}

/**
 * How many friends the donor can still cover today. The mile is the donor's
 * whole half of the exchange, so it is spent at OFFER time, not at accept:
 * an offer nobody has answered yet still holds its mile, or one runner could
 * offer the same mile to five friends and have all five accept it.
 *
 * Bucketed by the donor's own local date, so an offer left unanswered
 * overnight stops charging tomorrow's miles (it dies with its target day
 * anyway — see `pendingOfferRows`).
 */
export async function getDonationBudget(
  donorId: string,
  row: StreakFeatureUserRow,
  donorToday: string,
): Promise<DonationBudget> {
  const goalMiles = Number(row.goal_miles) || 1.0;
  const todayMiles = await getMilesOnLocalDate(donorId, donorToday);
  const allowed = Math.max(
    0,
    Math.floor(
      (todayMiles - goalMiles + DONATION_TOLERANCE) / DONATION_MILE_COST,
    ),
  );
  const usedRows = await db.query<{ n: string }>(
    `SELECT COUNT(*) AS n FROM streak_assist_offers
     WHERE donor_id = $1 AND donor_date = $2::date
       AND status IN ('pending', 'accepted')`,
    [donorId, donorToday],
  );
  const used = Number(usedRows[0]?.n ?? 0);
  return {
    goal_miles: goalMiles,
    today_miles: Math.round(todayMiles * 100) / 100,
    allowed,
    used,
    remaining: Math.max(0, allowed - used),
  };
}

/**
 * Re-check that a target day is still worth (and legal to) cover, against the
 * recipient's own clock. Every advertisement of an exchange runs this, and so
 * does the accept — a day can be covered, run, or age out of the window
 * between an offer being made and answered.
 */
async function validateTarget(
  recipientId: string,
  recipientRow: StreakFeatureUserRow,
  targetDate: string,
): Promise<
  | { ok: true; restored_streak: number }
  | { ok: false; reason: "no_savable_day" | "window_passed" | "gap_too_wide" }
> {
  const recipientToday = await getUserLocalToday(recipientId);
  if (targetDate < dateStrMinus(recipientToday, ASSIST_RESCUE_WINDOW_DAYS)) {
    return { ok: false, reason: "window_passed" };
  }
  const target = await getSavableTarget(
    recipientId,
    recipientToday,
    recipientRow,
  );
  if (!target) return { ok: false, reason: "no_savable_day" };
  if (target.local_date !== targetDate) {
    // They moved on: ran the day, or slipped a further day back. Either way
    // this offer is about a date that is no longer the one in play.
    return {
      ok: false,
      reason: target.local_date > targetDate ? "no_savable_day" : "gap_too_wide",
    };
  }
  return { ok: true, restored_streak: target.restored_streak };
}

/** Both halves of the exchange, resolved and checked. */
async function loadExchange(
  donorId: string,
  recipientId: string,
): Promise<
  | { ok: false; status: AssistExchangeError }
  | {
      ok: true;
      donorRow: StreakFeatureUserRow;
      recipientRow: StreakFeatureUserRow;
      donorToday: string;
      target: SavableTarget;
    }
> {
  if (!streakFeaturesGloballyEnabled()) return { ok: false, status: "disabled" };
  if (donorId === recipientId) return { ok: false, status: "forbidden" };

  const [donorRow, recipientRow] = await Promise.all([
    getStreakFeatureRow(donorId),
    getStreakFeatureRow(recipientId),
  ]);
  if (!donorRow?.streak_features_at)
    return { ok: false, status: "not_enrolled" };
  if (!recipientRow?.streak_features_at)
    return { ok: false, status: "friend_not_enrolled" };
  if (!(await friendshipAllowed(donorId, recipientId)))
    return { ok: false, status: "forbidden" };

  const [donorToday, recipientToday] = await Promise.all([
    getUserLocalToday(donorId),
    getUserLocalToday(recipientId),
  ]);

  // The recipient's token is the half that pays for the coverage row.
  const recipientMeters = await getMeters(
    recipientId,
    recipientRow,
    recipientToday,
  );
  if (!recipientMeters.streak_assist.held)
    return { ok: false, status: "friend_no_token" };

  const target = await getSavableTarget(
    recipientId,
    recipientToday,
    recipientRow,
  );
  if (!target) return { ok: false, status: "no_savable_day" };

  return { ok: true, donorRow, recipientRow, donorToday, target };
}

async function displayName(userId: string): Promise<string> {
  const rows = await db.query<{
    username: string | null;
    first_name: string | null;
  }>(`SELECT username, first_name FROM users WHERE user_id = $1`, [userId]);
  return rows[0]?.username || rows[0]?.first_name || "A friend";
}

/**
 * Donor side: commit one of today's spare miles to a friend who is holding a
 * token and has a day worth saving. Creates a PENDING offer — the friend's
 * token is theirs to spend, so nothing is covered until they say yes.
 */
export async function offerStreakAssist(
  donorId: string,
  recipientId: string,
): Promise<AssistExchangeResult> {
  const ex = await loadExchange(donorId, recipientId);
  if (!ex.ok) return { status: ex.status };

  const budget = await getDonationBudget(donorId, ex.donorRow, ex.donorToday);
  if (budget.remaining < 1) return { status: "no_miles" };

  const rows = await db.query<{ id: string }>(
    `INSERT INTO streak_assist_offers
       (donor_id, recipient_id, initiator, donor_date, target_date)
     VALUES ($1, $2, 'donor', $3::date, $4::date)
     ON CONFLICT DO NOTHING
     RETURNING id`,
    [donorId, recipientId, ex.donorToday, ex.target.local_date],
  );
  if (rows.length === 0) return { status: "already_pending" };

  const display = await displayName(donorId);
  const dayWord = ex.target.kind === "today" ? "today" : "the day you missed";
  sendPush(recipientId, {
    title: `\u{1F91D} ${display} ran you a mile`,
    body: `They went a mile past their goal for you. Use your Streak Assist to save ${dayWord}?`,
    type: "streak_assist_offer",
    data: {
      offer_id: rows[0].id,
      user_id: donorId,
      local_date: ex.target.local_date,
      restored_streak: String(ex.target.restored_streak),
    },
  }).catch((e: any) =>
    console.error("[StreakFeatures] offer push failed:", e?.message ?? e),
  );

  return {
    status: "ok",
    offer_id: rows[0].id,
    target_date: ex.target.local_date,
    restored_streak: ex.target.restored_streak,
    applied: false,
  };
}

/**
 * Recipient side: ask a friend to donate a mile. The donor's mile is only
 * committed if and when they accept, so `donor_date` stays NULL here — an
 * unanswered ask costs nobody anything and doesn't eat the friend's budget.
 */
export async function requestStreakAssist(
  recipientId: string,
  donorId: string,
): Promise<AssistExchangeResult> {
  const ex = await loadExchange(donorId, recipientId);
  if (!ex.ok) {
    // Same guard set, but the caller is the one holding (or missing) the token.
    return { status: ex.status === "friend_no_token" ? "no_token" : ex.status };
  }

  const rows = await db.query<{ id: string }>(
    `INSERT INTO streak_assist_offers
       (donor_id, recipient_id, initiator, target_date)
     VALUES ($1, $2, 'recipient', $3::date)
     ON CONFLICT DO NOTHING
     RETURNING id`,
    [donorId, recipientId, ex.target.local_date],
  );
  if (rows.length === 0) return { status: "already_pending" };

  const display = await displayName(recipientId);
  sendPush(donorId, {
    title: `\u{1F91D} ${display} needs a mile`,
    body: `Run a mile past your goal today and you can save their ${ex.target.restored_streak}-day streak.`,
    type: "streak_assist_request",
    data: {
      offer_id: rows[0].id,
      user_id: recipientId,
      local_date: ex.target.local_date,
      restored_streak: String(ex.target.restored_streak),
    },
  }).catch((e: any) =>
    console.error("[StreakFeatures] request push failed:", e?.message ?? e),
  );

  return {
    status: "ok",
    offer_id: rows[0].id,
    target_date: ex.target.local_date,
    restored_streak: ex.target.restored_streak,
    applied: false,
  };
}

/**
 * Answer whichever half of an exchange is waiting on you. Declining just
 * closes the row (freeing the donor's mile); accepting re-validates BOTH
 * halves from scratch — an offer can sit unanswered while the recipient runs
 * the day, or the donor's miles get re-synced downward — and only then writes
 * the coverage row.
 */
export async function respondToAssistOffer(
  userId: string,
  offerId: string,
  accept: boolean,
): Promise<AssistExchangeResult> {
  if (!streakFeaturesGloballyEnabled()) return { status: "disabled" };

  const rows = await db.query<{
    id: string;
    donor_id: string;
    recipient_id: string;
    initiator: string;
    target_date: string;
    donor_date: string | null;
  }>(
    `SELECT id, donor_id, recipient_id, initiator,
            to_char(target_date, 'YYYY-MM-DD') AS target_date,
            to_char(donor_date, 'YYYY-MM-DD') AS donor_date
     FROM streak_assist_offers
     WHERE id = $1 AND status = 'pending'`,
    [offerId],
  );
  const offer = rows[0];
  if (!offer) return { status: "not_found" };

  // Only the side that DIDN'T open it gets to answer.
  const responder = offer.initiator === "donor" ? offer.recipient_id : offer.donor_id;
  if (responder !== userId) return { status: "forbidden" };

  if (!accept) {
    await db.query(
      `UPDATE streak_assist_offers
       SET status = 'declined', resolved_at = NOW()
       WHERE id = $1 AND status = 'pending'`,
      [offerId],
    );
    return {
      status: "ok",
      offer_id: offerId,
      target_date: offer.target_date,
      restored_streak: 0,
      applied: false,
    };
  }

  const ex = await loadExchange(offer.donor_id, offer.recipient_id);
  if (!ex.ok) {
    return {
      status:
        ex.status === "friend_no_token" && userId === offer.recipient_id
          ? "no_token"
          : ex.status,
    };
  }

  const check = await validateTarget(
    offer.recipient_id,
    ex.recipientRow,
    offer.target_date,
  );
  if (!check.ok) return { status: check.reason };

  // The donor's mile, re-checked from scratch either way — a workout can be
  // edited or deleted between the offer and the answer, and a pending offer
  // must not be able to write coverage the donor no longer has miles for.
  if (offer.initiator === "recipient") {
    // Nothing committed yet: this accept is what charges today's mile.
    const budget = await getDonationBudget(
      offer.donor_id,
      ex.donorRow,
      ex.donorToday,
    );
    if (budget.remaining < 1) return { status: "no_miles" };
  } else {
    // Already committed, so THIS row is inside `used` — the question is
    // whether that day's miles still cover everything promised from them.
    // Bucketed on the offer's own donor_date, not today: an offer answered
    // after midnight is still backed by the mile that was actually run.
    const budget = await getDonationBudget(
      offer.donor_id,
      ex.donorRow,
      offer.donor_date ?? ex.donorToday,
    );
    if (budget.allowed < budget.used) return { status: "no_miles" };
  }

  const inserted = await insertCoverage(
    offer.recipient_id,
    offer.target_date,
    "streak_assist",
    ex.donorToday,
    offer.donor_id,
  );
  if (!inserted) return { status: "already_saved" };

  const recipientToday = await getUserLocalToday(offer.recipient_id);
  await db.query(
    // The RECIPIENT's token pays for the coverage — resetting their meter
    // window is what spends it.
    `UPDATE users SET streak_assist_last_used = $1::date WHERE user_id = $2`,
    [recipientToday, offer.recipient_id],
  );
  await db.query(
    `UPDATE streak_assist_offers
     SET status = 'accepted', resolved_at = NOW(), donor_date = COALESCE(donor_date, $2::date)
     WHERE id = $1`,
    [offerId, ex.donorToday],
  );
  // Any other offer aimed at the day just covered is dead — close it so it
  // stops holding its donor's mile.
  await db.query(
    `UPDATE streak_assist_offers
     SET status = 'expired', resolved_at = NOW()
     WHERE recipient_id = $1 AND target_date = $2::date AND status = 'pending'`,
    [offer.recipient_id, offer.target_date],
  );

  const restored = await refreshCurrentStreak(offer.recipient_id);

  const [donorName, recipientName] = await Promise.all([
    displayName(offer.donor_id),
    displayName(offer.recipient_id),
  ]);
  // Tell the side that wasn't here. When the recipient accepted, the donor
  // learns their mile landed; when the donor accepted a request, the recipient
  // learns their streak is back.
  const notifyId =
    userId === offer.recipient_id ? offer.donor_id : offer.recipient_id;
  const push: Parameters<typeof sendPush>[1] =
    notifyId === offer.donor_id
      ? {
          title: `\u{1F91D} ${recipientName} used your mile`,
          body: `Their ${restored}-day streak is back because you ran the extra one.`,
          type: "streak_assist_accepted",
          data: { user_id: offer.recipient_id, local_date: offer.target_date },
        }
      : {
          title: `\u{1F91D} ${donorName} saved your streak!`,
          body: `Your ${restored}-day streak is back — go keep it alive.`,
          type: "streak_assisted",
          data: { user_id: offer.donor_id, local_date: offer.target_date },
        };
  sendPush(notifyId, push).catch((e: any) =>
    console.error("[StreakFeatures] accept push failed:", e?.message ?? e),
  );

  return {
    status: "ok",
    offer_id: offerId,
    target_date: offer.target_date,
    restored_streak: restored,
    applied: true,
  };
}

export interface PendingAssistOffer {
  offer_id: string;
  /** 'donor' — someone offered you a mile; 'recipient' — someone asked for one. */
  initiator: string;
  /** The other person. */
  user_id: string;
  username: string | null;
  first_name: string | null;
  profile_image_url: string | null;
  target_date: string;
  restored_streak: number;
  created_at: string;
}

/**
 * Offers waiting on THIS user's answer — the app-entry popup. Rides on the
 * status payload rather than its own endpoint, since every surface that would
 * show it already refreshes status.
 *
 * Dead offers are filtered here rather than swept: an offer is only as alive
 * as its target day, and `validateTarget` is the same check the accept runs,
 * so nothing can be listed that the accept would then refuse.
 */
export async function getPendingAssistOffers(
  userId: string,
): Promise<PendingAssistOffer[]> {
  const rows = await db.query<{
    id: string;
    initiator: string;
    donor_id: string;
    recipient_id: string;
    other_id: string;
    username: string | null;
    first_name: string | null;
    profile_image_url: string | null;
    target_date: string;
    created_at: string;
  }>(
    `SELECT o.id, o.initiator, o.donor_id, o.recipient_id,
            u.user_id AS other_id, u.username, u.first_name, u.profile_image_url,
            to_char(o.target_date, 'YYYY-MM-DD') AS target_date,
            to_char(o.created_at, 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS created_at
     FROM streak_assist_offers o
     JOIN users u ON u.user_id = CASE WHEN o.initiator = 'donor'
                                      THEN o.donor_id ELSE o.recipient_id END
     WHERE o.status = 'pending'
       AND ((o.initiator = 'donor' AND o.recipient_id = $1)
         OR (o.initiator = 'recipient' AND o.donor_id = $1))
       AND o.target_date >= (CURRENT_DATE - ${ASSIST_RESCUE_WINDOW_DAYS + 1})
       AND NOT EXISTS (
         SELECT 1 FROM user_blocks b
         WHERE (b.blocker_id = $1 AND b.blocked_id = u.user_id)
            OR (b.blocker_id = u.user_id AND b.blocked_id = $1)
       )
     ORDER BY o.created_at DESC
     LIMIT 10`,
    [userId],
  );

  const live: PendingAssistOffer[] = [];
  for (const row of rows) {
    const recipientRow = await getStreakFeatureRow(row.recipient_id);
    if (!recipientRow?.streak_features_at) continue;
    const check = await validateTarget(
      row.recipient_id,
      recipientRow,
      row.target_date,
    );
    if (!check.ok) continue;
    live.push({
      offer_id: row.id,
      initiator: row.initiator,
      user_id: row.other_id,
      username: row.username,
      first_name: row.first_name,
      profile_image_url: row.profile_image_url,
      target_date: row.target_date,
      restored_streak: check.restored_streak,
      created_at: row.created_at,
    });
  }
  return live;
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
  // `source_username` is the assist GIVER, so a client can say "alex saved
  // this day" rather than a bare "covered". Additive to the object; shipped
  // clients ignore the extra key.
  frozen_dates: {
    local_date: string;
    kind: string;
    source_username: string | null;
  }[];
  natural_streak: boolean;
  streak_at_risk: boolean;
  /**
   * The caller's OWN day a donated mile could cover, if any. Present so the
   * client can offer "ask a friend for a mile" at the one moment it means
   * something — without it the app has to guess from the streak number, which
   * says nothing about whether a single coverage row would reconnect.
   */
  my_savable_day: {
    local_date: string;
    kind: SavableTarget["kind"];
    restored_streak: number;
  } | null;
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

  const coverage = await db.query<{
    local_date: string;
    kind: string;
    source_username: string | null;
  }>(
    `SELECT to_char(sc.local_date, 'YYYY-MM-DD') AS local_date, sc.kind,
            su.username AS source_username
     FROM streak_coverage sc
     LEFT JOIN users su ON su.user_id = sc.source_user
     WHERE sc.user_id = $1 AND sc.local_date >= $2::date
     ORDER BY sc.local_date DESC`,
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
    // Only worth reporting when they're holding the token that would pay for
    // it — an ask they can't complete is worse than no ask.
    my_savable_day: meters.streak_assist.held
      ? await getSavableTarget(userId, userToday, row).then((t) =>
          t
            ? {
                local_date: t.local_date,
                kind: t.kind,
                restored_streak: t.restored_streak,
              }
            : null,
        )
      : null,
  };
}

/**
 * Why the broken user could still fix this themselves. Purely informational —
 * it never blocks the Assist, it just lets the giver's confirmation sheet say
 * "they can still earn this back today" before a token is spent.
 */
export type SelfRecovery = "double_down" | "streak_save" | null;

export interface AssistableFriend {
  user_id: string;
  username: string | null;
  first_name: string | null;
  last_name: string | null;
  profile_image_url: string | null;
  /** The day a donated mile would cover. */
  target_date: string;
  /** 'missed' — already lost; 'today' — they still have hours to run it. */
  target_kind: SavableTarget["kind"];
  prior_streak: number;
  /** The streak the friend ENDS UP with once this day is covered. */
  restored_streak: number;
  /** This caller's standing offer to them: 'none' | 'pending' | 'accepted'. */
  offer_status: string;
  offer_id: string | null;
}

/**
 * Friends who are holding an Assist token and have a day a donated mile could
 * cover — the friends-list donate section. Both halves are checked here: a
 * friend with a broken streak and no token can't be helped this way, and the
 * list would just advertise a POST that 409s.
 *
 * ONE query for up to 50 friends (their local today, their last 4 days and any
 * standing offer, as LATERALs; the Assist allowance is a plain date predicate)
 * and then at most one `streakEndingAt` per actual candidate. The previous
 * version walked five queries per friend before it could rule any of them out,
 * which was ~250 for a list that is usually empty.
 *
 * `self_recovery` is deliberately NOT computed here — it needs two more meters
 * per friend and only matters once someone is looking at a specific rescue.
 * `getFriendRescueStatus` (the profile/confirm read) carries it.
 *
 * ponytail: capped at 50 friends; whoever needs a 51st can donate from the
 * friend's profile, which reads live.
 */
export async function getAssistableFriends(
  userId: string,
): Promise<AssistableFriend[]> {
  const rows = await db.query<{
    user_id: string;
    username: string | null;
    first_name: string | null;
    last_name: string | null;
    profile_image_url: string | null;
    friend_today: string;
    ok_days: string[] | null;
    offer_id: string | null;
    offer_status: string | null;
    offer_target: string | null;
  }>(
    `SELECT u.user_id, u.username, u.first_name, u.last_name, u.profile_image_url,
            to_char(t.today, 'YYYY-MM-DD') AS friend_today,
            ok.days AS ok_days,
            o.id AS offer_id, o.status AS offer_status,
            o.target_date AS offer_target
     FROM friendships f
     JOIN users u ON u.user_id = f.friend_id
     CROSS JOIN LATERAL (
       SELECT (NOW() + (COALESCE((
         SELECT w.timezone_offset FROM workouts w
         WHERE w.user_id = u.user_id
         ORDER BY w.device_end_date DESC LIMIT 1
       ), 0) || ' minutes')::interval)::date AS today
     ) t
     LEFT JOIN LATERAL (
       SELECT array_agg(x.d) AS days FROM (
         SELECT to_char(w.local_date, 'YYYY-MM-DD') AS d FROM workouts w
          WHERE w.user_id = u.user_id AND w.deleted_at IS NULL
            AND w.exclusion_reason IS NULL
            AND w.local_date > t.today - 4 AND w.local_date <= t.today
          GROUP BY w.local_date HAVING SUM(w.distance) >= 0.95
         UNION
         SELECT to_char(sc.local_date, 'YYYY-MM-DD') FROM streak_coverage sc
          WHERE sc.user_id = u.user_id AND sc.local_date > t.today - 4
       ) x
     ) ok ON TRUE
     LEFT JOIN LATERAL (
       -- Carries its target_date out so the caller can check it against the
       -- day actually in play: yesterday's ACCEPTED offer must not read as
       -- "already offered" for a fresh day this friend needs covering.
       SELECT id, status, to_char(target_date, 'YYYY-MM-DD') AS target_date
       FROM streak_assist_offers
        WHERE donor_id = $1 AND recipient_id = u.user_id
          AND status IN ('pending', 'accepted')
        ORDER BY created_at DESC LIMIT 1
     ) o ON TRUE
     WHERE f.user_id = $1 AND f.status = 'accepted'
       AND u.streak_features_at IS NOT NULL
       -- Holding an Assist is now just a date: never spent one, or spent one
       -- at least ${STREAK_ASSIST_TARGET_DAYS} days ago. Same rule as
       -- assistDaysElapsed(), cheap enough to state right here instead of
       -- inlining a meter subquery per friend.
       AND (u.streak_assist_last_used IS NULL
            OR u.streak_assist_last_used <= t.today - ${STREAK_ASSIST_TARGET_DAYS})
       AND NOT EXISTS (
         SELECT 1 FROM user_blocks b
         WHERE (b.blocker_id = $1 AND b.blocked_id = u.user_id)
            OR (b.blocker_id = u.user_id AND b.blocked_id = $1)
       )
     LIMIT 50`,
    [userId],
  );

  const out: AssistableFriend[] = [];
  for (const row of rows) {
    const okDays = new Set(row.ok_days ?? []);
    const ok = (d: string) => okDays.has(d);
    const pick = pickTargetDay(row.friend_today, ok);
    if (!pick) continue;

    const prior = await streakEndingAt(
      row.user_id,
      dateStrMinus(pick.local_date, 1),
    );
    if (prior < 1) continue;

    out.push({
      user_id: row.user_id,
      username: row.username,
      first_name: row.first_name,
      last_name: row.last_name,
      profile_image_url: row.profile_image_url,
      target_date: pick.local_date,
      target_kind: pick.kind,
      prior_streak: prior,
      restored_streak: projectRestoredStreak(
        pick.local_date,
        row.friend_today,
        prior,
        ok,
      ),
      // Only an offer aimed at THIS day counts as already offered.
      offer_status:
        row.offer_target === pick.local_date ? (row.offer_status ?? "none") : "none",
      offer_id: row.offer_target === pick.local_date ? row.offer_id : null,
    });
  }
  // A day already lost is more urgent than one they can still go run.
  out.sort((a, b) =>
    a.target_kind === b.target_kind ? 0 : a.target_kind === "missed" ? -1 : 1,
  );
  return out.slice(0, 20);
}

export interface FriendRescueStatus {
  /** The caller could donate a mile to this friend right now. */
  available: boolean;
  /** Present whenever there's a day in play — what a mile would cover. */
  target_date?: string;
  /** 'missed' — already lost; 'today' — they can still go run it. */
  target_kind?: SavableTarget["kind"];
  /** The run that ended at the miss (what broke). */
  prior_streak?: number;
  /** What the friend's streak becomes once it's covered. */
  restored_streak?: number;
  /** The friend's own token that could still fix this. Informational only. */
  self_recovery?: SelfRecovery;
  /** The friend holds the Assist token this would spend. */
  friend_holds_assist: boolean;
  /** The caller's miles past goal today, and what's left of them. */
  viewer_budget: DonationBudget;
  /** An exchange already in flight between these two: 'pending' | 'accepted'. */
  offer_status?: string;
  offer_id?: string;
  /**
   * Why nothing is offered, when `available` is false.
   *
   * `gap_too_wide` / `window_passed` mean a break EXISTS but no single
   * coverage row can bring it back — distinct from `no_savable_day`, which
   * means there's nothing wrong with them at all. The client renders those two
   * as an explanation rather than as silence: "no rescue possible" and "this
   * feature is broken" looked identical before, which is how a friend three
   * days into a gap read as a bug.
   *
   * `friend_no_token` and `no_miles` are the two halves of the price, and both
   * are recoverable — the friend can bank 20 extra miles, the caller can go
   * run one more today — so they're reported as state, not as failure.
   */
  reason?:
    | "disabled"
    | "not_enrolled"
    | "friend_not_enrolled"
    | "forbidden"
    | "no_savable_day"
    | "gap_too_wide"
    | "window_passed"
    | "friend_no_token"
    | "no_miles"
    | "self";
}

const EMPTY_BUDGET: DonationBudget = {
  goal_miles: 0,
  today_miles: 0,
  allowed: 0,
  used: 0,
  remaining: 0,
};

const NO_RESCUE = (
  reason: FriendRescueStatus["reason"],
): FriendRescueStatus => ({
  available: false,
  friend_holds_assist: false,
  viewer_budget: EMPTY_BUDGET,
  reason,
});

/**
 * Everything one friend's profile needs to render (or explain the absence of)
 * the Donate a Mile CTA. Deliberately a per-friend read rather than a field on
 * the status payload: the profile needs it for a friend the caller can't help
 * YET, and it answers for a friend who isn't in the (token-holders-only)
 * assistable list at all.
 *
 * The CTA is only `available` when BOTH halves are in hand — the friend's
 * token and the caller's spare mile — but every other field is still filled
 * in, so the button can say which half is missing instead of vanishing.
 */
export async function getFriendRescueStatus(
  viewerId: string,
  friendId: string,
): Promise<FriendRescueStatus> {
  if (!streakFeaturesGloballyEnabled()) return NO_RESCUE("disabled");
  if (viewerId === friendId) return NO_RESCUE("self");

  const [viewerRow, friendRow] = await Promise.all([
    getStreakFeatureRow(viewerId),
    getStreakFeatureRow(friendId),
  ]);
  if (!viewerRow?.streak_features_at) return NO_RESCUE("not_enrolled");

  const viewerToday = await getUserLocalToday(viewerId);
  const budget = await getDonationBudget(viewerId, viewerRow, viewerToday);

  // How far gone is this friend's streak? Computed once and reused for every
  // "no, and here's why" answer below. The profile renders NOTHING when a
  // rescue isn't possible, so a vague reason is indistinguishable from the
  // feature being broken — which is exactly how it read in practice.
  const friendToday = await getUserLocalToday(friendId);
  const facts = await recentDayFacts(friendId, dateStrMinus(friendToday, 4));
  const dayOk = (d: string) => facts.qualified.has(d) || facts.covered.has(d);
  const d1 = dateStrMinus(friendToday, 1);
  const d2 = dateStrMinus(friendToday, 2);
  const multiDayGap = !dayOk(d1) && !dayOk(d2);

  // An un-enrolled friend can't be covered (their streak walk is the legacy
  // one and would never see the coverage row). Report that only when they
  // ACTUALLY have a day in play, so the profile can say "they need the update"
  // at the one moment it matters instead of on every friend who hasn't updated.
  if (!friendRow?.streak_features_at) {
    return {
      available: false,
      friend_holds_assist: false,
      viewer_budget: budget,
      reason: pickTargetDay(friendToday, dayOk)
        ? "friend_not_enrolled"
        : multiDayGap
          ? "gap_too_wide"
          : "no_savable_day",
    };
  }

  if (!(await friendshipAllowed(viewerId, friendId))) {
    return {
      available: false,
      friend_holds_assist: false,
      viewer_budget: budget,
      reason: "forbidden",
    };
  }

  const friendMeters = await getMeters(friendId, friendRow, friendToday);
  const base = {
    friend_holds_assist: friendMeters.streak_assist.held,
    viewer_budget: budget,
  };

  const target = await getSavableTarget(friendId, friendToday, friendRow);
  if (!target) {
    return {
      ...base,
      available: false,
      reason: multiDayGap ? "gap_too_wide" : "no_savable_day",
    };
  }
  if (target.local_date < dateStrMinus(friendToday, ASSIST_RESCUE_WINDOW_DAYS)) {
    return { ...base, available: false, reason: "window_passed" };
  }

  const existing = await db.query<{ id: string; status: string }>(
    `SELECT id, status FROM streak_assist_offers
     WHERE donor_id = $1 AND recipient_id = $2 AND target_date = $3::date
       AND status IN ('pending', 'accepted')
     ORDER BY created_at DESC LIMIT 1`,
    [viewerId, friendId, target.local_date],
  );

  const detail = {
    ...base,
    target_date: target.local_date,
    target_kind: target.kind,
    prior_streak: target.prior_streak,
    restored_streak: target.restored_streak,
    self_recovery: target.self_recovery,
    offer_status: existing[0]?.status,
    offer_id: existing[0]?.id,
  };

  if (!friendMeters.streak_assist.held) {
    return { ...detail, available: false, reason: "friend_no_token" };
  }
  if (budget.remaining < 1) {
    return { ...detail, available: false, reason: "no_miles" };
  }
  return { ...detail, available: existing.length === 0 };
}

/**
 * Which single day (if any) an Assist may cover, given what's intact around
 * the user's today. Pure, so the per-user read and the batched friends list
 * decide it from the same three shapes instead of drifting apart — the list
 * feeds it a preloaded set, the read feeds it a live query.
 */
function pickTargetDay(
  userToday: string,
  ok: (d: string) => boolean,
): {
  local_date: string;
  kind: SavableTarget["kind"];
  ddWindowOpen: boolean;
} | null {
  const d1 = dateStrMinus(userToday, 1);
  const d2 = dateStrMinus(userToday, 2);
  const d3 = dateStrMinus(userToday, 3);
  if (!ok(d1) && ok(d2))
    return { local_date: d1, kind: "missed", ddWindowOpen: true };
  if (ok(d1) && !ok(d2) && ok(d3))
    return { local_date: d2, kind: "missed", ddWindowOpen: false };
  if (ok(d1) && !ok(userToday))
    return { local_date: userToday, kind: "today", ddWindowOpen: false };
  return null;
}

interface SavableTarget {
  local_date: string;
  /** 'missed' — the day is already lost; 'today' — still winnable by running. */
  kind: "missed" | "today";
  prior_streak: number;
  restored_streak: number;
  self_recovery: SelfRecovery;
}

/**
 * The streak the user would be sitting on the moment `missedDay` gets covered:
 * the run that ended at the miss, plus the covered day itself, plus every
 * intact day since (today included when they've already run it). This — not
 * `prior_streak` — is the number a giver is actually buying, and it's what the
 * confirmation sheet shows before a token is spent.
 */
function projectRestoredStreak(
  missedDay: string,
  userToday: string,
  priorStreak: number,
  ok: (d: string) => boolean,
): number {
  let total = priorStreak + 1; // + the covered day
  let cursor = dateStrPlus(missedDay, 1);
  while (cursor <= userToday && ok(cursor)) {
    total++;
    cursor = dateStrPlus(cursor, 1);
  }
  return total;
}

/**
 * The one day an Assist could cover for this user right now, derived live
 * (i.e. before/without a stamped `streak_events` row).
 *
 * Three shapes, in priority order — a lost day always outranks a pending one:
 *   - yesterday missed, older streak intact → the classic break.
 *   - yesterday made up but the day before missed → the hole a Double Down
 *     window left behind.
 *   - nothing missed, but TODAY isn't run yet → bank today. Not a rescue but
 *     the same machinery: this is what lets a runner hand off a spare mile in
 *     the evening to someone who is about to lose a streak at midnight, rather
 *     than everyone waiting for the break to actually happen.
 *
 * Deliberately does NOT hide a break while the user still holds a Double Down
 * or a Streak Save. It used to, and that left a dead zone: the sweep sees an
 * open Double Down window, returns "waiting", and for the rest of that day the
 * streak reads broken everywhere while nobody can do anything about it. The
 * token they hold is reported as `self_recovery` instead, and the confirmation
 * sheet says so. A `today` target has no self-recovery to report — the way out
 * is to go run, which is not a token.
 */
async function getSavableTarget(
  userId: string,
  userToday: string,
  row: StreakFeatureUserRow,
): Promise<SavableTarget | null> {
  const facts = await recentDayFacts(userId, dateStrMinus(userToday, 4));
  const ok = (d: string) => facts.qualified.has(d) || facts.covered.has(d);

  const pick = pickTargetDay(userToday, ok);
  if (!pick) return null;
  const { local_date: missedDay, kind, ddWindowOpen } = pick;

  let selfRecovery: SelfRecovery = null;
  if (kind === "missed") {
    const meters = await getMeters(userId, row, userToday);
    selfRecovery =
      ddWindowOpen && meters.double_down.held
        ? "double_down"
        : meters.streak_save.held
          ? "streak_save"
          : null;
  }

  const prior = await streakEndingAt(userId, dateStrMinus(missedDay, 1));
  if (prior < 1) return null;
  return {
    local_date: missedDay,
    kind,
    prior_streak: prior,
    restored_streak: projectRestoredStreak(missedDay, userToday, prior, ok),
    self_recovery: selfRecovery,
  };
}

/**
 * Restored-streak projection for a break we already have stamped, plus whether
 * covering it actually reconnects. `bridged` mirrors the gap check
 * `giveStreakAssist` enforces (tokens never partially bridge) — without it a
 * stamped break with a second hole after it would advertise a Save Streak CTA
 * that the POST then rejects with `gap_too_wide`.
 *
 * `prior` is RE-DERIVED here rather than read off `streak_events.prior_streak`.
 * The stored column is a snapshot taken by `recordBreak` at stamp time, and
 * every row written before the `streakEndingAt` island fix holds a `1` — so
 * trusting it would keep serving "back to 2 days" to real users long after the
 * query was corrected. Re-deriving is also just more truthful: a late-syncing
 * Watch workout can land on a day BEFORE the miss and legitimately lengthen the
 * run being bought. Days at or before the miss are settled history, so this is
 * stable across reads within a day.
 */
async function stampedBreakDetail(
  userId: string,
  missedDay: string,
): Promise<{
  prior: number;
  restored: number;
  bridged: boolean;
  inWindow: boolean;
}> {
  const userToday = await getUserLocalToday(userId);
  const facts = await recentDayFacts(userId, missedDay);
  const ok = (d: string) => facts.qualified.has(d) || facts.covered.has(d);

  let bridged = true;
  let cursor = dateStrPlus(missedDay, 1);
  while (cursor < userToday) {
    if (!ok(cursor)) {
      bridged = false;
      break;
    }
    cursor = dateStrPlus(cursor, 1);
  }

  const prior = await streakEndingAt(userId, dateStrMinus(missedDay, 1));

  return {
    prior,
    restored: projectRestoredStreak(missedDay, userToday, prior, ok),
    bridged,
    // The list query bounds break age by the SERVER's CURRENT_DATE; the give
    // call bounds it by the FRIEND's local today. For anyone west of UTC those
    // are different days, so a break can pass the list and then come back
    // `window_passed`. Re-check it against the friend's own clock.
    inWindow: missedDay >= dateStrMinus(userToday, ASSIST_RESCUE_WINDOW_DAYS),
  };
}
