import { PostgresService } from "./DbService.js";
import {
  countedWorkoutSql,
  MAX_PLAUSIBLE_MILE_SECONDS,
} from "./mileTime.js";
import { DAILY_GOAL_TOLERANCE } from "./workoutService.js";
import {
  pbSplitFilterSql,
  servedWeekResult,
  sundayWeekStartSql,
} from "./weeklyChallengeService.js";
import { readStoredStreak, streakEndingAt } from "./streakFeatureCore.js";
import { getBlockedIds } from "./moderationService.js";
import { isUserInQuietHours, sendPush } from "./pushNotificationService.js";
import {
  CLIENT_FEATURES,
  supportsClientFeatureSql,
} from "./clientFeatures.js";

const db = PostgresService.getInstance();

/**
 * Weekly Recap: "your week in review", served by
 * `GET /users/:id/weekly-recap` and announced by a Saturday-evening push.
 *
 * THE WEEK is the weekly challenge's week — Sunday→Saturday in the user's own
 * timezone (`sundayWeekStartSql`, same offset COALESCE as `weekWindowForUser`)
 * — so "this week" means one thing on every surface. Days are `local_date`,
 * and every figure is COUNTED miles (`countedWorkoutSql`): never `feed_role`,
 * which decides what the feed shows, not what counts.
 */

/** The local hour the recap push goes out on the week's last day. */
export const WEEKLY_RECAP_LOCAL_HOUR = 19;
/** …moved here when the daily reminder already owns 19:00 (one push an hour). */
export const WEEKLY_RECAP_ALT_HOUR = 20;
/**
 * From this local hour on the week's LAST day, the default recap is the week
 * still running (it is nearly over, and the push that points at it has gone
 * out); before it, the default is the most recently completed week.
 */
export const WEEKLY_RECAP_OPEN_HOUR = 17;
/** Saturday — the last day of a Sunday-start week (Postgres DOW). */
const WEEK_LAST_DOW = 6;

/** How far back "Best week in N weeks" looks. */
const BEST_WEEK_LOOKBACK = 12;

export function weeklyRecapDisabled(): boolean {
  const v = process.env.WEEKLY_RECAP_DISABLED;
  return v === "true" || v === "1";
}

export class WeeklyRecapRequestError extends Error {
  constructor(
    public code: string,
    message: string,
  ) {
    super(message);
  }
}

export interface WeeklyRecapDay {
  date: string;
  miles: number;
  goal_met: boolean;
  covered: boolean;
}

export interface WeeklyRecapFriend {
  user_id: string;
  username: string | null;
  first_name: string | null;
  profile_image_url: string | null;
  miles: number;
  is_me: boolean;
}

export interface WeeklyRecap {
  week_start: string;
  week_end: string;
  is_complete: boolean;
  unit_note: "miles";
  total_miles: number;
  prior_week_miles: number | null;
  days: WeeklyRecapDay[];
  days_goal_met: number;
  goal_miles: number;
  workouts: number;
  total_duration_seconds: number;
  longest_workout_miles: number;
  fastest_mile_pace_seconds: number | null;
  current_streak: number;
  streak_at_week_start: number | null;
  weekly_challenge: {
    name: string;
    completed: boolean;
    value: number;
    target: number;
    unit: string;
    // Additive beyond the contract: lets the card draw the challenge's own art.
    challenge_key: string;
    icon: string;
  } | null;
  friends: {
    rank: number;
    of: number;
    top: WeeklyRecapFriend[];
  } | null;
  highlights: string[];
}

/** Plain date math on a "YYYY-MM-DD" string, in UTC so no timezone can shift it. */
function addDays(ymd: string, days: number): string {
  const [y, m, d] = ymd.split("-").map((n) => parseInt(n, 10));
  const date = new Date(Date.UTC(y, m - 1, d));
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

/** The Sunday on or before a "YYYY-MM-DD" date. */
function sundayOf(ymd: string): string {
  const [y, m, d] = ymd.split("-").map((n) => parseInt(n, 10));
  const date = new Date(Date.UTC(y, m - 1, d));
  return addDays(ymd, -date.getUTCDay());
}

const round2 = (n: number) => Math.round(n * 100) / 100;

/**
 * The user's local clock at `at`: today, the hour, and the Sunday that starts
 * this week. Same offset COALESCE as `weekWindowForUser` (preference, then the
 * latest workout's offset, then UTC). `AT TIME ZONE 'UTC'` pins the wall-clock
 * arithmetic so a session TimeZone can't move it.
 */
async function userClock(
  userId: string,
  at: Date,
): Promise<{ localToday: string; localHour: number; weekStart: string }> {
  const rows = await db.query<{
    local_today: string;
    local_hour: number;
    week_start: string;
  }>(
    `WITH tz AS (
			SELECT COALESCE(
				(SELECT ns.timezone_offset_minutes FROM notification_settings ns WHERE ns.user_id = $1::text),
				(SELECT w.timezone_offset FROM workouts w WHERE w.user_id = $1::text ORDER BY w.device_end_date DESC LIMIT 1),
				0
			) AS offset_minutes
		),
		local AS (
			SELECT (($2::timestamptz AT TIME ZONE 'UTC') + (tz.offset_minutes || ' minutes')::interval) AS ts FROM tz
		)
		SELECT
			local.ts::date::text AS local_today,
			EXTRACT(HOUR FROM local.ts)::int AS local_hour,
			${sundayWeekStartSql("local.ts")}::text AS week_start
		FROM local`,
    [userId, at.toISOString()],
  );
  const row = rows[0];
  return {
    localToday: row.local_today,
    localHour: Number(row.local_hour),
    weekStart: row.week_start,
  };
}

/**
 * Which week a recap read is about.
 *
 * Explicit `week_start`: any date is accepted and resolved to the Sunday of
 * its week (a client passing the push's `data.week_start` gets exactly that
 * week); a week that hasn't started yet in the user's timezone is a 400.
 *
 * Default: the CURRENT week once it is the week's last day and ≥ 17:00 local
 * (the push goes out at 19:00, so a read prompted by it lands on the week it
 * announced), otherwise the most recently COMPLETED week — on a Wednesday the
 * week in progress is three days of a story, the one before it is the recap.
 */
export async function resolveRecapWeek(
  userId: string,
  requested: string | undefined,
  at: Date = new Date(),
): Promise<{ weekStart: string; localToday: string }> {
  const clock = await userClock(userId, at);
  if (requested !== undefined) {
    if (
      !/^\d{4}-\d{2}-\d{2}$/.test(requested) ||
      Number.isNaN(Date.parse(`${requested}T00:00:00Z`)) ||
      new Date(`${requested}T00:00:00Z`).toISOString().slice(0, 10) !==
        requested
    ) {
      throw new WeeklyRecapRequestError(
        "invalid_week_start",
        "week_start must be a YYYY-MM-DD date",
      );
    }
    const weekStart = sundayOf(requested);
    if (weekStart > clock.weekStart) {
      throw new WeeklyRecapRequestError(
        "week_in_future",
        "That week hasn't started yet",
      );
    }
    return { weekStart, localToday: clock.localToday };
  }
  const lastDay = addDays(clock.weekStart, 6);
  const current =
    clock.localToday === lastDay && clock.localHour >= WEEKLY_RECAP_OPEN_HOUR;
  return {
    weekStart: current ? clock.weekStart : addDays(clock.weekStart, -7),
    localToday: clock.localToday,
  };
}

/**
 * The recap for one user's week. Every query is bounded to the user (or their
 * friend circle, capped) and to a fixed date range — the week, the week
 * before it, or the `BEST_WEEK_LOOKBACK` weeks behind it.
 */
export async function getWeeklyRecap(
  userId: string,
  requestedWeekStart?: string,
  at: Date = new Date(),
): Promise<WeeklyRecap> {
  const { weekStart, localToday } = await resolveRecapWeek(
    userId,
    requestedWeekStart,
    at,
  );
  const weekEnd = addDays(weekStart, 6);
  const counted = countedWorkoutSql("w");

  const [
    userRows,
    dayRows,
    aggRows,
    paceRows,
    historyRows,
    streak,
    streakAtStart,
    challenge,
    friends,
  ] = await Promise.all([
    db.query<{ goal_miles: string | number | null }>(
      `SELECT goal_miles FROM users WHERE user_id = $1::text`,
      [userId],
    ),
    db.query<{ date: string; miles: string | number; covered: boolean }>(
      `SELECT to_char(d.day, 'YYYY-MM-DD') AS date,
				COALESCE((SELECT SUM(w.distance) FROM workouts w
					WHERE w.user_id = $1::text AND w.local_date = d.day AND ${counted}), 0) AS miles,
				EXISTS (SELECT 1 FROM streak_coverage sc
					WHERE sc.user_id = $1::text AND sc.local_date = d.day) AS covered
			FROM (
				SELECT ($2::date + g.n) AS day FROM generate_series(0, 6) AS g(n)
			) d
			ORDER BY d.day`,
      [userId, weekStart],
    ),
    db.query<{
      workouts: number;
      total: string | number;
      duration: string | number;
      longest: string | number | null;
    }>(
      `SELECT COUNT(*)::int AS workouts,
				COALESCE(SUM(w.distance), 0) AS total,
				COALESCE(SUM(w.total_duration), 0) AS duration,
				MAX(w.distance) AS longest
			FROM workouts w
			WHERE w.user_id = $1::text
				AND w.local_date BETWEEN $2::date AND ($2::date + 6)
				AND ${counted}`,
      [userId, weekStart],
    ),
    db.query<{ p: string | number | null }>(
      `SELECT MIN(ws.split_pace) AS p
			FROM workout_splits ws
			JOIN workouts w ON w.workout_id = ws.workout_id
			WHERE w.user_id = $1::text
				AND w.local_date BETWEEN $2::date AND ($2::date + 6)
				AND ${pbSplitFilterSql("w", "ws")}
				AND ws.split_pace <= ${MAX_PLAUSIBLE_MILE_SECONDS}`,
      [userId, weekStart],
    ),
    // The weeks before this one (prior week + the best-week lookback), plus
    // the first counted day ever so a new account's empty past doesn't read
    // as weeks it "beat".
    db.query<{ week_start: string | null; miles: string | number | null; first_day: string | null }>(
      `WITH first AS (
				SELECT MIN(w.local_date) AS d FROM workouts w
				WHERE w.user_id = $1::text AND ${counted}
			)
			SELECT
				${sundayWeekStartSql("w.local_date")}::text AS week_start,
				SUM(w.distance) AS miles,
				(SELECT d::text FROM first) AS first_day
			FROM workouts w
			WHERE w.user_id = $1::text
				AND w.local_date BETWEEN ($2::date - ${7 * BEST_WEEK_LOOKBACK}) AND ($2::date - 1)
				AND ${counted}
			GROUP BY 1
			UNION ALL
			SELECT NULL, NULL, (SELECT d::text FROM first)`,
      [userId, weekStart],
    ),
    readStoredStreak(userId),
    streakEndingAt(userId, addDays(weekStart, -1)).catch(() => null),
    servedWeekResult(userId, weekStart, localToday),
    friendsBoard(userId, weekStart),
  ]);

  const rawGoal = Number(userRows[0]?.goal_miles ?? 1);
  // A goal of 0 makes `current >= goal * 0.95` vacuously true — clamp it.
  const goal = Number.isFinite(rawGoal) && rawGoal > 0 ? rawGoal : 1;

  const days: WeeklyRecapDay[] = dayRows.map((r) => {
    const miles = Number(r.miles) || 0;
    return {
      date: r.date,
      miles: round2(miles),
      goal_met: miles >= goal * DAILY_GOAL_TOLERANCE,
      covered: r.covered === true,
    };
  });
  const daysGoalMet = days.filter((d) => d.goal_met).length;

  const agg = aggRows[0];
  const total = Number(agg?.total ?? 0) || 0;
  const pace = paceRows[0]?.p;

  const history = new Map<string, number>();
  let firstDay: string | null = null;
  for (const r of historyRows) {
    if (r.first_day) firstDay = r.first_day;
    if (r.week_start) history.set(r.week_start, Number(r.miles) || 0);
  }
  const hadPastWorkouts = firstDay !== null && firstDay < weekStart;
  const priorStart = addDays(weekStart, -7);
  const priorMiles = hadPastWorkouts ? (history.get(priorStart) ?? 0) : null;

  const recap: WeeklyRecap = {
    week_start: weekStart,
    week_end: weekEnd,
    is_complete: weekEnd < localToday,
    unit_note: "miles",
    total_miles: round2(total),
    prior_week_miles: priorMiles === null ? null : round2(priorMiles),
    days,
    days_goal_met: daysGoalMet,
    goal_miles: goal,
    workouts: Number(agg?.workouts ?? 0),
    total_duration_seconds: Math.round(Number(agg?.duration ?? 0) || 0),
    longest_workout_miles: round2(Number(agg?.longest ?? 0) || 0),
    fastest_mile_pace_seconds:
      pace === null || pace === undefined ? null : Math.round(Number(pace)),
    current_streak: streak.streak,
    streak_at_week_start: streakAtStart,
    weekly_challenge: challenge
      ? {
          name: challenge.title,
          completed: challenge.completed,
          value: round2(challenge.value),
          target: Number(challenge.target),
          unit: challenge.unit,
          challenge_key: challenge.challenge_key,
          icon: challenge.icon,
        }
      : null,
    friends,
    highlights: [],
  };
  recap.highlights = highlightsFor(recap, history, firstDay);
  return recap;
}

/**
 * Up to three short, factual lines. No units (the client converts distances
 * and these are plain strings) and nothing that isn't literally in the numbers.
 */
function highlightsFor(
  recap: WeeklyRecap,
  history: Map<string, number>,
  firstDay: string | null,
): string[] {
  const out: string[] = [];
  const total = recap.total_miles;
  if (total <= 0) return out;

  if (recap.days_goal_met === 7) out.push("7 for 7");

  // Walk back week by week while this one beats them, never past the first
  // week the account has a counted workout in.
  if (firstDay !== null && firstDay < recap.week_start) {
    const firstWeek = sundayOf(firstDay);
    let beaten = 0;
    let reachedFirst = false;
    for (let k = 1; k <= BEST_WEEK_LOOKBACK; k++) {
      const wk = addDays(recap.week_start, -7 * k);
      if (wk < firstWeek) {
        reachedFirst = true;
        break;
      }
      if ((history.get(wk) ?? 0) >= total) break;
      beaten++;
      if (wk === firstWeek) {
        reachedFirst = true;
        break;
      }
    }
    if (beaten >= 3) {
      // Beat every week the account has ever had ⇒ "yet"; otherwise say how
      // far back it holds.
      out.push(reachedFirst ? "Your best week yet" : `Best week in ${beaten + 1} weeks`);
    }
  }

  const prior = recap.prior_week_miles;
  if (prior !== null && prior > 0 && total >= prior * 1.1) {
    out.push(`Up ${Math.round((total / prior - 1) * 100)}% on last week`);
  }

  if (recap.weekly_challenge?.completed) out.push("Weekly challenge complete");

  return out.slice(0, 3);
}

/**
 * The viewer's circle (accepted friends either direction, minus blocks, plus
 * the viewer), each measured over the VIEWER's week — per-friend windows
 * aren't comparable, the weekly leaderboard's rule. Null with no friends.
 */
async function friendsBoard(
  userId: string,
  weekStart: string,
): Promise<WeeklyRecap["friends"]> {
  const blocked = await getBlockedIds(userId);
  const rows = await db.query<{
    user_id: string;
    username: string | null;
    first_name: string | null;
    profile_image_url: string | null;
    miles: string | number;
  }>(
    `WITH circle AS (
			SELECT CASE WHEN f.user_id = $1::text THEN f.friend_id ELSE f.user_id END AS uid
			FROM friendships f
			WHERE (f.user_id = $1::text OR f.friend_id = $1::text) AND f.status = 'accepted'
			UNION
			SELECT $1::text
		)
		SELECT u.user_id, u.username, u.first_name, u.profile_image_url,
			COALESCE((SELECT SUM(w.distance) FROM workouts w
				WHERE w.user_id = u.user_id
					AND w.local_date BETWEEN $2::date AND ($2::date + 6)
					AND ${countedWorkoutSql("w")}), 0) AS miles
		FROM circle
		JOIN users u ON u.user_id = circle.uid
		WHERE u.user_id = $1::text OR NOT (u.user_id = ANY($3::text[]))
		ORDER BY (u.user_id = $1::text) DESC
		LIMIT 200`,
    [userId, weekStart, blocked],
  );
  if (rows.length <= 1) return null;

  const people: WeeklyRecapFriend[] = rows
    .map((r) => ({
      user_id: r.user_id,
      username: r.username,
      first_name: r.first_name,
      profile_image_url: r.profile_image_url,
      miles: round2(Number(r.miles) || 0),
      is_me: r.user_id === userId,
    }))
    .sort(
      (a, b) =>
        b.miles - a.miles ||
        (a.username ?? "").localeCompare(b.username ?? "") ||
        a.user_id.localeCompare(b.user_id),
    );
  const me = people.find((p) => p.is_me);
  if (!me) return null;
  // Standard competition ranking: level people share a place.
  const rank = 1 + people.filter((p) => p.miles > me.miles).length;
  const top = people.slice(0, 3);
  if (!top.some((p) => p.is_me)) top.push(me);
  return { rank, of: people.length, top };
}

// ─── The push ──────────────────────────────────────────────────────────────

export interface WeeklyRecapCandidate {
  user_id: string;
  week_start: string;
  local_date: string;
}

/**
 * Who is due a recap at `at`.
 *
 * Local clock on the week's LAST day (Saturday) at 19:00 — 20:00 when the
 * daily reminder is set to 19, since one hour carries one push — for users:
 *  - with the `weekly_recap_enabled` switch on (NULL = on);
 *  - holding a device that declared `weekly_recap_v1` (no fallback push: a
 *    build that can't open the recap would get a banner that goes nowhere);
 *  - with at least one COUNTED workout in the week (a "0 miles" recap is not
 *    sent; a lapse is the win-back reminder's job);
 *  - not already claimed for that week in `weekly_recap_log`.
 *
 * `at` is injectable so the check can pin the hour arithmetic against seeded
 * offsets (pattern: `lastCallCandidates`).
 */
export async function weeklyRecapCandidates(
  at: Date = new Date(),
): Promise<WeeklyRecapCandidate[]> {
  const rows = await db.query<WeeklyRecapCandidate>(
    `WITH base AS (
			SELECT
				u.user_id,
				COALESCE(
					ns.timezone_offset_minutes,
					(SELECT timezone_offset FROM workouts WHERE user_id = u.user_id ORDER BY device_end_date DESC LIMIT 1)
				) AS tz_offset,
				COALESCE(ns.daily_reminder_enabled, TRUE) AS reminder_on,
				COALESCE(ns.daily_reminder_hour, 18) AS reminder_hour
			FROM users u
			LEFT JOIN notification_settings ns ON ns.user_id = u.user_id
			WHERE COALESCE(ns.weekly_recap_enabled, TRUE) = TRUE
				AND ${supportsClientFeatureSql("u.user_id", CLIENT_FEATURES.weeklyRecapV1)}
		),
		local AS (
			SELECT b.*,
				(($1::timestamptz AT TIME ZONE 'UTC') + (b.tz_offset || ' minutes')::interval) AS local_now
			FROM base b
			WHERE b.tz_offset IS NOT NULL
		),
		due AS (
			SELECT l.user_id,
				l.local_now::date AS local_today,
				${sundayWeekStartSql("l.local_now")} AS week_start
			FROM local l
			WHERE EXTRACT(DOW FROM l.local_now) = ${WEEK_LAST_DOW}
				AND EXTRACT(HOUR FROM l.local_now) =
					CASE WHEN l.reminder_on AND l.reminder_hour = $2::int THEN $3::int ELSE $2::int END
		)
		SELECT d.user_id, d.week_start::text AS week_start, d.local_today::text AS local_date
		FROM due d
		WHERE NOT EXISTS (
				SELECT 1 FROM weekly_recap_log l
				WHERE l.user_id = d.user_id AND l.week_start = d.week_start
			)
			AND EXISTS (
				SELECT 1 FROM workouts w
				WHERE w.user_id = d.user_id
					AND w.local_date BETWEEN d.week_start AND (d.week_start + 6)
					AND ${countedWorkoutSql("w")}
			)`,
    [at.toISOString(), WEEKLY_RECAP_LOCAL_HOUR, WEEKLY_RECAP_ALT_HOUR],
  );
  return rows;
}

/** Title + body from the week's numbers. Factual; no health claims. */
export function weeklyRecapCopy(recap: WeeklyRecap): {
  title: string;
  body: string;
} {
  const miles = `${recap.total_miles.toFixed(1)} mi`;
  const title =
    recap.days_goal_met > 0
      ? `Your week: ${miles}, ${recap.days_goal_met} of 7 days${recap.days_goal_met === 7 ? " 🔥" : ""}`
      : `Your week: ${miles} over ${recap.workouts} workout${recap.workouts === 1 ? "" : "s"}`;
  const lead = recap.highlights[0];
  const body = lead
    ? `${lead}. Tap to see your recap and share it.`
    : "Tap to see your recap and share it.";
  return { title, body };
}

/**
 * Sends every recap due at `at`. Returns how many went out.
 *
 * Quiet hours are honoured by SKIPPING, never queueing: a recap parked for the
 * morning flush arrives on the next week's first day about a week that is
 * over. The claim (`weekly_recap_log`, PK user+week) is taken before the send,
 * so a crash costs one push rather than doubling one.
 */
export async function sendWeeklyRecaps(at: Date = new Date()): Promise<number> {
  if (weeklyRecapDisabled()) return 0;
  const candidates = await weeklyRecapCandidates(at);
  if (candidates.length === 0) return 0;

  let sent = 0;
  for (const c of candidates) {
    try {
      if (await isUserInQuietHours(c.user_id)) continue;
      const recap = await getWeeklyRecap(c.user_id, c.week_start, at);
      if (recap.workouts === 0) continue;

      const claimed = await db.query<{ user_id: string }>(
        `INSERT INTO weekly_recap_log (user_id, week_start)
				 VALUES ($1::text, $2::date)
				 ON CONFLICT DO NOTHING
				 RETURNING user_id`,
        [c.user_id, c.week_start],
      );
      if (claimed.length === 0) continue;

      await sendPush(c.user_id, {
        ...weeklyRecapCopy(recap),
        type: "weekly_recap",
        // Strings only: shipped inboxes decode `data` as [String: String].
        data: { week_start: recap.week_start },
      });
      sent++;
    } catch (err: any) {
      console.error(
        `[WeeklyRecap] Failed for user ${c.user_id}: ${err?.message ?? err}`,
      );
    }
  }
  if (sent > 0) console.log(`[WeeklyRecap] Sent ${sent} recap(s).`);
  return sent;
}
