import { PostgresService } from "./DbService.js";
import { refreshCurrentStreak } from "./leaderboardService.js";
import { revokeUnearnedBadges } from "./badgeService.js";

const db = PostgresService.getInstance();

export interface WorkoutDeletionResult {
  deleted: boolean;
  currentStreak: number;
  revokedBadges: string[];
}

/**
 * Soft-delete a single workout and heal the user's derived data.
 *
 * The workout row is kept (tombstoned via `deleted_at`) rather than removed so a
 * HealthKit re-sync — which would re-upload the same `workout_id` — can't bring
 * it back: the upload's `ON CONFLICT DO UPDATE` never clears `deleted_at`.
 *
 * After tombstoning we:
 *  1. drop any daily-challenge completion this workout triggered (if the workout
 *     was a bad/drive entry, the completion it earned is bogus too),
 *  2. recompute and store the user's current streak from active workouts, and
 *  3. revoke any badges the user no longer qualifies for (e.g. a total-miles or
 *     fake-streak badge that only the deleted workout had pushed them over).
 *
 * Idempotent: deleting an already-deleted or non-existent workout is a no-op
 * (returns deleted=false) and still returns the freshly recomputed streak.
 */
export async function softDeleteWorkout(
  userId: string,
  workoutId: string,
): Promise<WorkoutDeletionResult> {
  const active = await db.query<{ workout_id: string }>(
    `SELECT workout_id FROM workouts
		WHERE workout_id = $1 AND user_id = $2 AND deleted_at IS NULL`,
    [workoutId, userId],
  );

  if (active.length === 0) {
    // Nothing to delete — still return the current (recomputed) streak so the
    // client stays in sync.
    const streak = await refreshCurrentStreak(userId);
    return { deleted: false, currentStreak: streak, revokedBadges: [] };
  }

  await db.query(
    `UPDATE workouts SET deleted_at = NOW() WHERE workout_id = $1 AND user_id = $2`,
    [workoutId, userId],
  );

  // Remove any challenge completion this specific workout earned.
  await db
    .query(
      `DELETE FROM user_challenge_completions
		WHERE user_id = $1 AND completing_workout_id = $2`,
      [userId, workoutId],
    )
    .catch(() => {});

  const currentStreak = await refreshCurrentStreak(userId);
  const revokedBadges = await revokeUnearnedBadges(userId);

  return { deleted: true, currentStreak, revokedBadges };
}
