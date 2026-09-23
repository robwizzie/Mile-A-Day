// Post lifecycle: author lookup, edit, soft/moderator delete and UGC terms
// acceptance.

import { PostgresService } from "../DbService.js";

const db = PostgresService.getInstance();

/** The author of a post (for hype targeting / report validation). */
export async function getPostAuthor(postId: string): Promise<string | null> {
  const rows = await db.query<{ user_id: string }>(
    `SELECT user_id FROM posts WHERE post_id = $1 AND deleted_at IS NULL`,
    [postId],
  );
  return rows[0]?.user_id ?? null;
}

/**
 * Soft-delete a post the caller authored. Returns true if a row was deleted,
 * false if the post doesn't exist or isn't theirs (caller maps to 403/404).
 */
export async function softDeletePost(
  authorId: string,
  postId: string,
): Promise<boolean> {
  const rows = await db.query<{ post_id: string }>(
    `UPDATE posts SET deleted_at = NOW()
		 WHERE post_id = $1 AND user_id = $2 AND deleted_at IS NULL
		 RETURNING post_id`,
    [postId, authorId],
  );
  return rows.length > 0;
}

export type UpdatePostResult = "ok" | "not_found" | "feed_conflict";

/**
 * Edit a post the caller authored: caption text, and/or promote a story-only
 * post onto the feed (share_to_feed = true) IN PLACE — keeping its original
 * local_date, media, and stats, unlike the story viewer's re-POST flow.
 *
 * Promotion honors the one-feed-post-per-workout slot the same way createPost
 * does: an existing AUTO route/stats card for the run is soft-deleted and
 * replaced; an existing deliberate user post returns "feed_conflict" (409).
 */
export async function updateOwnPost(
  authorId: string,
  postId: string,
  updates: {
    caption?: string | null;
    addToFeed?: boolean;
    includeRoute?: boolean;
  },
): Promise<UpdatePostResult> {
  // The route is the one part of a post the author can only decide BEFORE
  // sharing, and it is the part they most often want back: a walk that started
  // at their front door reads differently once it's on the feed. Toggling it
  // here changes nothing else — the map is resolved at read time from
  // workout_routes, so turning it off withdraws the slide rather than deleting
  // the trace, and turning it back on restores it. Each crew member's own
  // trace still answers to their own consent underneath this.
  if (updates.includeRoute !== undefined) {
    const rows = await db.query<{ post_id: string }>(
      `UPDATE posts SET include_route = $3
			 WHERE post_id = $1 AND user_id = $2 AND deleted_at IS NULL
			 RETURNING post_id`,
      [postId, authorId, updates.includeRoute],
    );
    if (rows.length === 0) return "not_found";
  }

  if (updates.caption !== undefined) {
    const rows = await db.query<{ post_id: string }>(
      `UPDATE posts SET caption = $3
			 WHERE post_id = $1 AND user_id = $2 AND deleted_at IS NULL
			 RETURNING post_id`,
      [postId, authorId, updates.caption],
    );
    if (rows.length === 0) return "not_found";
  }

  if (updates.addToFeed === true) {
    const target = await db.query<{
      post_id: string;
      share_to_feed: boolean;
    }>(
      `SELECT post_id, share_to_feed FROM posts
			 WHERE post_id = $1 AND user_id = $2 AND deleted_at IS NULL`,
      [postId, authorId],
    );
    if (target.length === 0) return "not_found";
    if (target[0].share_to_feed) return "ok"; // already on the feed

    // Single statement so the auto card can't be deleted without the
    // promotion landing (no half-applied state): `conflict` finds any live
    // feed post on the same workout; the auto one is replaced, a deliberate
    // user post blocks both CTE updates.
    const promoted = await db.query<{ post_id: string }>(
      `
			WITH target AS (
				SELECT post_id, workout_id FROM posts
				WHERE post_id = $1 AND user_id = $2 AND deleted_at IS NULL
			),
			conflict AS (
				SELECT p.post_id, p.is_auto
				FROM posts p JOIN target t ON p.workout_id = t.workout_id
				WHERE t.workout_id IS NOT NULL
					AND p.user_id = $2
					AND p.share_to_feed
					AND p.deleted_at IS NULL
					AND p.post_id <> t.post_id
			),
			replaced AS (
				UPDATE posts SET deleted_at = NOW()
				WHERE post_id IN (SELECT post_id FROM conflict WHERE is_auto)
					AND NOT EXISTS (SELECT 1 FROM conflict WHERE is_auto IS NOT TRUE)
				RETURNING post_id
			)
			UPDATE posts p SET share_to_feed = true
			FROM target t
			WHERE p.post_id = t.post_id
				AND NOT EXISTS (SELECT 1 FROM conflict WHERE is_auto IS NOT TRUE)
				-- Referencing 'replaced' forces it to run first: an unreferenced
				-- data-modifying CTE has no ordering guarantee, and promoting
				-- before the auto card's soft-delete lands would trip the
				-- one-feed-post-per-workout unique index.
				AND (SELECT COUNT(*) FROM replaced) IS NOT NULL
			RETURNING p.post_id
			`,
      [postId, authorId],
    );
    if (promoted.length === 0) return "feed_conflict";
  }

  return "ok";
}

/** Moderator override delete (privileged users) — ignores authorship. */
export async function moderatorDeletePost(postId: string): Promise<boolean> {
  const rows = await db.query<{ post_id: string }>(
    `UPDATE posts SET deleted_at = NOW() WHERE post_id = $1 AND deleted_at IS NULL RETURNING post_id`,
    [postId],
  );
  return rows.length > 0;
}

/** Whether the user has accepted the UGC terms / EULA (gate for first post). */
export async function hasAcceptedTerms(userId: string): Promise<boolean> {
  const rows = await db.query<{ terms_accepted_at: string | null }>(
    `SELECT terms_accepted_at FROM users WHERE user_id = $1`,
    [userId],
  );
  return rows[0]?.terms_accepted_at != null;
}

/** Stamp the user's one-time terms acceptance (no-op if already accepted). */
export async function acceptTerms(userId: string): Promise<string> {
  const rows = await db.query<{ terms_accepted_at: string }>(
    `UPDATE users SET terms_accepted_at = COALESCE(terms_accepted_at, NOW())
		 WHERE user_id = $1
		 RETURNING terms_accepted_at`,
    [userId],
  );
  return rows[0]?.terms_accepted_at;
}
