import cron from "node-cron";
import { PostgresService } from "../services/DbService.js";
import { sendPush } from "../services/pushNotificationService.js";

const db = PostgresService.getInstance();

interface RecapCandidate {
  user_id: string;
  week_start: string; // Monday of the recapped week (user-local)
  total_miles: string;
  workout_count: string;
  active_days: string;
  best_pace_min_per_mile: string | null;
}

/** 8.7 minutes/mile → "8:42". */
function formatPace(minPerMile: number): string {
  const totalSeconds = Math.round(minPerMile * 60);
  const m = Math.floor(totalSeconds / 60);
  const s = totalSeconds % 60;
  return `${m}:${String(s).padStart(2, "0")}`;
}

/**
 * Sunday-evening "Your week" recap. Runs hourly and fires for users whose
 * LOCAL time is Sunday 5 PM (same per-user timezone predicate as the daily
 * reminder), summarizing the Monday–Sunday week that is ending. Users with
 * zero workouts that week are skipped — a "you did nothing" push is just
 * mean. weekly_recap_log makes the send exactly-once per user per week even
 * though the cron fires 24× a day across timezones.
 */
export async function sendWeeklyRecaps(): Promise<void> {
  const candidates = await db.query<RecapCandidate>(
    `
		WITH user_tz AS (
			SELECT
				u.user_id,
				COALESCE(
					ns.timezone_offset_minutes,
					(SELECT timezone_offset FROM workouts WHERE user_id = u.user_id ORDER BY device_end_date DESC LIMIT 1)
				) AS tz_offset,
				COALESCE(ns.weekly_recap_enabled, TRUE) AS weekly_recap_enabled
			FROM users u
			LEFT JOIN notification_settings ns ON ns.user_id = u.user_id
		),
		due AS (
			SELECT
				t.user_id,
				(NOW() + (t.tz_offset || ' minutes')::interval)::date AS local_today,
				date_trunc('week', (NOW() + (t.tz_offset || ' minutes')::interval))::date AS week_start
			FROM user_tz t
			WHERE t.weekly_recap_enabled = TRUE
				AND t.tz_offset IS NOT NULL
				AND EXTRACT(DOW FROM (NOW() + (t.tz_offset || ' minutes')::interval)) = 0
				AND EXTRACT(HOUR FROM (NOW() + (t.tz_offset || ' minutes')::interval)) = 17
				AND EXISTS (SELECT 1 FROM device_tokens dt WHERE dt.user_id = t.user_id)
				AND NOT EXISTS (
					SELECT 1 FROM weekly_recap_log l
					WHERE l.user_id = t.user_id
						AND l.week_start = date_trunc('week', (NOW() + (t.tz_offset || ' minutes')::interval))::date
				)
		)
		SELECT
			d.user_id,
			d.week_start::text AS week_start,
			COALESCE(SUM(w.distance), 0)::text AS total_miles,
			COUNT(w.workout_id)::text AS workout_count,
			COUNT(DISTINCT w.local_date)::text AS active_days,
			MIN(CASE
				WHEN w.distance >= 0.95 AND w.total_duration > 0
				THEN (w.total_duration / 60.0) / w.distance
			END)::text AS best_pace_min_per_mile
		FROM due d
		JOIN workouts w
			ON w.user_id = d.user_id
			AND w.local_date >= d.week_start
			AND w.local_date <= d.local_today
			AND w.deleted_at IS NULL
			AND w.exclusion_reason IS NULL
		GROUP BY d.user_id, d.week_start
		HAVING COUNT(w.workout_id) > 0
		`,
  );

  if (candidates.length === 0) return;
  console.log(`[WeeklyRecap] ${candidates.length} user(s) due for a recap.`);

  for (const c of candidates) {
    // Claim the (user, week) slot first — the winner of the insert sends. A
    // crashed send costs one push, never a double-send.
    const claimed = await db.query<{ user_id: string }>(
      `INSERT INTO weekly_recap_log (user_id, week_start)
			 VALUES ($1, $2::date)
			 ON CONFLICT DO NOTHING
			 RETURNING user_id`,
      [c.user_id, c.week_start],
    );
    if (claimed.length === 0) continue;

    const miles = parseFloat(c.total_miles) || 0;
    const count = parseInt(c.workout_count, 10) || 0;
    const pace = c.best_pace_min_per_mile
      ? parseFloat(c.best_pace_min_per_mile)
      : null;

    const parts = [
      `${miles.toFixed(1)} mi`,
      `${count} workout${count === 1 ? "" : "s"}`,
    ];
    if (pace) parts.push(`best pace ${formatPace(pace)}`);

    try {
      await sendPush(c.user_id, {
        title: "Your week in review",
        body: `${parts.join(" · ")} — tap to see your recap and share it.`,
        type: "weekly_recap",
      });
    } catch (err: any) {
      console.error(
        `[WeeklyRecap] Push failed for user ${c.user_id}: ${err?.message ?? err}`,
      );
    }
  }
}

export function startWeeklyRecapCron(): void {
  // Hourly at :50 — the SQL predicate (local Sunday 5 PM + log table) decides
  // who actually gets one, so most runs are no-ops.
  cron.schedule("50 * * * *", async () => {
    try {
      await sendWeeklyRecaps();
    } catch (error: any) {
      console.error("[CRON] Error sending weekly recaps:", error.message);
    }
  });

  console.log("Weekly recap cron scheduled (hourly, fires local Sun 5 PM).");
}
