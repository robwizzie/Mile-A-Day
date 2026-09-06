import { PostgresService } from "./DbService.js";
import { sendPush } from "./pushNotificationService.js";
import { challengeForNotification } from "./dailyChallengeService.js";

const db = PostgresService.getInstance();

export interface ReminderCandidate {
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
 * How long someone has been away, and what their friends did meanwhile —
 * the two facts a win-back is made of.
 */
export interface LapseContext {
  user_id: string;
  /** Local days since the last counted workout (or since joining, if none). */
  days_quiet: number;
  /** False for an account that has never logged a counted workout. */
  has_walked: boolean;
  /** Friends' counted miles over the last 7 local days. */
  friend_miles_7d: number;
  /** How many friends logged anything in those 7 days. */
  active_friends: number;
  /** The friend with the most miles in the window — first name, else handle. */
  top_friend: string | null;
}

/**
 * The days a lapse is worth mentioning. Deliberately three fixed marks
 * rather than "every N days": the reminder already fires daily, so this is
 * not a second push — on these days the daily reminder SAYS SOMETHING ELSE.
 * Its only other "you stopped" push is `streak_lost` (once, ten-day streaks
 * and up), after which a quiet user hears the same "Mile still waiting…"
 * every evening and nothing acknowledges the gap.
 */
export const WIN_BACK_DAYS = [7, 14, 30] as const;

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

/**
 * Lapse context for every candidate whose quiet stretch lands on a
 * win-back day. Anchored on the last COUNTED workout's local date (a
 * duplicate or a drive never counted as a mile, so it can't count as a
 * return either); an account with no workout at all is anchored on the day
 * it was created, so "joined a week ago, never walked" is day 7 too.
 *
 * Friends are the caller's accepted rows (`friendships` is stored per
 * direction), scored over the seven local days ending today so the number
 * in the push is the one the Friends tab shows for the same week.
 */
export async function lapseContextFor(
  candidates: ReminderCandidate[],
): Promise<Map<string, LapseContext>> {
  if (candidates.length === 0) return new Map();
  const ids = candidates.map((c) => c.user_id);
  const dates = candidates.map((c) => c.local_date);
  const rows = await db.query<{
    user_id: string;
    days_quiet: number;
    has_walked: boolean;
    friend_miles_7d: string | null;
    active_friends: number;
    top_friend: string | null;
  }>(
    `WITH due AS (
			SELECT * FROM UNNEST($1::text[], $2::text[]) AS t(user_id, local_date)
		),
		anchor AS (
			SELECT due.user_id, due.local_date::date AS local_date,
				(SELECT MAX(w.local_date) FROM workouts w
				  WHERE w.user_id = due.user_id
				    AND w.deleted_at IS NULL AND w.exclusion_reason IS NULL) AS last_walk,
				(u.created_at AT TIME ZONE 'UTC')::date AS joined
			FROM due JOIN users u ON u.user_id = due.user_id
		),
		lapsed AS (
			SELECT a.user_id, a.local_date,
				(a.local_date - COALESCE(a.last_walk, a.joined))::int AS days_quiet,
				(a.last_walk IS NOT NULL) AS has_walked
			FROM anchor a
			WHERE (a.local_date - COALESCE(a.last_walk, a.joined)) = ANY($3::int[])
		),
		friend_week AS (
			SELECT l.user_id, f.friend_id,
				COALESCE(fu.first_name, fu.username) AS name,
				COALESCE((SELECT SUM(w.distance) FROM workouts w
				  WHERE w.user_id = f.friend_id
				    AND w.local_date > l.local_date - 7 AND w.local_date <= l.local_date
				    AND w.deleted_at IS NULL AND w.exclusion_reason IS NULL), 0) AS miles
			FROM lapsed l
			JOIN friendships f ON f.user_id = l.user_id AND f.status = 'accepted'
			JOIN users fu ON fu.user_id = f.friend_id
		)
		SELECT l.user_id, l.days_quiet, l.has_walked,
			(SELECT SUM(miles) FROM friend_week fw WHERE fw.user_id = l.user_id) AS friend_miles_7d,
			(SELECT COUNT(*) FROM friend_week fw WHERE fw.user_id = l.user_id AND fw.miles > 0)::int AS active_friends,
			(SELECT name FROM friend_week fw WHERE fw.user_id = l.user_id AND fw.miles > 0
			  ORDER BY fw.miles DESC, fw.friend_id ASC LIMIT 1) AS top_friend
		FROM lapsed l`,
    [ids, dates, [...WIN_BACK_DAYS]],
  );
  return new Map(
    rows.map((r) => [
      r.user_id,
      {
        user_id: r.user_id,
        days_quiet: Number(r.days_quiet),
        has_walked: Boolean(r.has_walked),
        friend_miles_7d: Number(r.friend_miles_7d ?? 0),
        active_friends: Number(r.active_friends ?? 0),
        top_friend: r.top_friend,
      },
    ]),
  );
}

/**
 * The win-back line. Kind, specific, and about the people rather than the
 * number: "your friends walked 23 mi this week" is a reason to go out,
 * "you've missed 14 days" is a reason to delete the app. Names the most
 * active friend when there is one, because a person beats a statistic.
 */
export function winBackCopy(lapse: LapseContext): ReminderCopy {
  const miles = lapse.friend_miles_7d;
  const milesText =
    miles >= 10 ? Math.round(miles).toString() : miles.toFixed(1);
  let friendsLine: string | null = null;
  if (lapse.active_friends > 0 && lapse.top_friend && miles > 0) {
    const others = lapse.active_friends - 1;
    const who =
      others <= 0
        ? lapse.top_friend
        : `${lapse.top_friend} and ${others} ${others === 1 ? "friend" : "friends"}`;
    friendsLine = `${who} walked ${milesText} mi this week.`;
  }

  if (!lapse.has_walked) {
    return {
      title:
        lapse.days_quiet >= 30
          ? "A month in, no first mile yet"
          : lapse.days_quiet >= 14
            ? "Two weeks in, no first mile yet"
            : "A week in, no first mile yet",
      body: friendsLine
        ? `${friendsLine} Your first one is a walk around the block.`
        : "Your first one is a walk around the block. Today's a good day for it.",
    };
  }

  if (lapse.days_quiet >= 30) {
    return {
      title: "A month since your last mile",
      body: friendsLine
        ? `${friendsLine} Fresh start: one mile today, no pressure.`
        : "Fresh start: one mile today, no pressure.",
    };
  }
  if (lapse.days_quiet >= 14) {
    return {
      title: "Two weeks without a mile",
      body: friendsLine
        ? `${friendsLine} A streak starts over with one.`
        : "A streak starts over with one. Lace up and take it slow.",
    };
  }
  return {
    title: "A week without a mile",
    body: friendsLine
      ? `${friendsLine} One mile brings your flame back.`
      : "One mile brings your flame back. Tonight counts.",
  };
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

  const [matchups, lapses] = await Promise.all([
    matchupsFor(candidates),
    lapseContextFor(candidates),
  ]);

  await Promise.all(
    candidates.map(async ({ user_id, local_date }) => {
      try {
        // On a win-back day the gap is the story: a week away, told about
        // today's challenge, reads as an app that didn't notice. Otherwise a
        // duel names the rival and the standing, which beats naming the
        // challenge — it IS the challenge, said in the form that decides
        // whether to go out. Everything else names today's challenge.
        const lapse = lapses.get(user_id);
        const duel = matchups.get(user_id);
        let copy: ReminderCopy;
        let data: Record<string, string> | undefined;
        if (lapse) {
          copy = winBackCopy(lapse);
          data = { kind: "win_back", days_quiet: String(lapse.days_quiet) };
        } else if (duel) {
          copy = duelCopy(duel);
        } else {
          const challenge = await challengeForNotification(user_id, local_date);
          copy = challenge ? challengeCopy(challenge) : GENERIC_COPY;
        }
        // Same type as every other reminder: shipped builds route it to the
        // dashboard, it honours the reminder switch and quiet hours, and it
        // is the one push that day — never a second one beside the reminder.
        await sendPush(user_id, {
          ...copy,
          type: "daily_reminder",
          ...(data ? { data } : {}),
        });
      } catch (err: any) {
        console.error(
          `[DailyReminder] Failed for user ${user_id}: ${err?.message ?? err}`,
        );
      }
    }),
  );
}
