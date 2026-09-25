import { PostgresService } from "./DbService.js";
import { MIN_PLAUSIBLE_MILE_SECONDS, countedWorkoutSql } from "./mileTime.js";
import { earnedDetailsFor } from "./badgeEarnedDetail.js";
import { getUserBadges } from "./badgeService.js";

const db = PostgresService.getInstance();

/**
 * A medal whose stored `earned_at` is more than this many days after the day
 * its history says it was reached is re-dated. The slack keeps every LIVE
 * award (the walk synced today, or a Watch walk landing the next morning)
 * exactly as it was stamped.
 */
export const REDATE_SLACK_DAYS = 2;

/**
 * Put medals on the day they were actually EARNED.
 *
 * Every insert into `user_badges` used to leave `earned_at` at its default
 * now(), which is the truth for a medal crossed by today's walk and a lie for
 * anything awarded retroactively — Recalibrate, the one-time retro sweep
 * (`badge_retro_v1`), a first-run history import, a late-synced walk. Those
 * read "earned today" on the Medals screen, and the app celebrates a newly
 * arrived medal dated today, so a sweep that found a 400-day history's worth
 * of streak and mileage medals popped them one by one.
 *
 * The day is the one `earned_detail` already derives per family (the first
 * day the streak reached N, the day the cumulative miles crossed N, the first
 * day of N miles, the holiday, the Nth challenge, the ghost margin) — ONE
 * answer, shared with what the Medals screen prints under the medal — except
 * pace, where earned_detail names the FASTEST qualifying mile and the medal
 * was earned by the FIRST. Families with no dated history (hypes, nudges,
 * stories, competitions, buddy counts) derive nothing and are left alone.
 *
 * The instant is the last counted workout that local day, else local noon.
 * Only ever moves a date EARLIER, and only past the slack; the replaced value
 * is kept once in `progress_snapshot.stamped_at`, so it is reversible from
 * the table. Returns how many rows it re-dated.
 */
export async function redateBadges(
  userId: string,
  onlyBadgeIds?: string[],
): Promise<number> {
  const all = await getUserBadges(userId);
  const only = onlyBadgeIds ? new Set(onlyBadgeIds) : null;
  const badges = only ? all.filter((b) => only.has(b.badgeId)) : all;
  if (badges.length === 0) return 0;

  const details = await earnedDetailsFor(userId, badges, "self");
  const days = new Map<string, string>();
  for (const b of badges) {
    const day = details.get(b.badgeId)?.date;
    if (day && /^\d{4}-\d{2}-\d{2}$/.test(day)) days.set(b.badgeId, day);
  }

  // Pace: the first day a qualifying split existed at each medal's limit.
  const pace = badges.filter(
    (b) =>
      b.category === "pace" &&
      b.requirement !== null &&
      Number.isFinite(Number(b.requirement)),
  );
  if (pace.length) {
    const rows = await db.query<{ badge_id: string; day: string | null }>(
      `SELECT t.badge_id, to_char(x.d, 'YYYY-MM-DD') AS day
			 FROM unnest($2::text[], $3::float8[]) AS t(badge_id, lim)
			 LEFT JOIN LATERAL (
			   SELECT MIN(w.local_date) AS d
			     FROM workout_splits s JOIN workouts w ON w.workout_id = s.workout_id
			    WHERE w.user_id = $1 AND s.split_pace >= ${MIN_PLAUSIBLE_MILE_SECONDS}
			      AND s.split_distance >= 0.95 AND ${countedWorkoutSql("w")}
			      AND s.split_pace <= t.lim
			 ) x ON true`,
      [
        userId,
        pace.map((b) => b.badgeId),
        pace.map((b) => Number(b.requirement) * 60),
      ],
    );
    for (const r of rows) {
      if (r.day) days.set(r.badge_id, r.day);
      else days.delete(r.badge_id);
    }
  }
  if (days.size === 0) return 0;

  const ids = [...days.keys()];
  const res = await db.query<{ badge_id: string }>(
    `WITH off AS (
		   SELECT COALESCE(
		     (SELECT ns.timezone_offset_minutes FROM notification_settings ns WHERE ns.user_id = $1),
		     (SELECT w.timezone_offset FROM workouts w WHERE w.user_id = $1 ORDER BY w.device_end_date DESC LIMIT 1),
		     0) AS m
		 ), src AS (
		   SELECT t.badge_id,
		          COALESCE(
		            (SELECT MAX(w.device_end_date) FROM workouts w
		              WHERE w.user_id = $1 AND w.local_date = t.day AND ${countedWorkoutSql("w")}),
		            ((t.day + time '12:00') - (off.m || ' minutes')::interval) AT TIME ZONE 'UTC'
		          ) AS at
		     FROM unnest($2::text[], $3::date[]) AS t(badge_id, day), off
		 )
		 UPDATE user_badges ub
		    SET earned_at = src.at,
		        progress_snapshot = CASE
		          WHEN ub.progress_snapshot ? 'stamped_at' THEN ub.progress_snapshot
		          ELSE COALESCE(ub.progress_snapshot, '{}'::jsonb) || jsonb_build_object(
		                 'stamped_at',
		                 to_char(ub.earned_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))
		        END
		   FROM src
		  WHERE ub.user_id = $1 AND ub.badge_id = src.badge_id
		    AND src.at < ub.earned_at - interval '${REDATE_SLACK_DAYS} days'
		 RETURNING ub.badge_id`,
    [userId, ids, ids.map((id) => days.get(id)!)],
  );
  return res.length;
}
