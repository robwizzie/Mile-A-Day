// Stories: the rail, one author's active stories, views and emoji reactions.

import { PostgresService } from "../DbService.js";
import { sendPush } from "../pushNotificationService.js";
import { shouldSendNotification } from "../notificationSettingsService.js";
import { OWNER_NOT_PRIVATE_SQL } from "../visibilityService.js";
import { type StoryGroup, type PostRow } from "./postTypes.js";
import { CIRCLE_CTE, POST_SELECT } from "./postSql.js";

const db = PostgresService.getInstance();

/**
 * Stories rail: one entry per author with an active (unexpired, non-deleted)
 * story the viewer is allowed to see. Ordered viewer-first, then unviewed
 * groups, then most-recent. The full per-author stories are fetched lazily via
 * getUserActiveStories when a ring is tapped.
 */
export async function getStoriesRail(viewerId: string): Promise<StoryGroup[]> {
  const rows = await db.query<{
    user_id: string;
    username: string | null;
    first_name: string | null;
    last_name: string | null;
    profile_image_url: string | null;
    created_at: string;
    is_viewed: boolean;
    local_date: string | null;
  }>(
    `
		${CIRCLE_CTE}
		SELECT
			p.user_id, u.username, u.first_name, u.last_name, u.profile_image_url, p.created_at,
			p.local_date::text AS local_date,
			EXISTS (
				SELECT 1 FROM story_views sv WHERE sv.post_id = p.post_id AND sv.viewer_id = $1
			) AS is_viewed
		FROM posts p
		JOIN circle c ON c.uid = p.user_id
		JOIN users u ON u.user_id = p.user_id
		WHERE p.share_to_story
			AND p.deleted_at IS NULL
			AND p.story_expires_at > NOW()
			AND p.user_id NOT IN (SELECT uid FROM blocked)
			AND ${OWNER_NOT_PRIVATE_SQL("p.user_id")}
		ORDER BY p.created_at ASC
		`,
    [viewerId],
  );

  const groups = new Map<string, StoryGroup>();
  for (const r of rows) {
    const g = groups.get(r.user_id);
    if (!g) {
      groups.set(r.user_id, {
        user_id: r.user_id,
        username: r.username,
        first_name: r.first_name,
        last_name: r.last_name,
        profile_image_url: r.profile_image_url,
        story_count: 1,
        has_unviewed: !r.is_viewed,
        latest_at: r.created_at,
        story_local_dates: r.local_date ? [r.local_date] : [],
        unviewed_local_dates:
          !r.is_viewed && r.local_date ? [r.local_date] : [],
      });
    } else {
      g.story_count += 1;
      g.has_unviewed = g.has_unviewed || !r.is_viewed;
      if (r.created_at > g.latest_at) g.latest_at = r.created_at;
      if (r.local_date && !g.story_local_dates.includes(r.local_date)) {
        g.story_local_dates.push(r.local_date);
      }
      if (
        !r.is_viewed &&
        r.local_date &&
        !g.unviewed_local_dates.includes(r.local_date)
      ) {
        g.unviewed_local_dates.push(r.local_date);
      }
    }
  }

  return Array.from(groups.values()).sort((a, b) => {
    if (a.user_id === viewerId) return -1;
    if (b.user_id === viewerId) return 1;
    if (a.has_unviewed !== b.has_unviewed) return a.has_unviewed ? -1 : 1;
    return a.latest_at < b.latest_at ? 1 : -1;
  });
}

/**
 * One author's active stories, oldest→newest (story playback order), each
 * tagged with is_viewed/is_hyped/hype_count for the viewer. Returns [] if the
 * author is outside the viewer's circle or blocked.
 */
export async function getUserActiveStories(
  viewerId: string,
  authorId: string,
): Promise<PostRow[]> {
  const rows = await db.query<PostRow>(
    `
		${CIRCLE_CTE}
		SELECT ${POST_SELECT},
			EXISTS (
				SELECT 1 FROM story_views sv WHERE sv.post_id = p.post_id AND sv.viewer_id = $1
			) AS is_viewed,
			(
				SELECT sr.emoji FROM story_reactions sr
				WHERE sr.post_id = p.post_id AND sr.user_id = $1
			) AS viewer_reaction,
			EXISTS (
				SELECT 1 FROM posts pf
				WHERE pf.workout_id = p.workout_id
					AND pf.workout_id IS NOT NULL
					AND pf.deleted_at IS NULL
					AND pf.share_to_feed
					AND NOT pf.is_auto
			) AS workout_on_feed
		FROM posts p
		JOIN circle c ON c.uid = p.user_id
		JOIN users u ON u.user_id = p.user_id
		WHERE p.user_id = $2
			AND p.share_to_story
			AND p.deleted_at IS NULL
			AND p.story_expires_at > NOW()
			AND p.user_id NOT IN (SELECT uid FROM blocked)
			AND ${OWNER_NOT_PRIVATE_SQL("p.user_id")}
		ORDER BY p.created_at ASC
		`,
    [viewerId, authorId],
  );
  return rows;
}

/**
 * Record that the viewer saw a story. Idempotent, and guarded: only records a
 * view for an ACTIVE story the viewer is actually allowed to see (author, or
 * an accepted friend of the author with no block either way) — otherwise a
 * relayed post id could inject a stranger into the author's "Seen by" list.
 */
export async function markStoryViewed(
  viewerId: string,
  postId: string,
): Promise<void> {
  await db.query(
    `INSERT INTO story_views (post_id, viewer_id)
		 SELECT p.post_id, $2
		 FROM posts p
		 WHERE p.post_id = $1
			 AND p.share_to_story
			 AND p.deleted_at IS NULL
			 AND p.story_expires_at > NOW()
			 AND (
				 p.user_id = $2
				 OR EXISTS (
					 SELECT 1 FROM friendships f
					 WHERE f.user_id = p.user_id AND f.friend_id = $2 AND f.status = 'accepted'
				 )
			 )
			 AND NOT EXISTS (
				 SELECT 1 FROM user_blocks b
				 WHERE (b.blocker_id = p.user_id AND b.blocked_id = $2)
						OR (b.blocker_id = $2 AND b.blocked_id = p.user_id)
			 )
		 ON CONFLICT (post_id, viewer_id) DO NOTHING`,
    [postId, viewerId],
  );
}

/** One row in a story's "seen by" list, with any emoji reaction. */
export interface StoryViewerRow {
  user_id: string;
  username: string | null;
  first_name: string | null;
  last_name: string | null;
  profile_image_url: string | null;
  viewed_at: string;
  emoji: string | null;
}

/**
 * Who viewed the caller's story (with their reactions), newest first. Returns
 * null when the post isn't the caller's own story — the controller maps that
 * to 404 so viewers stay private.
 */
export async function getStoryViewers(
  authorId: string,
  postId: string,
): Promise<StoryViewerRow[] | null> {
  const own = await db.query(
    `SELECT 1 FROM posts
		 WHERE post_id = $1 AND user_id = $2 AND share_to_story AND deleted_at IS NULL`,
    [postId, authorId],
  );
  if (own.length === 0) return null;

  return db.query<StoryViewerRow>(
    `
		SELECT u.user_id, u.username, u.first_name, u.last_name, u.profile_image_url,
			sv.viewed_at, sr.emoji
		FROM story_views sv
		JOIN users u ON u.user_id = sv.viewer_id
		LEFT JOIN story_reactions sr ON sr.post_id = sv.post_id AND sr.user_id = sv.viewer_id
		WHERE sv.post_id = $1 AND sv.viewer_id <> $2
		ORDER BY sr.emoji IS NULL, sv.viewed_at DESC
		LIMIT 200
		`,
    [postId, authorId],
  );
}

export interface StoryReactorRow {
  user_id: string;
  username: string | null;
  first_name: string | null;
  last_name: string | null;
  profile_image_url: string | null;
  emoji: string;
  created_at: string;
}

/**
 * Everyone who reacted to a story, for the Instagram-style bubble row shown to
 * ALL circle viewers (not just the author, unlike getStoryViewers). Returns
 * null when the caller can't see the story (author/accepted-friend, no block) —
 * the controller maps that to 404. Includes the caller's own reaction.
 */
export async function getStoryReactors(
  viewerId: string,
  postId: string,
): Promise<StoryReactorRow[] | null> {
  const allowed = await db.query(
    `SELECT 1 FROM posts p
			 WHERE p.post_id = $1 AND p.share_to_story AND p.deleted_at IS NULL
				 AND (
					 p.user_id = $2
					 OR EXISTS (
						 SELECT 1 FROM friendships f
						 WHERE f.user_id = $2 AND f.friend_id = p.user_id AND f.status = 'accepted'
					 )
				 )
				 AND NOT EXISTS (
					 SELECT 1 FROM user_blocks b
					 WHERE (b.blocker_id = $2 AND b.blocked_id = p.user_id)
							OR (b.blocker_id = p.user_id AND b.blocked_id = $2)
				 )`,
    [postId, viewerId],
  );
  if (allowed.length === 0) return null;

  return db.query<StoryReactorRow>(
    `
		SELECT u.user_id, u.username, u.first_name, u.last_name, u.profile_image_url,
			sr.emoji, sr.created_at
		FROM story_reactions sr
		JOIN users u ON u.user_id = sr.user_id
		WHERE sr.post_id = $1
		ORDER BY sr.created_at DESC
		LIMIT 200
		`,
    [postId],
  );
}

/** The ephemeral counterpart to feed hype — one emoji per (story, viewer). */
export const ALLOWED_STORY_REACTIONS = new Set([
  "\u2764\uFE0F",
  "\uD83D\uDD25",
  "\uD83D\uDC4F",
  "\uD83D\uDCAA",
  "\uD83D\uDE2E",
]);

/**
 * React to a friend's active story with an emoji. Re-reacting replaces the
 * previous emoji. Pushes a lightweight notification to the author (respects
 * their per-friend "hype" notification preference). Returns a status the
 * controller maps to HTTP.
 */
export async function reactToStory(
  senderId: string,
  postId: string,
  emoji: string,
): Promise<"ok" | "not_found" | "forbidden"> {
  const rows = await db.query<{ user_id: string }>(
    `SELECT user_id FROM posts
		 WHERE post_id = $1 AND share_to_story AND deleted_at IS NULL
			 AND story_expires_at > NOW()`,
    [postId],
  );
  const authorId = rows[0]?.user_id;
  if (!authorId) return "not_found";
  if (authorId === senderId) return "forbidden";

  // Sender must be an accepted friend of the author (stories are circle-only)
  // with no block in either direction.
  const allowed = await db.query(
    `SELECT 1 FROM friendships f
		 WHERE f.user_id = $1 AND f.friend_id = $2 AND f.status = 'accepted'
			 AND NOT EXISTS (
				 SELECT 1 FROM user_blocks b
				 WHERE (b.blocker_id = $1 AND b.blocked_id = $2)
						OR (b.blocker_id = $2 AND b.blocked_id = $1)
			 )`,
    [authorId, senderId],
  );
  if (allowed.length === 0) return "forbidden";

  const inserted = await db.query<{ inserted: boolean }>(
    `INSERT INTO story_reactions (post_id, user_id, emoji)
		 VALUES ($1, $2, $3)
		 ON CONFLICT (post_id, user_id)
		 DO UPDATE SET emoji = EXCLUDED.emoji, created_at = NOW()
		 RETURNING (xmax = 0) AS inserted`,
    [postId, senderId, emoji],
  );

  // Notify only on the FIRST reaction to this story (emoji swaps stay quiet).
  if (inserted[0]?.inserted) {
    try {
      const shouldSend = await shouldSendNotification(
        authorId,
        senderId,
        "hype",
      );
      if (shouldSend) {
        const sender = await db.query<{ username: string | null }>(
          `SELECT username FROM users WHERE user_id = $1`,
          [senderId],
        );
        const name = sender[0]?.username ?? "A friend";
        sendPush(authorId, {
          title: `${name} reacted ${emoji}`,
          body: "to your story",
          type: "story_reaction",
          data: { user_id: senderId, post_id: postId },
        }).catch((e: any) =>
          console.error("[reactToStory] push failed:", e?.message ?? e),
        );
      }
    } catch (e: any) {
      console.error("[reactToStory] notify failed:", e?.message ?? e);
    }
  }
  return "ok";
}
