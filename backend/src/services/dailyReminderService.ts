import { PostgresService } from "./DbService.js";
import { sendPush } from "./pushNotificationService.js";
import { challengeForNotification } from "./dailyChallengeService.js";

const db = PostgresService.getInstance();

interface ReminderCandidate {
  user_id: string;
  goal_miles: string | number;
  tz_offset: number;
  local_date: string;
}

/** The duel this user is in today, when the rotation served them one. */
interface ReminderMatchup {
  user_id: string;
  rival_username: string | null;
  my_miles: number;
  rival_miles: number;
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
interface ReminderCopy {
  title: string;
  body: string;
}

const GENERIC_COPY: ReminderCopy = {
  title: "Mile still waiting…",
  body: "Don't forget to log your daily mile! Lace up and get moving.",
};

/**
 * Today's challenge, said out loud.
 *
 * The challenge system has only ever pushed `challenge_won` (to the winner,
 * the next morning) and the Head-to-Head `lead_change` — so unless you opened
 * the app you never learned there WAS a challenge today, never mind which.
 * The reminder already fires once, at the user's hour, only when the mile
 * isn't done; naming the challenge there turns "go for a walk" into "here is
 * the specific thing on offer", which is the whole point of having one.
 *
 * The challenge's own description is the body verbatim: it is already written
 * for the user (the dashboard card shows exactly this string), and rewriting
 * it here would be a second copy to drift.
 */
function challengeCopy(challenge: {
  title: string;
  description: string;
}): ReminderCopy {
  return {
    title: `Today's challenge: ${challenge.title}`,
    body: `${challenge.description} Your mile isn't done yet.`,
  };
}

/**
 * Head-to-Head has exactly two pushes — `lead_change` when somebody overtakes
 * you, and `challenge_won` the next morning — and both are conditional enough
 * that a duel can run start to finish in silence: a tie is never announced, a
 * lead is only announced as a RETAKE, and being passed only counts once the
 * rival has actually logged something. So on the ordinary day where you are
 * simply up against someone, nothing ever said so.
 *
 * The reminder is the honest place to say it. It already fires once, at the
 * user's own hour, only when the mile ISN'T done — which is exactly when
 * "@someone is at 2.10 today" is a reason to move rather than trivia.
 *
 * Deliberately reads the EXISTING pin instead of assigning one. `h2h_matchups`
 * rows are written by the user's own dashboard read and by the sync-time
 * evaluation (dailyChallengeService), and a reminder that started assigning
 * would become a third writer — creating duels for accounts that never opened
 * the app, whose rivals would then be told they had won against nobody. No
 * pin, no duel line; the generic copy stands.
 */
async function matchupsFor(
  candidates: ReminderCandidate[],
): Promise<Map<string, ReminderMatchup>> {
  if (candidates.length === 0) return new Map();
  const ids = candidates.map((c) => c.user_id);
  const dates = candidates.map((c) => c.local_date);
  const rows = await db.query<{
    user_id: string;
    rival_username: string | null;
    my_miles: string | null;
    rival_miles: string | null;
  }>(
    `WITH due AS (
			SELECT * FROM UNNEST($1::text[], $2::text[]) AS t(user_id, local_date)
		)
		SELECT due.user_id,
			r.username AS rival_username,
			(SELECT COALESCE(SUM(w.distance), 0) FROM workouts w
			  WHERE w.user_id = due.user_id AND w.local_date = due.local_date::date
				AND w.deleted_at IS NULL AND w.exclusion_reason IS NULL) AS my_miles,
			(SELECT COALESCE(SUM(w.distance), 0) FROM workouts w
			  WHERE w.user_id = m.rival_id AND w.local_date = due.local_date::date
				AND w.deleted_at IS NULL AND w.exclusion_reason IS NULL) AS rival_miles
		FROM due
		JOIN h2h_matchups m
		  ON m.user_id = due.user_id AND m.local_date = due.local_date::date
		 AND m.resolved_at IS NULL
		JOIN users r ON r.user_id = m.rival_id
		-- Only when the rotation actually SERVED them the duel: the pin can
		-- survive an eligibility flip that moved them onto another challenge,
		-- and naming a rival they aren't playing reads as a bug.
		WHERE EXISTS (
			SELECT 1 FROM user_daily_challenges udc
			 WHERE udc.user_id = due.user_id
			   AND udc.local_date = due.local_date::date
			   AND udc.challenge_key = 'head_to_head'
		)`,
    [ids, dates],
  );
  return new Map(
    rows.map((r) => [
      r.user_id,
      {
        user_id: r.user_id,
        rival_username: r.rival_username,
        my_miles: Number(r.my_miles ?? 0),
        rival_miles: Number(r.rival_miles ?? 0),
      },
    ]),
  );
}

/** Says where the duel stands, because that is what decides whether to go. */
function duelCopy(duel: ReminderMatchup): { title: string; body: string } {
  const name = duel.rival_username ? `@${duel.rival_username}` : "Your rival";
  const mine = duel.my_miles.toFixed(2);
  const theirs = duel.rival_miles.toFixed(2);
  if (duel.rival_miles <= 0) {
    return {
      title: `You're up against ${name} today 🥊`,
      body: "Neither of you has logged a mile yet. Go first.",
    };
  }
  if (duel.my_miles >= duel.rival_miles) {
    return {
      title: `You're ahead of ${name} 🔥`,
      body: `${mine} mi to their ${theirs} — but your mile isn't done. Finish it to keep the lead.`,
    };
  }
  return {
    title: `${name} is ahead of you 👀`,
    body: `${theirs} mi to your ${mine}. Still time to answer before midnight.`,
  };
}

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
		SELECT t.user_id, t.goal_miles, t.tz_offset,
			(NOW() + (t.tz_offset || ' minutes')::interval)::date::text AS local_date
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

  const matchups = await matchupsFor(candidates);

  await Promise.all(
    candidates.map(async ({ user_id, local_date }) => {
      try {
        // A duel names the rival and the standing, which beats naming the
        // challenge — it IS the challenge, said in the form that decides
        // whether to go out. Everything else names today's challenge.
        const duel = matchups.get(user_id);
        let copy: ReminderCopy;
        if (duel) {
          copy = duelCopy(duel);
        } else {
          const challenge = await challengeForNotification(user_id, local_date);
          copy = challenge ? challengeCopy(challenge) : GENERIC_COPY;
        }
        await sendPush(user_id, { ...copy, type: "daily_reminder" });
      } catch (err: any) {
        console.error(
          `[DailyReminder] Failed for user ${user_id}: ${err?.message ?? err}`,
        );
      }
    }),
  );
}
