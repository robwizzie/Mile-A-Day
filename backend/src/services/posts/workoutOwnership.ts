// Post-link guards: does a workout belong to the poster, and how far did it (or
// its day) go.

import { PostgresService } from "../DbService.js";

const db = PostgresService.getInstance();

/** Whether the workout exists and belongs to the user (post-link guard). */
export async function userOwnsWorkout(
  userId: string,
  workoutId: string,
): Promise<boolean> {
  const rows = await db.query(
    `SELECT 1 FROM workouts WHERE workout_id = $1 AND user_id = $2`,
    [workoutId, userId],
  );
  return rows.length > 0;
}

/** Distance for a workout that exists and belongs to the user (post-link guard). */
export async function getOwnedWorkoutDistance(
  userId: string,
  workoutId: string,
): Promise<number | null> {
  const rows = await db.query<{ distance: number | string | null }>(
    `SELECT distance FROM workouts WHERE workout_id = $1 AND user_id = $2`,
    [workoutId, userId],
  );
  const distance = Number(rows[0]?.distance);
  return Number.isFinite(distance) ? distance : null;
}

/**
 * The DAY's rollup distance for a post's linked workout — i.e. the number every
 * read surface already restates a `daily_mile` anchor with (see POST_COLUMNS).
 * Null when the workout isn't the day's anchor, so callers fall back to the
 * workout's own distance.
 *
 * Exists so the auto-post stats guard accepts a card that bakes the day's total
 * (what the feed will display) as well as one that bakes the single leg. Same
 * membership rule as the feed lateral: everything rolled into the anchor, plus
 * sub-floor junk logged up to it.
 */
export async function getOwnedWorkoutRollupDistance(
  userId: string,
  workoutId: string,
): Promise<number | null> {
  const rows = await db.query<{ distance: number | string | null }>(
    `SELECT SUM(m.distance)::double precision AS distance
		 FROM workouts w
		 JOIN workouts m ON m.user_id = w.user_id AND m.local_date = w.local_date
			 AND m.deleted_at IS NULL AND m.exclusion_reason IS NULL
			 AND (
				 m.feed_role IN ('rolled_up', 'daily_mile')
				 OR (m.feed_role = 'hidden' AND m.device_end_date <= w.device_end_date)
			 )
		 WHERE w.workout_id = $1 AND w.user_id = $2 AND w.feed_role = 'daily_mile'`,
    [workoutId, userId],
  );
  const distance = Number(rows[0]?.distance);
  return Number.isFinite(distance) ? distance : null;
}
