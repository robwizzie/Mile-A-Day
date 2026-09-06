import { PostgresService } from "./DbService.js";
import { isUserInQuietHours, sendPush } from "./pushNotificationService.js";
import { refreshCurrentStreak } from "./leaderboardService.js";
import { DAILY_GOAL_TOLERANCE } from "./workoutService.js";

const db = PostgresService.getInstance();

/**
 * The local hour the last call goes out: two hours before midnight, which
 * is late enough that the day is genuinely at risk and early enough that a
 * mile is still a walk around the block, not a sprint.
 */
export const LAST_CALL_LOCAL_HOUR = 22;

export interface LastCallCandidate {
  user_id: string;
  /** users.current_streak as stored — re-verified before sending. */
  streak: number;
  local_date: string;
  goal_miles: number;
  today_miles: number;
}

/**
 * Who is two hours from losing a live streak right now.
 *
 * The daily reminder fires ONCE, at the user's chosen hour (6 PM by default),
 * only when the mile isn't done — and then nothing. A user who ignored it
 * heard nothing else before midnight, and for a streak app that silence is
 * the single most expensive one there is. This is the second, later voice:
 * only for people with a streak to lose (`current_streak > 0`), only when
 * today's counted miles are still under the goal, and only at local 22:00.
 *
 * The same hourly cron + local-hour predicate the daily reminder uses makes
 * it at most once per day per user. A user whose reminder hour IS 22 is
 * skipped — one push in that hour, never two — and the reminder switch
 * governs it (it is a reminder; Guideline 4.5.4 wants it controllable).
 *
 * `at` is injectable so the check can pin the hour arithmetic against
 * seeded timezone offsets instead of waiting for 10 PM somewhere.
 */
export async function lastCallCandidates(
  at: Date = new Date(),
): Promise<LastCallCandidate[]> {
  const rows = await db.query<{
    user_id: string;
    streak: number;
    local_date: string;
    goal_miles: string | number;
    today_miles: string | number;
  }>(
    `WITH user_tz AS (
			SELECT
				u.user_id,
				u.goal_miles,
				u.current_streak,
				COALESCE(
					ns.timezone_offset_minutes,
					(SELECT timezone_offset FROM workouts WHERE user_id = u.user_id ORDER BY device_end_date DESC LIMIT 1)
				) AS tz_offset,
				COALESCE(ns.daily_reminder_enabled, TRUE) AS daily_reminder_enabled,
				COALESCE(ns.daily_reminder_hour, 18) AS daily_reminder_hour
			FROM users u
			LEFT JOIN notification_settings ns ON ns.user_id = u.user_id
			WHERE u.current_streak > 0
		),
		local AS (
			SELECT t.*, ($1::timestamptz + (t.tz_offset || ' minutes')::interval) AS local_now
			FROM user_tz t
			WHERE t.tz_offset IS NOT NULL
		)
		SELECT l.user_id,
			l.current_streak::int AS streak,
			l.local_now::date::text AS local_date,
			l.goal_miles,
			COALESCE((SELECT SUM(w.distance) FROM workouts w
			  WHERE w.user_id = l.user_id
			    AND w.local_date = l.local_now::date
			    AND w.deleted_at IS NULL AND w.exclusion_reason IS NULL), 0) AS today_miles
		FROM local l
		WHERE l.daily_reminder_enabled = TRUE
		  AND EXTRACT(HOUR FROM l.local_now) = $2
		  AND l.daily_reminder_hour <> $2
		  AND EXISTS (SELECT 1 FROM device_tokens dt WHERE dt.user_id = l.user_id)
		  AND COALESCE((SELECT SUM(w.distance) FROM workouts w
			  WHERE w.user_id = l.user_id
			    AND w.local_date = l.local_now::date
			    AND w.deleted_at IS NULL AND w.exclusion_reason IS NULL), 0)
		      < l.goal_miles * $3`,
    [at.toISOString(), LAST_CALL_LOCAL_HOUR, DAILY_GOAL_TOLERANCE],
  );
  return rows.map((r) => ({
    user_id: r.user_id,
    streak: Number(r.streak),
    local_date: r.local_date,
    goal_miles: Number(r.goal_miles),
    today_miles: Number(r.today_miles ?? 0),
  }));
}

/** Short, specific, and about what's at stake — never about how late it is. */
export function lastCallCopy(streak: number): { title: string; body: string } {
  if (streak <= 1) {
    return {
      title: "Last call for today's mile",
      body: "Two hours to midnight. One mile makes it a 2-day streak.",
    };
  }
  return {
    title: `Last call: ${streak}-day streak on the line`,
    body: "Two hours to midnight and today's mile isn't in. One mile keeps it.",
  };
}

/**
 * Sends the last call to everyone due this hour. Returns how many went out.
 *
 * Two guards beyond the query, both deliberate:
 *  - the stored streak is REFRESHED first. `users.current_streak` is
 *    reconciled every six hours, so someone who broke their streak
 *    yesterday can still read 12 at 10 PM; telling them a dead streak is
 *    "on the line" is worse than saying nothing.
 *  - quiet hours are honoured by SKIPPING, never queueing. The type is
 *    HIGH_PRIORITY so sendPush never parks it for the 9 AM flush — a
 *    "two hours to midnight" delivered next morning is a lie — which means
 *    the quiet-hours check has to happen here.
 */
export async function sendPendingLastCalls(
  at: Date = new Date(),
): Promise<number> {
  const candidates = await lastCallCandidates(at);
  if (candidates.length === 0) return 0;

  let sent = 0;
  for (const c of candidates) {
    try {
      const streak = await refreshCurrentStreak(c.user_id);
      if (streak <= 0) continue;
      if (await isUserInQuietHours(c.user_id)) continue;
      await sendPush(c.user_id, {
        ...lastCallCopy(streak),
        type: "streak_last_call",
        // Strings only: shipped inboxes decode `data` as [String: String].
        data: {
          kind: "last_call",
          streak: String(streak),
          local_date: c.local_date,
        },
      });
      sent++;
    } catch (err: any) {
      console.error(
        `[LastCall] Failed for user ${c.user_id}: ${err?.message ?? err}`,
      );
    }
  }
  if (sent > 0) console.log(`[LastCall] Sent ${sent} last call(s).`);
  return sent;
}
