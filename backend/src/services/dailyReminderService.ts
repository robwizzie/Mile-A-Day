import { PostgresService } from "./DbService.js";
import { sendPush } from "./pushNotificationService.js";

const db = PostgresService.getInstance();

interface ReminderCandidate {
  user_id: string;
  goal_miles: string | number;
  tz_offset: number;
}

/**
 * Sends "Mile still waiting…" pushes to every user whose current local hour
 * matches their `daily_reminder_hour` and who hasn't completed today's mile.
 *
 * Intended to be called once per hour by a cron job. The local-hour predicate
 * inside the query ensures each user gets at most one fire per day even though
 * the cron runs 24× daily.
 *
 * Background:
 *   The original implementation scheduled a local notification on the iPhone
 *   whose "still waiting" vs. "completed" text was frozen at schedule time.
 *   When the user finished their mile via the Apple Watch (or the app didn't
 *   get a background refresh window before 6 PM), the stale "still waiting"
 *   notification would fire even though the mile was done. Driving the reminder
 *   from the server eliminates that race — completion state is read at fire
 *   time from the authoritative workouts table.
 */
export async function sendPendingDailyReminders(): Promise<void> {
  const candidates = await db.query<ReminderCandidate>(
    `
		WITH user_tz AS (
			SELECT
				u.user_id,
				u.goal_miles,
				COALESCE(
					ns.timezone_offset_minutes,
					(SELECT timezone_offset FROM workouts WHERE user_id = u.user_id ORDER BY device_end_date DESC LIMIT 1)
				) AS tz_offset,
				COALESCE(ns.daily_reminder_enabled, TRUE) AS daily_reminder_enabled,
				COALESCE(ns.daily_reminder_hour, 18) AS daily_reminder_hour
			FROM users u
			LEFT JOIN notification_settings ns ON ns.user_id = u.user_id
		)
		SELECT t.user_id, t.goal_miles, t.tz_offset
		FROM user_tz t
		WHERE t.daily_reminder_enabled = TRUE
		  AND t.tz_offset IS NOT NULL
		  AND EXTRACT(HOUR FROM (NOW() + (t.tz_offset || ' minutes')::interval)) = t.daily_reminder_hour
		  AND EXISTS (SELECT 1 FROM device_tokens dt WHERE dt.user_id = t.user_id)
		  AND COALESCE(
				(SELECT SUM(w.distance) FROM workouts w
				 WHERE w.user_id = t.user_id
				   AND w.local_date = (NOW() + (t.tz_offset || ' minutes')::interval)::date
				   AND w.deleted_at IS NULL AND w.exclusion_reason IS NULL),
				0
			  ) < t.goal_miles
		`,
  );

  if (candidates.length === 0) {
    console.log("[DailyReminder] No users due for a reminder this hour.");
    return;
  }

  console.log(
    `[DailyReminder] Sending reminders to ${candidates.length} user(s).`,
  );

  await Promise.all(
    candidates.map(async ({ user_id }) => {
      try {
        await sendPush(user_id, {
          title: "Mile still waiting…",
          body: "Don't forget to log your daily mile! Lace up and get moving.",
          type: "daily_reminder",
        });
      } catch (err: any) {
        console.error(
          `[DailyReminder] Failed for user ${user_id}: ${err?.message ?? err}`,
        );
      }
    }),
  );
}
