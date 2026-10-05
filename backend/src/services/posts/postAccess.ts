// Direct post/workout access: who may open ONE post or workout outside the feed
// (DIRECT_POST_ACCESS_SQL and its callers).

import { PostgresService } from "../DbService.js";
import { OWNER_NOT_PRIVATE_SQL } from "../visibilityService.js";
import {
  AUTHOR_VISIBLE_TO_VIEWER,
  VIEWER_IS_MULTI_COAUTHOR,
  COLLAB_REACH_SQL,
  FRIEND_OF_MULTI_COAUTHOR,
  COLLAB_ACTIVE,
  BLOCKED_VS_MULTI_COAUTHOR,
} from "./postSql.js";

const db = PostgresService.getInstance();

/** Both sides of a post the viewer may see. `coauthor_user_id` is the ACCEPTED
 * coauthor only (a pending invite isn't a second author yet) and is returned
 * regardless of that coauthor's own visibility setting — privacy withholds the
 * public TAG, it doesn't stop the person being an author of the post. */
export interface VisiblePostAuthors {
  author_id: string;
  coauthor_user_id: string | null;
}

/**
 * Guard tail shared by visiblePostAuthors (single) and visiblePostPreviews
 * (batch) — ONE copy so direct access and inbox previews can't drift. `$1`
 * is the viewer; the post predicate (`p.post_id = ...`) is the caller's.
 */
export const DIRECT_POST_ACCESS_SQL = `p.deleted_at IS NULL AND p.share_to_feed
			 AND ${AUTHOR_VISIBLE_TO_VIEWER}
			 AND (p.user_id = $1
				 OR p.coauthor_user_id = $1
				 OR ${VIEWER_IS_MULTI_COAUTHOR}
				 OR EXISTS (
					 SELECT 1 FROM friendships f
					 WHERE f.user_id = $1 AND f.status = 'accepted'
						 AND (f.friend_id = p.user_id
							 -- Reach through the coauthor stops when they go 'private',
							 -- exactly as it does in the feed.
							 OR (f.friend_id = p.coauthor_user_id AND ${COLLAB_REACH_SQL}))
				 )
				 OR ${FRIEND_OF_MULTI_COAUTHOR})
			 AND NOT EXISTS (
				 SELECT 1 FROM user_blocks b
				 WHERE (b.blocker_id = $1 AND b.blocked_id = p.user_id)
						OR (b.blocker_id = p.user_id AND b.blocked_id = $1)
						-- Live collabs are hidden from feeds when EITHER author is
						-- blocked; deny direct access (comments/mentions) the same way.
						OR (${COLLAB_ACTIVE} AND (
							(b.blocker_id = $1 AND b.blocked_id = p.coauthor_user_id)
							OR (b.blocker_id = p.coauthor_user_id AND b.blocked_id = $1)
						))
			 )
			 AND NOT ${BLOCKED_VS_MULTI_COAUTHOR}`;

/**
 * The post's authors IF the viewer may see the post: viewer is one of the two
 * authors or an accepted friend of one of them, the post is live on the feed,
 * and no block exists in either direction. Null when not visible — callers map
 * that to 404 so post existence isn't leaked. Shared by comments, mentions and
 * hypes, so all three agree on who can touch a collab post.
 *
 * `coauthor_user_id` stays the LEGACY scalar coauthor — multi-collab
 * participants are read via `acceptedCoauthorIds` where a caller needs them
 * all, so the two-author contract every existing caller depends on is intact.
 */
export async function visiblePostAuthors(
  viewerId: string,
  postId: string,
): Promise<VisiblePostAuthors | null> {
  const rows = await db.query<VisiblePostAuthors>(
    `SELECT p.user_id AS author_id,
				CASE WHEN ${COLLAB_ACTIVE} THEN p.coauthor_user_id END
					AS coauthor_user_id
		 FROM posts p
		 WHERE p.post_id = $2 AND ${DIRECT_POST_ACCESS_SQL}`,
    [viewerId, postId],
  );
  return rows[0] ?? null;
}

const POST_UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Batch: the subset of `postIds` the viewer may see (same guards as
 * visiblePostAuthors) with each post's media path — feeds the notification
 * inbox's per-row post thumbnails. Non-uuid strings are filtered out here
 * (the ANY cast would 500 on garbage), so ids straight from untrusted push
 * payload data are safe to pass. Sign media urls before responding.
 */
export interface VisiblePostPreview {
  post_id: string;
  media_url: string;
  // Fields lockUnearnedPhotos needs to apply the "run to see today's
  // photos" gate to inbox thumbnails exactly as the feed applies it.
  user_id: string;
  local_date: string | null;
  is_auto: boolean;
  photo_locked?: boolean;
}

export async function visiblePostPreviews(
  viewerId: string,
  postIds: string[],
): Promise<VisiblePostPreview[]> {
  const ids = postIds.filter((id) => POST_UUID_RE.test(id));
  if (ids.length === 0) return [];
  return db.query<VisiblePostPreview>(
    `SELECT p.post_id, p.media_url, p.user_id,
				p.local_date::text AS local_date, p.is_auto
		 FROM posts p
		 WHERE p.post_id = ANY($2::uuid[]) AND ${DIRECT_POST_ACCESS_SQL}`,
    [viewerId, ids],
  );
}

/** The post's PRIMARY author if the viewer may see it — see visiblePostAuthors. */
export async function visiblePostAuthor(
  viewerId: string,
  postId: string,
): Promise<string | null> {
  return (await visiblePostAuthors(viewerId, postId))?.author_id ?? null;
}

/**
 * The workout's author IF the viewer may see that raw workout activity in the
 * unified feed. Null when not visible — callers map that to 404 so workout
 * existence is not leaked.
 */
export async function visibleWorkoutAuthor(
  viewerId: string,
  workoutId: string,
): Promise<string | null> {
  const rows = await db.query<{ user_id: string }>(
    `SELECT w.user_id FROM workouts w
		 LEFT JOIN notification_settings ns ON ns.user_id = w.user_id
		 WHERE w.workout_id = $2
			 AND w.deleted_at IS NULL
			 AND w.exclusion_reason IS NULL
			 AND (w.user_id = $1 OR COALESCE(ns.share_workouts_to_feed, true) = true)
			 AND (w.user_id = $1 OR ${OWNER_NOT_PRIVATE_SQL("w.user_id")})
			 AND (w.user_id = $1 OR EXISTS (
				 SELECT 1 FROM friendships f
				 WHERE f.user_id = $1 AND f.friend_id = w.user_id
					 AND f.status = 'accepted'
			 ))
			 AND NOT EXISTS (
				 SELECT 1 FROM user_blocks b
				 WHERE (b.blocker_id = $1 AND b.blocked_id = w.user_id)
						OR (b.blocker_id = w.user_id AND b.blocked_id = $1)
			 )`,
    [viewerId, workoutId],
  );
  return rows[0]?.user_id ?? null;
}
