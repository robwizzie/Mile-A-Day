import { PostgresService } from "./DbService.js";
import { sendPush } from "./pushNotificationService.js";

const db = PostgresService.getInstance();

// Shared circle + symmetric-block fragment. `$1` is always the viewer id.
// `circle` = the viewer's accepted friends plus the viewer themself; blocked
// ids (either direction) are excluded so neither party sees the other.
const CIRCLE_CTE = `
WITH circle AS (
	SELECT friend_id AS uid FROM friendships WHERE user_id = $1 AND status = 'accepted'
	UNION
	SELECT $1 AS uid
),
blocked AS (
	SELECT blocked_id AS uid FROM user_blocks WHERE blocker_id = $1
	UNION
	SELECT blocker_id AS uid FROM user_blocks WHERE blocked_id = $1
)`;

export interface PostStatsSnapshot {
  distance?: number;
  pace?: number | null;
  duration?: number | null;
  streak?: number | null;
  date?: string | null;
}

export interface PostRow {
  post_id: string;
  user_id: string;
  username: string | null;
  first_name: string | null;
  last_name: string | null;
  profile_image_url: string | null;
  media_url: string;
  caption: string | null;
  workout_id: string | null;
  stats_snapshot: PostStatsSnapshot | null;
  local_date: string;
  share_to_feed: boolean;
  share_to_story: boolean;
  story_expires_at: string | null;
  created_at: string;
  is_self: boolean;
  is_hyped: boolean;
  hype_count: number;
  is_viewed?: boolean;
}

export interface StoryGroup {
  user_id: string;
  username: string | null;
  first_name: string | null;
  last_name: string | null;
  profile_image_url: string | null;
  story_count: number;
  has_unviewed: boolean;
  latest_at: string;
}

// SELECT list shared by feed + story-detail reads so both shapes match PostRow.
// `$1` must be the viewer id (drives is_self / is_hyped).
const POST_SELECT = `
	p.post_id,
	p.user_id,
	u.username,
	u.first_name,
	u.last_name,
	u.profile_image_url,
	p.media_url,
	p.caption,
	p.workout_id,
	p.stats_snapshot,
	p.local_date::text AS local_date,
	p.share_to_feed,
	p.share_to_story,
	p.story_expires_at,
	p.created_at,
	(p.user_id = $1) AS is_self,
	EXISTS (
		SELECT 1 FROM hype_log h
		WHERE h.sender_id = $1
			AND h.target_id = p.user_id
			AND h.context_type = 'post'
			AND h.context_id = p.post_id::text
	) AS is_hyped,
	(
		SELECT COUNT(*)::int FROM hype_log hc
		WHERE hc.context_type = 'post' AND hc.context_id = p.post_id::text
	) AS hype_count`;

export interface CreatePostInput {
  userId: string;
  mediaUrl: string;
  caption?: string | null;
  workoutId?: string | null;
  localDate: string;
  shareToFeed: boolean;
  shareToStory: boolean;
  statsSnapshot?: PostStatsSnapshot | null;
}

/**
 * Insert a post and return it shaped as a PostRow (is_self=true, no hypes yet).
 * story_expires_at is set to now()+24h only when the post is shared to a story.
 */
export async function createPost(input: CreatePostInput): Promise<PostRow> {
  const rows = await db.query<PostRow>(
    `
		WITH inserted AS (
			INSERT INTO posts (
				user_id, media_url, caption, workout_id, stats_snapshot,
				local_date, share_to_feed, share_to_story, story_expires_at
			)
			VALUES (
				$1, $2, $3, $4, $5::jsonb, $6::date, $7, $8,
				CASE WHEN $8 THEN NOW() + INTERVAL '24 hours' ELSE NULL END
			)
			RETURNING *
		)
		SELECT
			p.post_id, p.user_id, u.username, u.first_name, u.last_name, u.profile_image_url,
			p.media_url, p.caption, p.workout_id, p.stats_snapshot, p.local_date::text AS local_date,
			p.share_to_feed, p.share_to_story, p.story_expires_at, p.created_at,
			true AS is_self, false AS is_hyped, 0 AS hype_count
		FROM inserted p
		JOIN users u ON u.user_id = p.user_id
		`,
    [
      input.userId,
      input.mediaUrl,
      input.caption ?? null,
      input.workoutId ?? null,
      input.statsSnapshot ? JSON.stringify(input.statsSnapshot) : null,
      input.localDate,
      input.shareToFeed,
      input.shareToStory,
    ],
  );
  return rows[0];
}

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
  }>(
    `
		${CIRCLE_CTE}
		SELECT
			p.user_id, u.username, u.first_name, u.last_name, u.profile_image_url, p.created_at,
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
      });
    } else {
      g.story_count += 1;
      g.has_unviewed = g.has_unviewed || !r.is_viewed;
      if (r.created_at > g.latest_at) g.latest_at = r.created_at;
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
			) AS is_viewed
		FROM posts p
		JOIN circle c ON c.uid = p.user_id
		JOIN users u ON u.user_id = p.user_id
		WHERE p.user_id = $2
			AND p.share_to_story
			AND p.deleted_at IS NULL
			AND p.story_expires_at > NOW()
			AND p.user_id NOT IN (SELECT uid FROM blocked)
		ORDER BY p.created_at ASC
		`,
    [viewerId, authorId],
  );
  return rows;
}

/** Record that the viewer saw a story. Idempotent. */
export async function markStoryViewed(
  viewerId: string,
  postId: string,
): Promise<void> {
  await db.query(
    `INSERT INTO story_views (post_id, viewer_id) VALUES ($1, $2)
		 ON CONFLICT (post_id, viewer_id) DO NOTHING`,
    [postId, viewerId],
  );
}

/**
 * Persistent feed: photo posts from the viewer's circle, newest first, keyset
 * paginated on created_at. Pass `before` (an ISO timestamp) to fetch older.
 */
export async function getFeed(
  viewerId: string,
  limit: number,
  before?: string | null,
): Promise<PostRow[]> {
  const rows = await db.query<PostRow>(
    `
		${CIRCLE_CTE}
		SELECT ${POST_SELECT}
		FROM posts p
		JOIN circle c ON c.uid = p.user_id
		JOIN users u ON u.user_id = p.user_id
		WHERE p.share_to_feed
			AND p.deleted_at IS NULL
			AND p.user_id NOT IN (SELECT uid FROM blocked)
			AND ($2::timestamptz IS NULL OR p.created_at < $2::timestamptz)
		ORDER BY p.created_at DESC
		LIMIT $3
		`,
    [viewerId, before ?? null, limit],
  );
  return rows;
}

// One row of the unified feed — either a photo `post` or a raw `workout`
// activity. Type-specific columns are null for the other kind.
export interface FeedEntryRow {
  kind: "post" | "workout";
  id: string;
  sort_ts: string;
  user_id: string;
  username: string | null;
  first_name: string | null;
  last_name: string | null;
  profile_image_url: string | null;
  // post-only
  media_url: string | null;
  caption: string | null;
  stats_snapshot: PostStatsSnapshot | null;
  // workout-only
  workout_type: string | null;
  distance: number | null;
  total_duration: number | null;
  calories: number | null;
  steps: number | null;
  // shared
  is_self: boolean;
  is_hyped: boolean;
  hype_count: number;
}

/**
 * Unified, infinitely-scrollable feed: photo posts AND raw workout activity from
 * the viewer's circle, interleaved newest-first, keyset-paginated on a combined
 * timestamp (`before`). A workout that already has a feed post is omitted (the
 * post represents it), and a user's raw workouts are hidden when they've turned
 * off `share_workouts_to_feed`. No time window — paginate as far back as desired.
 */
export async function getUnifiedFeed(
  viewerId: string,
  limit: number,
  before?: string | null,
): Promise<FeedEntryRow[]> {
  const rows = await db.query<FeedEntryRow>(
    `
		${CIRCLE_CTE}
		SELECT * FROM (
			SELECT
				'post' AS kind,
				p.post_id::text AS id,
				p.created_at AS sort_ts,
				p.user_id, u.username, u.first_name, u.last_name, u.profile_image_url,
				p.media_url, p.caption, p.stats_snapshot,
				NULL::varchar AS workout_type,
				NULL::double precision AS distance,
				NULL::double precision AS total_duration,
				NULL::double precision AS calories,
				NULL::integer AS steps,
				(p.user_id = $1) AS is_self,
				EXISTS (
					SELECT 1 FROM hype_log h
					WHERE h.sender_id = $1 AND h.target_id = p.user_id
						AND h.context_type = 'post' AND h.context_id = p.post_id::text
				) AS is_hyped,
				(SELECT COUNT(*)::int FROM hype_log hc
					WHERE hc.context_type = 'post' AND hc.context_id = p.post_id::text) AS hype_count
			FROM posts p
			JOIN circle c ON c.uid = p.user_id
			JOIN users u ON u.user_id = p.user_id
			WHERE p.share_to_feed AND p.deleted_at IS NULL
				AND p.user_id NOT IN (SELECT uid FROM blocked)

			UNION ALL

			SELECT
				'workout' AS kind,
				w.workout_id AS id,
				w.device_end_date AS sort_ts,
				w.user_id, u.username, u.first_name, u.last_name, u.profile_image_url,
				NULL::text AS media_url, NULL::text AS caption, NULL::jsonb AS stats_snapshot,
				w.workout_type,
				w.distance::double precision,
				w.total_duration::double precision,
				w.calories::double precision,
				w.steps,
				(w.user_id = $1) AS is_self,
				EXISTS (
					SELECT 1 FROM hype_log h
					WHERE h.sender_id = $1 AND h.target_id = w.user_id
						AND h.context_type = 'mile' AND h.context_id = w.workout_id
				) AS is_hyped,
				(SELECT COUNT(*)::int FROM hype_log hc
					WHERE hc.context_type = 'mile' AND hc.context_id = w.workout_id) AS hype_count
			FROM workouts w
			JOIN circle c ON c.uid = w.user_id
			JOIN users u ON u.user_id = w.user_id
			LEFT JOIN notification_settings ns ON ns.user_id = w.user_id
			WHERE w.user_id NOT IN (SELECT uid FROM blocked)
				AND COALESCE(ns.share_workouts_to_feed, true) = true
				AND w.deleted_at IS NULL AND w.exclusion_reason IS NULL
				AND NOT EXISTS (
					SELECT 1 FROM posts p2
					WHERE p2.workout_id = w.workout_id AND p2.deleted_at IS NULL AND p2.share_to_feed
				)
		) feed
		WHERE ($2::timestamptz IS NULL OR sort_ts < $2::timestamptz)
		ORDER BY sort_ts DESC
		LIMIT $3
		`,
    [viewerId, before ?? null, limit],
  );
  return rows;
}

/**
 * A user's permanent feed posts (newest first) for the Instagram-style profile
 * grid. Viewer must be the author or an accepted friend, and not blocked.
 * Returns [] when not allowed to view.
 */
export async function getUserPosts(
  viewerId: string,
  authorId: string,
  limit: number,
  before?: string | null,
): Promise<PostRow[]> {
  const rows = await db.query<PostRow>(
    `
		${CIRCLE_CTE}
		SELECT ${POST_SELECT}
		FROM posts p
		JOIN users u ON u.user_id = p.user_id
		WHERE p.user_id = $2
			AND p.share_to_feed
			AND p.deleted_at IS NULL
			AND EXISTS (SELECT 1 FROM circle WHERE uid = $2)
			AND $2 NOT IN (SELECT uid FROM blocked)
			AND ($3::timestamptz IS NULL OR p.created_at < $3::timestamptz)
		ORDER BY p.created_at DESC
		LIMIT $4
		`,
    [viewerId, authorId, before ?? null, limit],
  );
  return rows;
}

/**
 * Best-effort push to the author's friends that they shared a new feed post.
 * Respects each friend's `friend_posts_enabled` (default on), excludes blocks
 * both ways, and is capped to avoid fan-out storms. Never throws into the
 * caller — notifications must not block post creation.
 */
export async function notifyFriendsOfPost(
  authorId: string,
  caption: string | null,
): Promise<void> {
  try {
    const recipients = await db.query<{ uid: string }>(
      `SELECT f.friend_id AS uid
			 FROM friendships f
			 LEFT JOIN notification_settings ns ON ns.user_id = f.friend_id
			 WHERE f.user_id = $1 AND f.status = 'accepted'
				 AND COALESCE(ns.friend_posts_enabled, true) = true
				 AND f.friend_id NOT IN (
					 SELECT blocked_id FROM user_blocks WHERE blocker_id = $1
					 UNION
					 SELECT blocker_id FROM user_blocks WHERE blocked_id = $1
				 )
			 LIMIT 25`,
      [authorId],
    );
    if (recipients.length === 0) return;

    const authorRows = await db.query<{ username: string | null }>(
      `SELECT username FROM users WHERE user_id = $1`,
      [authorId],
    );
    const name = authorRows[0]?.username ?? "A friend";
    const trimmed = caption?.trim() ?? "";
    const body =
      trimmed.length > 0 ? trimmed.slice(0, 120) : "shared a new post";

    for (const r of recipients) {
      sendPush(r.uid, {
        title: `${name} posted 📸`,
        body,
        type: "friend_post",
        data: { user_id: authorId, kind: "post" },
      }).catch((e: any) =>
        console.error("[notifyFriendsOfPost]", e?.message ?? e),
      );
    }
  } catch (e: any) {
    console.error("[notifyFriendsOfPost] failed:", e?.message ?? e);
  }
}

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
