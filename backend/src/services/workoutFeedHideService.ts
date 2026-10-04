import { PostgresService } from "./DbService.js";

const db = PostgresService.getInstance();

/** HealthKit uuids are 36 chars; the column allows 255 like workouts.workout_id. */
const MAX_WORKOUT_ID = 255;

export function isValidWorkoutId(id: unknown): id is string {
  return typeof id === "string" && id.length > 0 && id.length <= MAX_WORKOUT_ID;
}

/**
 * "Off the feed" for ONE walk — the photo prompt's audience choice.
 *
 * Writes or clears a `workout_feed_hides` row. Deliberately does NOT require
 * the workout to exist yet: the prompt opens the moment a walk ends, usually
 * before the phone has synced it, and the camera hold (10 min) is the only
 * thing keeping the raw card off friends' feeds until then. A row keyed by
 * (caller, uuid) can only ever describe the caller's own workout, synced or
 * not, so nothing about it needs a lookup.
 *
 * Idempotent both ways. Returns the state now stored.
 */
export async function setWorkoutFeedHidden(
  userId: string,
  workoutId: string,
  hidden: boolean,
): Promise<boolean> {
  if (hidden) {
    await db.query(
      `INSERT INTO workout_feed_hides (user_id, workout_id)
			 VALUES ($1, $2)
			 ON CONFLICT (user_id, workout_id) DO NOTHING`,
      [userId, workoutId],
    );
  } else {
    await db.query(
      `DELETE FROM workout_feed_hides WHERE user_id = $1 AND workout_id = $2`,
      [userId, workoutId],
    );
  }
  return hidden;
}
