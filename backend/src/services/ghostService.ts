import { PostgresService } from "./DbService.js";
import { CIRCLE_CTE } from "./postService.js";
import { OWNER_NOT_PRIVATE_SQL } from "./visibilityService.js";
import { sendPush } from "./pushNotificationService.js";
import { shouldSendNotification } from "./notificationSettingsService.js";
import { CLIENT_FEATURES, userSupports } from "./clientFeatures.js";
import { logError } from "./errorLogService.js";

const db = PostgresService.getInstance();

/** Activity types a ghost can be raced for. */
export const GHOST_ACTIVITIES = ["running", "walking"] as const;
export type GhostActivity = (typeof GHOST_ACTIVITIES)[number];

/**
 * A mile between 2:00 and 40:00 — the same window the client's
 * `BestEffortStore.GhostTarget.isPlausible` enforces, and the same one
 * `ghostRaceParams` uses when storing a result. Kept in sync deliberately: a
 * ghost outside this band would be armed, raced, won, and then silently
 * dropped on upload.
 */
const MIN_GHOST_SECONDS = 120;
const MAX_GHOST_SECONDS = 2400;

/** Friend count worth offering in a picker. */
const MAX_GHOSTS = 50;

export interface FriendGhost {
  user_id: string;
  username: string | null;
  first_name: string | null;
  last_name: string | null;
  profile_image_url: string | null;
  /** Their fastest completed mile, in seconds. */
  mile_seconds: number;
}

/**
 * Friends whose fastest mile can be raced as a ghost, fastest first.
 *
 * Deliberately NOT built on `leaderboardService.getPaceLeaderboard`, even
 * though that already returns a friend-scoped `period_best_pace` in the right
 * unit. Four reasons, in order of severity:
 *
 *  1. It has no activity dimension. `split_pace` is stored without one, so a
 *     friend's 6:30 RUN split would be handed back as a WALK ghost. The client
 *     already refuses to do this to a user with their OWN PR
 *     (`BestEffortStore.seededPace` — "an unbeatable ghost dressed up as a
 *     fair one"); doing it with someone else's time is the same bug with a
 *     name attached.
 *  2. It has no block filter — `rankingUserIds` gates on `status = 'accepted'`
 *     alone, so a block that didn't tear down the friendship leaks through.
 *  3. It has no `deleted_at` / `exclusion_reason` guard, so a soft-deleted or
 *     vehicle-speed-flagged workout can supply the number.
 *  4. It ignores `workout_visibility`, so a user who went 'private' is still
 *     offered.
 *
 * The 0.999 distance floor (not the legacy 0.95 used by badges and PR
 * detection) excludes the trailing partial split that SplitCalculator emits
 * with an extrapolated per-mile pace — otherwise a half mile run "at 7:00 pace"
 * becomes a ghost nobody can catch. Same floor the pace leaderboard uses, so
 * the two agree.
 *
 * The viewer is included in their own list: the picker reads as a leaderboard,
 * and seeing your own time next to your friends' is the point.
 */
export async function getFriendGhosts(
  userId: string,
  activity: GhostActivity,
): Promise<FriendGhost[]> {
  // CIRCLE_CTE hardcodes the viewer as $1, so the activity has to be $2.
  return db.query<FriendGhost>(
    `${CIRCLE_CTE},
		bests AS (
			SELECT w.user_id, MIN(ws.split_pace)::float AS mile_seconds
			  FROM workout_splits ws
			  JOIN workouts w ON w.workout_id = ws.workout_id
			 WHERE w.user_id IN (SELECT uid FROM circle)
			   AND w.user_id NOT IN (SELECT uid FROM blocked)
			   AND w.workout_type = $2
			   AND w.deleted_at IS NULL
			   AND w.exclusion_reason IS NULL
			   AND ws.split_pace > 0
			   AND ws.split_distance >= 0.999
			 GROUP BY w.user_id
		)
		-- Narrower than FRIEND_SAFE_USER_COLUMNS on purpose: a picker needs a
		-- name, a face and a time. Never a star select -- that table carries
		-- email and apple_sub, and this list is read by other users.
		SELECT u.user_id, u.username, u.first_name, u.last_name,
		       u.profile_image_url, b.mile_seconds
		  FROM bests b
		  JOIN users u ON u.user_id = b.user_id
		 WHERE b.mile_seconds >= $3
		   AND b.mile_seconds <= $4
		   AND ${OWNER_NOT_PRIVATE_SQL("u.user_id")}
		 ORDER BY b.mile_seconds ASC
		 LIMIT ${MAX_GHOSTS}`,
    [userId, activity, MIN_GHOST_SECONDS, MAX_GHOST_SECONDS],
  );
}

/**
 * Tell friends whose ghost was just beaten.
 *
 * Called from the workout-upload path with the ids that upload just wrote.
 * Everything about this is claim-first and re-validated, because none of the
 * inputs are trustworthy on their own:
 *
 *  - `ghost_friend_user_id` is CLIENT-ASSERTED. A crafted upload could name
 *    anyone. So the friendship and the block state are re-checked here, in
 *    SQL, against the same rules the picker used. Naming a stranger buys
 *    nothing: the row simply doesn't come back.
 *  - The same workout is re-uploaded constantly (fullSync, recalibrate, the
 *    route re-push after `finishRoute`). `ghost_notified_at` is claimed in the
 *    same UPDATE that selects the work, so a re-upload can never re-push.
 *  - The claim is stamped even when the push is then suppressed by a
 *    preference or an old build. That's deliberate — "we considered this
 *    workout" is the thing being recorded, and re-considering it tomorrow
 *    would just re-suppress it.
 *
 * Never throws: a failed push must not fail a workout sync.
 */
export async function notifyGhostsBeaten(
  racerId: string,
  workoutIds: string[],
): Promise<void> {
  if (workoutIds.length === 0) return;
  try {
    // Claim and select in one statement. The friendship/block re-check lives
    // in the WHERE so an unverified id never even gets claimed — if the two
    // aren't friends, the row stays unclaimed and a later legitimate state
    // (they become friends) is still eligible.
    const rows = await db.query<{
      owner_id: string;
      margin: number;
      racer_name: string | null;
    }>(
      `UPDATE workouts w
          SET ghost_notified_at = NOW()
         FROM users racer
        WHERE w.workout_id = ANY($2::text[])
          AND w.user_id = $1
          AND racer.user_id = $1
          AND w.deleted_at IS NULL
          AND w.ghost_notified_at IS NULL
          AND w.ghost_margin_seconds IS NOT NULL
          AND w.ghost_friend_user_id IS NOT NULL
          AND w.ghost_friend_user_id <> $1
          AND EXISTS (
            SELECT 1 FROM friendships f
             WHERE f.user_id = $1
               AND f.friend_id = w.ghost_friend_user_id
               AND f.status = 'accepted'
          )
          AND NOT EXISTS (
            SELECT 1 FROM user_blocks b
             WHERE (b.blocker_id = $1 AND b.blocked_id = w.ghost_friend_user_id)
                OR (b.blocker_id = w.ghost_friend_user_id AND b.blocked_id = $1)
          )
       RETURNING w.ghost_friend_user_id AS owner_id,
                 w.ghost_margin_seconds AS margin,
                 COALESCE(racer.first_name, racer.username) AS racer_name`,
      [racerId, workoutIds],
    );

    for (const row of rows) {
      // Social pushes share the "hype" preference bucket by convention. That
      // toggle genuinely mutes this, which is what makes it a real control
      // (App Review 4.5.4). Buddy invites minted their own category only
      // because they're high-priority and would otherwise be unmutable.
      if (!(await shouldSendNotification(row.owner_id, racerId, "hype"))) {
        continue;
      }
      // Gate on the RECIPIENT's build: an older one has no handler for this
      // push, so it would arrive as a notification whose tap does nothing.
      if (
        !(await userSupports(row.owner_id, CLIENT_FEATURES.ghostFriendRaceV1))
      ) {
        continue;
      }
      const name = row.racer_name || "A friend";
      const seconds = Math.max(1, Math.round(Number(row.margin)));
      await sendPush(row.owner_id, {
        title: "Your ghost was caught",
        body: `${name} beat your mile by ${seconds}s`,
        type: "ghost_beaten",
        // Push data values must be STRING-valued — shipped builds decode the
        // inbox as [String: String], so one number breaks the whole decode.
        data: { racer_user_id: racerId, margin_seconds: String(seconds) },
      });
    }
  } catch (error: any) {
    // A workout sync must never fail because a push didn't go out.
    logError("push", `notifyGhostsBeaten: ${error?.message ?? String(error)}`, {
      userId: racerId,
    });
  }
}
