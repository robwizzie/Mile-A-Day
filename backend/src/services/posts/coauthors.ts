// Collab coauthors: multi-person credit rows, invite responses and the
// coauthor's per-post switches.

import { PostgresService } from "../DbService.js";
import { COLLAB_ACTIVE } from "./postSql.js";
import { notifyCoauthorInvite } from "./postNotifications.js";

const db = PostgresService.getInstance();

/**
 * Write the post_coauthors rows for a multi-person collab and notify everyone.
 *
 * The participant mirrored into the legacy scalar columns is inserted here too,
 * so post_coauthors is the COMPLETE list — code reading it never has to union
 * it with the scalars to know who is on a post.
 *
 * Rows start 'accepted', Instagram-style, matching what the scalar path does at
 * insert: tagging is immediate and the way out is removing yourself
 * (respondToMultiCoauthorInvite with accept=false). 'pending' would be worse
 * here than it ever was for the scalar path — there is no accept step left in
 * the app, so every participant past the mirrored one would sit un-credited
 * forever and a four-person buddy recap would publicly credit exactly one
 * person.
 */
export async function attachMultiCoauthors(
  postId: string,
  authorId: string,
  coauthorIds: string[],
  mirroredCoauthorId: string | null,
  buddySessionId: string | null,
  notify: boolean = true,
): Promise<void> {
  for (const coauthorId of coauthorIds) {
    await db.query(
      `INSERT INTO post_coauthors (post_id, user_id, status, buddy_session_id)
			 VALUES ($1, $2, 'accepted', $3)
			 ON CONFLICT (post_id, user_id) DO NOTHING`,
      [postId, coauthorId, buddySessionId],
    );
  }

  // The mirrored participant already gets notifyCoauthorInvite from the legacy
  // path — notifying them again here would double-push for one invite.
  const toNotify = notify
    ? coauthorIds.filter((id) => id !== mirroredCoauthorId)
    : [];
  for (const coauthorId of toNotify) {
    void notifyCoauthorInvite(authorId, coauthorId, postId).catch(() => {
      /* a failed invite push must never fail the post */
    });
  }
}

/** The post's author id, or null when the post is gone. */
export async function postAuthorId(postId: string): Promise<string | null> {
  const rows = await db.query<{ user_id: string }>(
    `SELECT user_id FROM posts WHERE post_id = $1 AND deleted_at IS NULL`,
    [postId],
  );
  return rows[0]?.user_id ?? null;
}

/**
 * Everyone credited on a post, legacy scalar and multi-collab alike.
 *
 * Callers that fan out notifications or run moderation need the full set;
 * `acceptedCoauthor` (singular) remains for the legacy two-person paths.
 */
export async function acceptedCoauthorIds(postId: string): Promise<string[]> {
  const rows = await db.query<{ user_id: string }>(
    `SELECT user_id FROM post_coauthors
		  WHERE post_id = $1 AND status = 'accepted'
		 UNION
		 SELECT coauthor_user_id AS user_id FROM posts
		  WHERE post_id = $1 AND coauthor_status = 'accepted'
		    AND coauthor_user_id IS NOT NULL AND deleted_at IS NULL`,
    [postId],
  );
  return rows.map((r) => r.user_id);
}

/**
 * Accept or decline a multi-person collab invite.
 *
 * Mirrors respondToCoauthorInvite: declining works after acceptance too
 * ("leave post"). When the responder is ALSO the one mirrored into the legacy
 * scalar columns, both representations are updated together so old and new
 * clients never disagree about whether they're on the post.
 */
export async function respondToMultiCoauthorInvite(
  userId: string,
  postId: string,
  accept: boolean,
): Promise<boolean> {
  const updated = await db.query<{ user_id: string }>(
    `UPDATE post_coauthors
		    SET status = $3, responded_at = NOW()
		  WHERE post_id = $1 AND user_id = $2
		  RETURNING user_id`,
    [postId, userId, accept ? "accepted" : "declined"],
  );
  if (updated.length === 0) return false;

  // Keep the legacy mirror in step when this responder is the mirrored one —
  // byte-for-byte the same writes respondToCoauthorInvite makes, including
  // clearing coauthor_workout_id on the way out. Leaving that id behind keeps
  // the departed person's own mile suppressed in the unified feed forever,
  // which is the opposite of what removing yourself should do.
  if (accept) {
    await db.query(
      `UPDATE posts SET
					coauthor_status = 'accepted',
					coauthor_workout_id = (
						SELECT w.workout_id FROM workouts w
						WHERE w.user_id = $2 AND w.local_date = posts.local_date
							AND w.deleted_at IS NULL AND w.exclusion_reason IS NULL
						ORDER BY w.distance DESC LIMIT 1
					)
			  WHERE post_id = $1 AND coauthor_user_id = $2 AND deleted_at IS NULL`,
      [postId, userId],
    );
  } else {
    await db.query(
      `UPDATE posts SET
					coauthor_user_id = NULL, coauthor_status = NULL, coauthor_workout_id = NULL
			  WHERE post_id = $1 AND coauthor_user_id = $2 AND deleted_at IS NULL`,
      [postId, userId],
    );
  }

  return true;
}

/**
 * The post's LIVE coauthor, if any (comment notifications + moderation). A
 * block between the two authors ends the collab, so it also stops the pushes
 * that ride on it.
 */
export async function acceptedCoauthor(postId: string): Promise<string | null> {
  const rows = await db.query<{ coauthor_user_id: string }>(
    `SELECT p.coauthor_user_id FROM posts p
		 WHERE p.post_id = $1 AND ${COLLAB_ACTIVE} AND p.deleted_at IS NULL`,
    [postId],
  );
  return rows[0]?.coauthor_user_id ?? null;
}

/**
 * Coauthor accepts or declines a collab invite. Decline also works AFTER
 * acceptance ("leave post") — it clears the collab entirely. On accept, the
 * coauthor's own mile that day (their biggest workout on the post's
 * local_date) is linked so it stops duplicating in the unified feed.
 */
export async function respondToCoauthorInvite(
  userId: string,
  postId: string,
  accept: boolean,
): Promise<{ author_id: string } | null> {
  const rows = accept
    ? await db.query<{ author_id: string }>(
        `UPDATE posts SET
					coauthor_status = 'accepted',
					coauthor_workout_id = (
						SELECT w.workout_id FROM workouts w
						WHERE w.user_id = $1 AND w.local_date = posts.local_date
							AND w.deleted_at IS NULL AND w.exclusion_reason IS NULL
						ORDER BY w.distance DESC LIMIT 1
					)
				 WHERE post_id = $2 AND coauthor_user_id = $1
					 -- Tags are accepted on creation now, so 'accepted' is the normal
					 -- state here. Kept idempotent rather than pending-only: an older
					 -- build still shows Accept, and that tap must succeed as a no-op
					 -- instead of 404ing on a collab the user is already part of.
					 AND coauthor_status IN ('pending', 'accepted')
					 AND deleted_at IS NULL
				 RETURNING user_id AS author_id`,
        [userId, postId],
      )
    : await db.query<{ author_id: string }>(
        `UPDATE posts SET
					coauthor_user_id = NULL, coauthor_status = NULL, coauthor_workout_id = NULL
				 WHERE post_id = $2 AND coauthor_user_id = $1 AND deleted_at IS NULL
				 RETURNING user_id AS author_id`,
        [userId, postId],
      );
  return rows[0] ?? null;
}

/**
 * The coauthor pins this collab on or off their own profile GRID. Distinct
 * from respondToCoauthorInvite(accept:false), which severs the tag outright:
 * here the tag stays live everywhere it already was — the Tagged tab, the
 * author's grid, both circles' feeds, the card's "alice & bob" header — and
 * only the coauthor's curated Posts grid changes.
 *
 * Writes an explicit override, so a later flip of `tagged_posts_on_profile`
 * leaves this post where the user put it. Returns null when the caller isn't
 * this post's coauthor.
 */
export async function setCoauthorProfileVisibility(
  userId: string,
  postId: string,
  onProfile: boolean,
): Promise<{ author_id: string } | null> {
  const scalar = await db.query<{ author_id: string }>(
    `UPDATE posts SET coauthor_on_profile = $3
		 WHERE post_id = $2 AND coauthor_user_id = $1 AND deleted_at IS NULL
		 RETURNING user_id AS author_id`,
    [userId, postId, onProfile],
  );
  // Writes the multi-person row too, for the same reason
  // setCoauthorFeedVisibility does: a buddy post carries the same person in
  // BOTH representations, so moving only one makes the switch read as broken
  // from whichever surface asks the other. And for everyone on a crew who is
  // not the legacy scalar — four people out of five on the walk in front of
  // me — this is the ONLY row there is: the scalar UPDATE matched nothing, so
  // the call returned null, the controller 404'd, and "Add to grid" was a
  // button that could never work for them.
  const multi = await db.query<{ author_id: string }>(
    `UPDATE post_coauthors pca SET on_profile = $3
		 FROM posts p
		 WHERE pca.post_id = $2 AND pca.user_id = $1
			 AND p.post_id = pca.post_id AND p.deleted_at IS NULL
		 RETURNING p.user_id AS author_id`,
    [userId, postId, onProfile],
  );
  return scalar[0] ?? multi[0] ?? null;
}

/**
 * The coauthor's REACH switch: does this collab go to my friends' feeds?
 *
 * Separate call from the profile one because they are separate decisions and
 * bundling them would force a user to give up the tag to quiet the broadcast.
 * Writes the legacy scalar AND the multi-person row in one go where both
 * exist, for the same reason respondToCoauthorController does: a buddy post
 * carries the same person in both representations, and a switch that only
 * moved one of them would read as not working from whichever surface asked
 * the other.
 */
export async function setCoauthorFeedVisibility(
  userId: string,
  postId: string,
  onFeed: boolean,
): Promise<{ author_id: string } | null> {
  const scalar = await db.query<{ author_id: string }>(
    `UPDATE posts SET coauthor_on_feed = $3
		 WHERE post_id = $2 AND coauthor_user_id = $1 AND deleted_at IS NULL
		 RETURNING user_id AS author_id`,
    [userId, postId, onFeed],
  );
  const multi = await db.query<{ author_id: string }>(
    `UPDATE post_coauthors pca SET on_feed = $3
		 FROM posts p
		 WHERE pca.post_id = $2 AND pca.user_id = $1
			 AND p.post_id = pca.post_id AND p.deleted_at IS NULL
		 RETURNING p.user_id AS author_id`,
    [userId, postId, onFeed],
  );
  return scalar[0] ?? multi[0] ?? null;
}

/**
 * The coauthor's ROUTE switch for one post: is MY trace drawn on this card?
 *
 * Only meaningful on the multi-person representation — `post_coauthors` is
 * where a participant's route is resolved from (CREW_ROUTE_SQL), and the
 * legacy scalar coauthor has never had a route on the card at all. Passing
 * null restores "follow my global Share route maps setting", which is what
 * every row starts as.
 */
export async function setCoauthorRoutePreference(
  userId: string,
  postId: string,
  includeRoute: boolean | null,
): Promise<{ author_id: string } | null> {
  const rows = await db.query<{ author_id: string }>(
    `UPDATE post_coauthors pca SET include_route = $3
		 FROM posts p
		 WHERE pca.post_id = $2 AND pca.user_id = $1
			 AND p.post_id = pca.post_id AND p.deleted_at IS NULL
		 RETURNING p.user_id AS author_id`,
    [userId, postId, includeRoute],
  );
  return rows[0] ?? null;
}
