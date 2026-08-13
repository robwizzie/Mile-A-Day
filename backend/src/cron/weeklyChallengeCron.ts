import cron from "node-cron";
import { PostgresService } from "../services/DbService.js";
import { sendPush } from "../services/pushNotificationService.js";
import { shouldSendNotification } from "../services/notificationSettingsService.js";
import {
  CLIENT_FEATURES,
  supportsClientFeatureSql,
} from "../services/clientFeatures.js";
import {
  measure,
  serveWeek,
  sundayWeekStartSql,
  weekWindowForUser,
} from "../services/weeklyChallengeService.js";

const db = PostgresService.getInstance();

interface DueUser {
  user_id: string;
  week_start: string;
}

/** The user's own wall clock, as a SQL expression. */
const LOCAL_TS = "NOW() + (t.tz_offset || ' minutes')::interval";

/**
 * Per-user-local-time predicate, the same shape `weeklyRecapCron` uses: resolve
 * each user's offset from their stored preference (falling back to their most
 * recent workout's), then fire only for those whose LOCAL clock is at the
 * requested weekday and hour. The cron itself runs hourly, so every timezone
 * gets its turn exactly once.
 *
 * The `weekly_challenge_push_log` claim is what makes that exactly-once rather
 * than once-per-timezone-pass.
 */
function dueUsersSql(dow: number, hour: number, kind: string): string {
  return `
		WITH user_tz AS (
			SELECT
				u.user_id,
				COALESCE(
					ns.timezone_offset_minutes,
					(SELECT timezone_offset FROM workouts WHERE user_id = u.user_id ORDER BY device_end_date DESC LIMIT 1)
				) AS tz_offset,
				COALESCE(ns.weekly_challenge_enabled, TRUE) AS enabled
			FROM users u
			LEFT JOIN notification_settings ns ON ns.user_id = u.user_id
		)
		SELECT
			t.user_id,
			${sundayWeekStartSql(LOCAL_TS)}::text AS week_start
		FROM user_tz t
		WHERE t.enabled = TRUE
			AND t.tz_offset IS NOT NULL
			AND EXTRACT(DOW FROM (NOW() + (t.tz_offset || ' minutes')::interval)) = ${dow}
			AND EXTRACT(HOUR FROM (NOW() + (t.tz_offset || ' minutes')::interval)) = ${hour}
			-- A brand-new type string: only devices that declared they can
			-- render the weekly challenge have anywhere for this to open.
			AND ${supportsClientFeatureSql("t.user_id", CLIENT_FEATURES.weeklyChallengeV1)}
			AND NOT EXISTS (
				SELECT 1 FROM weekly_challenge_push_log l
				WHERE l.user_id = t.user_id
					-- Must be the SAME expression as the week_start selected
					-- above, or the exactly-once claim stops matching its own
					-- rows and every user gets re-announced hourly.
					AND l.week_start = ${sundayWeekStartSql(LOCAL_TS)}
					AND l.kind = '${kind}'
			)
		LIMIT 5000`;
}

/**
 * Claim the send before making it. Returns false when another pass got there
 * first, so a push can never go out twice even if two ticks overlap.
 */
async function claim(
  userId: string,
  weekStart: string,
  kind: string,
): Promise<boolean> {
  const rows = await db.query<{ user_id: string }>(
    `INSERT INTO weekly_challenge_push_log (user_id, week_start, kind)
		VALUES ($1, $2::date, $3)
		ON CONFLICT (user_id, week_start, kind) DO NOTHING
		RETURNING user_id`,
    [userId, weekStart, kind],
  );
  return rows.length > 0;
}

/**
 * Sunday morning: announce the week, and — importantly — SERVE it.
 *
 * Serving here rather than waiting for the user's first read is what fills the
 * friends leaderboard: a friend with no stamped row has no frozen target and
 * can't be ranked, so without this the board would populate one person at a
 * time as people happened to open the app.
 */
export async function sendWeeklyChallengeAnnouncements(): Promise<void> {
  const due = await db.query<DueUser>(dueUsersSql(0, 9, "new"));

  for (const user of due) {
    try {
      if (!(await claim(user.user_id, user.week_start, "new"))) continue;
      if (
        !(await shouldSendNotification(user.user_id, null, "weekly_challenge"))
      )
        continue;

      const served = await serveWeek(user.user_id, user.week_start);
      if (!served) continue;

      const target =
        served.challenge.target_step >= 1
          ? Math.round(served.target).toLocaleString("en-US")
          : served.target.toFixed(1);

      await sendPush(user.user_id, {
        title: `This week: ${served.challenge.title}`,
        body: served.challenge.description_template
          .replace("{target}", target)
          .replace("{unit}", served.challenge.unit),
        type: "weekly_challenge_new",
        // Every value a STRING: shipped builds decode the notification inbox's
        // data as [String: String], and one number breaks the whole decode.
        data: {
          type: "weekly_challenge_new",
          challenge_key: served.challenge.challenge_key,
          week_start: user.week_start,
          target: String(served.target),
        },
      });
    } catch (error: any) {
      console.error(
        `[WeeklyChallenges] Announce failed for ${user.user_id}:`,
        error?.message ?? error,
      );
    }
  }
}

/**
 * Friday evening: a nudge, but only to people who have started and not
 * finished. Someone at zero gets nothing — a "you did nothing this week" push
 * is just mean, and it's the same reason the weekly recap skips empty weeks.
 *
 * Under Sunday→Saturday weeks Friday leaves two days (Fri + Sat) rather than
 * three, which is why the copy never names a day count.
 */
export async function sendWeeklyChallengeNudges(): Promise<void> {
  const due = await db.query<DueUser>(dueUsersSql(5, 18, "nudge"));

  for (const user of due) {
    try {
      const served = await serveWeek(user.user_id, user.week_start);
      if (!served) continue;

      const window = await weekWindowForUser(user.user_id);
      const value = await measure(
        user.user_id,
        served.challenge.metric,
        window.weekStart,
        window.localToday,
      );

      const percent = served.target > 0 ? value / served.target : 0;
      if (percent <= 0 || percent >= 1) continue;

      if (!(await claim(user.user_id, user.week_start, "nudge"))) continue;
      if (
        !(await shouldSendNotification(user.user_id, null, "weekly_challenge"))
      )
        continue;

      const remaining = Math.max(0, served.target - value);
      const remainingText =
        served.challenge.target_step >= 1
          ? Math.ceil(remaining).toLocaleString("en-US")
          : remaining.toFixed(1);

      await sendPush(user.user_id, {
        title: served.challenge.title,
        body: `You're ${remainingText} ${served.challenge.unit} from finishing this week's challenge.`,
        type: "weekly_challenge_nudge",
        data: {
          type: "weekly_challenge_nudge",
          challenge_key: served.challenge.challenge_key,
          week_start: user.week_start,
          remaining: String(remaining),
        },
      });
    } catch (error: any) {
      console.error(
        `[WeeklyChallenges] Nudge failed for ${user.user_id}:`,
        error?.message ?? error,
      );
    }
  }
}

export function startWeeklyChallengeCron(): void {
  // Hourly, at :20 — off the :00 mark (and clear of the recap cron) so this
  // isn't contending with every other scheduled job on the hour.
  cron.schedule("20 * * * *", async () => {
    try {
      await sendWeeklyChallengeAnnouncements();
      await sendWeeklyChallengeNudges();
    } catch (error: any) {
      console.error(
        "[CRON] Weekly challenge pass failed:",
        error?.message ?? error,
      );
    }
  });

  console.log("Weekly challenge cron scheduled (hourly at :20).");
}
