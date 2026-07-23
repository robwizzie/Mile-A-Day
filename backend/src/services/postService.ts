import { PostgresService } from "./DbService.js";
import { sendPush } from "./pushNotificationService.js";
import { shouldSendNotification } from "./notificationSettingsService.js";
import {
  VIEWER_MAY_SEE_WORKOUT_CONTENT_SQL,
  OWNER_NOT_PRIVATE_SQL,
} from "./visibilityService.js";
import {
  postHypeMatchSql,
  postHypedByViewerMatchSql,
  runHypeMatchSql,
  runHypedByViewerMatchSql,
} from "./hypeService.js";

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
  is_auto: boolean;
  include_route: boolean;
  workout_type: string | null;
  is_self: boolean;
  is_hyped: boolean;
  hype_count: number;
  comment_count: number;
  // Collab post fields — null unless a coauthor exists AND (accepted, or the
  // viewer is one of the two authors; pending invites are private to them).
  coauthor_user_id?: string | null;
  coauthor_status?: "pending" | "accepted" | null;
  coauthor_username?: string | null;
  coauthor_first_name?: string | null;
  coauthor_last_name?: string | null;
  coauthor_profile_image_url?: string | null;
  is_viewed?: boolean;
  // The viewer's own emoji reaction to this story (getUserActiveStories only),
  // so re-opening a story they already reacted to shows the reaction. null/absent
  // = they haven't reacted.
  viewer_reaction?: string | null;
  // Set by lockUnearnedPhotos: this post's photo is withheld because it's from
  // the viewer's local today and they haven't finished their own mile yet.
  photo_locked?: boolean;
  // Microsecond-precise created_at (Postgres text form) for keyset pagination.
  // node-pg parses timestamptz to a ms-truncated JS Date, and a truncated
  // `before` cursor silently skips same-millisecond rows at page boundaries.
  cursor?: string;
  // The run's active story photo (getUserPosts only) — lets profile surfaces
  // lead with the real picture like the feed does.
  story_photo_url?: string | null;
  // getUserActiveStories only: does this story's workout already have a live
  // DELIBERATE feed post? Drives hiding the story viewer's "Add to feed"
  // button so it isn't offered (then 409'd) when the run is already on the
  // feed. The auto route/stats card does NOT count — promoting a story photo
  // replaces the auto card in place, which is the button's whole point.
  workout_on_feed?: boolean;
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
  /** Distinct author-local days ("yyyy-MM-dd") this group's stories span —
   *  lets the client gate viewing PER DAY (yesterday's stories stay viewable
   *  for a viewer who completed yesterday). Additive field. */
  story_local_dates: string[];
  /** Author-local days with at least one story the viewer HASN'T seen —
   *  lets the client light the "unviewed" ring only for days the viewer can
   *  actually watch, so an unearned today-story can't leave a permanently
   *  unclearable ring. Additive field. */
  unviewed_local_dates: string[];
}

/**
 * Keyset-pagination cursor as URL-safe ISO-8601 UTC with microseconds
 * ("2026-07-04T12:34:56.123456Z"). The raw `::text` of a timestamptz renders
 * as "2026-07-04 12:34:56.123456+00" — and a literal '+' in a query string is
 * decoded as a SPACE by Express's query parser, which made the returned
 * cursor fail its `::timestamptz` cast on the next page ("the feed stops
 * loading"). Microsecond precision is kept so same-millisecond rows at page
 * boundaries are neither skipped nor repeated.
 */
const URL_SAFE_CURSOR = (col: string) =>
  `to_char((${col}) AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US') || 'Z'`;

// Base post columns shared by every post-shaped read (viewer-independent).
// Routes are deliberately NOT here — only the unified feed ships them (the
// story viewer / memories / profile grid never render a route map, and the
// jsonb payload is not free).
const POST_COLUMNS = `
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
	p.is_auto,
	p.include_route,
	(SELECT w.workout_type FROM workouts w WHERE w.workout_id = p.workout_id) AS workout_type`;

// Collab-post columns. `$1` must be the viewer id: a PENDING coauthor is
// visible only to the two people involved; accepted collabs are public to
// whoever can see the post.
const COAUTHOR_VISIBLE = `(p.coauthor_user_id IS NOT NULL AND (p.coauthor_status = 'accepted' OR p.user_id = $1 OR p.coauthor_user_id = $1))`;
const COAUTHOR_COLUMNS = `
	CASE WHEN ${COAUTHOR_VISIBLE} THEN p.coauthor_user_id END AS coauthor_user_id,
	CASE WHEN ${COAUTHOR_VISIBLE} THEN p.coauthor_status END AS coauthor_status,
	(SELECT cu.username FROM users cu WHERE cu.user_id = p.coauthor_user_id AND ${COAUTHOR_VISIBLE}) AS coauthor_username,
	(SELECT cu.first_name FROM users cu WHERE cu.user_id = p.coauthor_user_id AND ${COAUTHOR_VISIBLE}) AS coauthor_first_name,
	(SELECT cu.last_name FROM users cu WHERE cu.user_id = p.coauthor_user_id AND ${COAUTHOR_VISIBLE}) AS coauthor_last_name,
	(SELECT cu.profile_image_url FROM users cu WHERE cu.user_id = p.coauthor_user_id AND ${COAUTHOR_VISIBLE}) AS coauthor_profile_image_url`;

// SELECT list shared by feed + story-detail reads so both shapes match PostRow.
// `$1` must be the viewer id (drives is_self / is_hyped).
// is_hyped is exact-card state so a different same-day mile doesn't disable
// the button; hype_count still uses the broader run tally for social proof.
const POST_SELECT = `${POST_COLUMNS},
	(p.user_id = $1) AS is_self,
	EXISTS (
		SELECT 1 FROM hype_log h
		WHERE h.sender_id = $1
			AND h.target_id = p.user_id
			AND ${postHypedByViewerMatchSql("h", "p")}
	) AS is_hyped,
	(
		SELECT COUNT(DISTINCT hc.sender_id)::int FROM hype_log hc
		WHERE hc.target_id = p.user_id
			AND ${postHypeMatchSql("hc", "p")}
	) AS hype_count,
	(
		SELECT COUNT(*)::int FROM post_comments pc
		WHERE pc.post_id = p.post_id AND pc.deleted_at IS NULL
	) AS comment_count,
	${COAUTHOR_COLUMNS}`;

export interface CreatePostInput {
  userId: string;
  mediaUrl: string;
  caption?: string | null;
  workoutId?: string | null;
  localDate: string;
  shareToFeed: boolean;
  shareToStory: boolean;
  statsSnapshot?: PostStatsSnapshot | null;
  // Tri-state: true = system auto post (route/stats card), false = deliberate
  // user post, undefined = legacy client that didn't send the flag (keeps the
  // original always-upsert behavior so shipped app versions don't break).
  isAuto?: boolean;
  includeRoute?: boolean;
  // Collab post: invite this accepted friend as coauthor (status 'pending'
  // until they accept). Ignored for auto posts.
  coauthorUserId?: string | null;
  // The author shared this inside their 10-minute fresh window (client-owned:
  // the window anchors to when the app SAW the finished workout). Drives the
  // FRESH chip for every viewer. Ignored for auto posts; legacy clients that
  // omit it get a server-side derivation in the feed query instead.
  postedLive?: boolean;
}

// Shape the freshly inserted/updated row like a PostRow (is_self=true).
const CREATED_POST_SELECT = `
	SELECT ${POST_COLUMNS},
		true AS is_self, false AS is_hyped, 0 AS hype_count, 0 AS comment_count,
		${COAUTHOR_COLUMNS}`;

/**
 * Insert a post and return it shaped as a PostRow (is_self=true, no hypes yet).
 * story_expires_at is set to now()+24h only when the post is shared to a story.
 *
 * One-deliberate-share-per-workout rules:
 * - Legacy clients (isAuto undefined) keep the original upsert-in-place.
 * - An AUTO post fills an empty slot or replaces an existing auto post; it
 *   never clobbers a deliberate user post (returns the existing post instead).
 * - A USER post (feed OR story) is allowed once per workout, across BOTH the
 *   feed and story-only slots: it fills an empty slot / replaces the auto post,
 *   but if a live user share already exists for the run — in EITHER slot — it
 *   throws "workout_already_posted". Deleting that share (or starting the next
 *   workout) frees it again. The per-slot partial unique indexes enforce the
 *   same-slot case; the cross-slot pre-check above closes the other-slot gap.
 */
export async function createPost(input: CreatePostInput): Promise<PostRow> {
  // A workout can have ONE live feed post and ONE live story-only photo
  // (separate partial unique indexes); pick the arbiter matching the row
  // being inserted so re-posting replaces the right one in place.
  const conflictTarget = input.shareToFeed
    ? `(workout_id) WHERE (deleted_at IS NULL AND workout_id IS NOT NULL AND share_to_feed)`
    : `(workout_id) WHERE (deleted_at IS NULL AND workout_id IS NOT NULL AND share_to_story AND NOT share_to_feed)`;
  // Legacy clients (still in the wild) don't send is_auto, but their auto
  // route/stats cards must stay replaceable by an updated device's photo post.
  // Classify legacy inserts with the same signature the 0008 backfill used:
  // a caption-less, feed-only post with a stats snapshot is the auto card.
  // A misfire only makes a caption-less legacy photo replaceable — which is
  // exactly the pre-flag behavior those clients already have.
  const legacyLooksAuto =
    input.caption == null &&
    input.statsSnapshot != null &&
    input.shareToFeed &&
    !input.shareToStory;
  const isAutoValue =
    input.isAuto === undefined ? legacyLooksAuto : input.isAuto === true;
  // Coauthor must be a real accepted friend (no block either way) — validated
  // here so the constraint holds no matter which controller path inserts.
  // Collabs are a FEED concept (profile grids + feed reach are feed-only) —
  // a story-only invite would be accepted into nothing. Silently ignored.
  const coauthorId =
    isAutoValue || !input.shareToFeed ? null : (input.coauthorUserId ?? null);
  if (coauthorId) {
    if (coauthorId === input.userId) throw new Error("invalid_coauthor");
    const ok = await db.query(
      `SELECT 1 FROM friendships f
			 WHERE f.user_id = $1 AND f.friend_id = $2 AND f.status = 'accepted'
				 AND NOT EXISTS (
					 SELECT 1 FROM user_blocks b
					 WHERE (b.blocker_id = $1 AND b.blocked_id = $2)
							OR (b.blocker_id = $2 AND b.blocked_id = $1)
				 )`,
      [input.userId, coauthorId],
    );
    if (ok.length === 0) throw new Error("invalid_coauthor");
  }
  // One deliberate share (a feed post OR a story) per workout — across BOTH
  // destination slots. The per-slot unique indexes already stop a second post
  // to the SAME slot; this closes the cross-slot gap where a feed post AND a
  // separate story-only photo could both be created for one run ("posting
  // again after I've posted"). Auto route/stats cards don't count as the user's
  // share and never block (a real photo still replaces them). The slot frees
  // when the existing share is deleted or the next workout starts.
  if (!isAutoValue && input.workoutId) {
    const otherSlotFilter = input.shareToFeed
      ? `(p.share_to_story AND NOT p.share_to_feed)`
      : `p.share_to_feed`;
    const existingShare = await db.query<{ post_id: string }>(
      `SELECT p.post_id FROM posts p
			WHERE p.workout_id = $1 AND p.user_id = $2
				AND p.deleted_at IS NULL AND NOT p.is_auto
				AND ${otherSlotFilter}
			LIMIT 1`,
      [input.workoutId, input.userId],
    );
    if (existingShare[0]) throw new Error("workout_already_posted");
  }
  // Only the slot's AUTO post may be overwritten in place — for legacy
  // requests too. Legacy upserts used to overwrite ANYTHING the caller owned,
  // which let an old build's background auto-card post silently DESTROY a
  // deliberate photo post's media (the old media_url is recorded nowhere, and
  // the orphan sweep then removed the photo file from disk). A blocked legacy
  // write now falls through to the yield/409 handling below instead.
  const updateGuard = `WHERE posts.user_id = $1 AND posts.is_auto`;
  // Legacy clients never sent the flags, so their upserts must not clobber a
  // stored is_auto/include_route (e.g. resetting a route opt-out to true).
  const flagUpdates =
    input.isAuto === undefined
      ? ""
      : `,
					is_auto = EXCLUDED.is_auto,
					include_route = EXCLUDED.include_route`;
  const rows = await db.query<PostRow>(
    `
		WITH inserted AS (
			INSERT INTO posts (
				user_id, media_url, caption, workout_id, stats_snapshot,
				local_date, share_to_feed, share_to_story, story_expires_at,
				is_auto, include_route, coauthor_user_id, coauthor_status,
				posted_fresh
			)
			VALUES (
				$1, $2, $3, $4, $5::jsonb, $6::date, $7, $8,
				CASE WHEN $8 THEN NOW() + INTERVAL '24 hours' ELSE NULL END,
				$9, $10, $11, CASE WHEN $11::text IS NULL THEN NULL ELSE 'pending' END,
				$12
			)
				ON CONFLICT ${conflictTarget}
				DO UPDATE SET
					media_url = EXCLUDED.media_url,
					caption = COALESCE(EXCLUDED.caption, posts.caption),
					stats_snapshot = COALESCE(EXCLUDED.stats_snapshot, posts.stats_snapshot),
					share_to_feed = EXCLUDED.share_to_feed,
					share_to_story = EXCLUDED.share_to_story,
					story_expires_at = CASE WHEN EXCLUDED.share_to_story THEN NOW() + INTERVAL '24 hours' ELSE NULL END,
					-- The update guard only ever overwrites an AUTO post, which never
					-- carries a coauthor — so taking EXCLUDED wholesale is safe.
					coauthor_user_id = EXCLUDED.coauthor_user_id,
					coauthor_status = EXCLUDED.coauthor_status,
					posted_fresh = EXCLUDED.posted_fresh${flagUpdates}
				${updateGuard}
			RETURNING *
		)
		${CREATED_POST_SELECT}
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
      isAutoValue,
      input.includeRoute !== false,
      coauthorId,
      !isAutoValue && input.postedLive === true,
    ],
  );
  if (rows[0]) return rows[0];

  // Zero rows — the slot is taken and the update guard skipped it. An auto
  // post (flagged, or a legacy insert that classifies as auto) quietly yields
  // to the caller's existing user post; anything else (another user's post,
  // or a second deliberate post) is rejected.
  if ((input.isAuto === true || legacyLooksAuto) && input.workoutId) {
    const existing = await db.query<PostRow>(
      `
			${CREATED_POST_SELECT}
			FROM posts p
			JOIN users u ON u.user_id = p.user_id
			WHERE p.workout_id = $2 AND p.user_id = $1 AND p.deleted_at IS NULL
				AND ${input.shareToFeed ? "p.share_to_feed" : "(p.share_to_story AND NOT p.share_to_feed)"}
			LIMIT 1
			`,
      [input.userId, input.workoutId],
    );
    if (existing[0]) return existing[0];
  }
  throw new Error("workout_already_posted");
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

/**
 * The caller's own past post photos for the "On this day" memories surface:
 * same calendar day in previous years only — sub-year lookbacks (a week/month
 * ago) felt too recent to be a "memory". Story-only photos count — expiry
 * hides them from the rail, not from the author's memories.
 */
export async function getOwnPostMemories(
  userId: string,
  localDate: string,
): Promise<PostRow[]> {
  return db.query<PostRow>(
    `
		SELECT ${POST_SELECT}
		FROM posts p
		JOIN users u ON u.user_id = p.user_id
		WHERE p.user_id = $1
			AND p.deleted_at IS NULL
			AND p.local_date < $2::date
			AND EXTRACT(MONTH FROM p.local_date) = EXTRACT(MONTH FROM $2::date)
			AND EXTRACT(DAY FROM p.local_date) = EXTRACT(DAY FROM $2::date)
		ORDER BY p.local_date DESC
		LIMIT 12
		`,
    [userId, localDate],
  );
}

/** The viewer's mile status for a feed read — drives the photo gate. */
export interface ViewerGoalGate {
  completed: boolean;
  localDate: string;
}

/**
 * Withhold TODAY's real photos from a viewer who hasn't finished their own mile
 * yet — "run to see your friends' pictures". Mutates and returns the rows.
 *
 * Rules (per the product decision):
 *  - Only the viewer's LOCAL today is gated; older posts always show.
 *  - Own posts are never gated (you can always see your own).
 *  - PHOTOS ONLY: a real user photo (media_url on a non-auto post) and any
 *    story_photo_url are withheld; auto route/stats cards stay visible.
 *  - Once the viewer completes their mile, nothing is gated.
 *
 * media_url is blanked to "" rather than nulled so existing (non-optional)
 * clients still decode; new clients read `photo_locked` to draw the lock state.
 * `photo_locked` marks a row that LOST a photo here — not merely one that fell
 * under the gate — so a row whose every slide survived never renders as locked.
 */
export function lockUnearnedPhotos<
  T extends {
    user_id: string;
    local_date?: string | null;
    is_auto?: boolean | null;
    media_url?: string | null;
    story_photo_url?: string | null;
    photo_locked?: boolean;
  },
>(rows: T[], viewerId: string, gate: ViewerGoalGate): T[] {
  if (gate.completed || !gate.localDate) return rows;
  for (const r of rows) {
    if (r.user_id === viewerId) continue;
    if ((r.local_date ?? null) !== gate.localDate) continue;
    let withheld = false;
    if (r.story_photo_url) {
      r.story_photo_url = null;
      withheld = true;
    }
    // Leave auto route/stats cards visible; only real photos are locked.
    if (r.is_auto !== true && r.media_url) {
      r.media_url = "";
      withheld = true;
    }
    // Only flag rows that actually LOST a photo. An auto route/stats card with
    // no story photo has nothing withheld, so it must not read as locked —
    // flagging it made clients hide a card they were meant to see.
    if (withheld) r.photo_locked = true;
  }
  return rows;
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
		SELECT ${POST_SELECT},
			${URL_SAFE_CURSOR("p.created_at")} AS cursor
		FROM posts p
		JOIN users u ON u.user_id = p.user_id
		WHERE p.share_to_feed
			AND p.deleted_at IS NULL
			-- Accepted collab posts reach BOTH authors' circles (semi-join, not a
			-- JOIN, so a post whose two authors share the viewer isn't doubled).
			AND EXISTS (
				SELECT 1 FROM circle c
				WHERE c.uid = p.user_id
					OR (p.coauthor_status = 'accepted' AND c.uid = p.coauthor_user_id)
			)
			AND p.user_id NOT IN (SELECT uid FROM blocked)
			AND (p.coauthor_status IS DISTINCT FROM 'accepted'
				OR p.coauthor_user_id NOT IN (SELECT uid FROM blocked))
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
  // The run's story-only photo (if one exists) so the feed card can offer a
  // photo/route flip without duplicating the run in the feed.
  story_photo_url: string | null;
  // post-only: system-generated route/stats card vs deliberate user post.
  is_auto: boolean | null;
  // post-only: the author's local date ("YYYY-MM-DD"), so the viewer's today can
  // be gated. Null for raw workout entries (they carry no photo to gate).
  local_date: string | null;
  // Set by lockUnearnedPhotos when this post's photo is withheld.
  photo_locked?: boolean;
  // Post entries only: shared inside the author's 10-minute fresh window and
  // still same-day — drives the FRESH chip for EVERY viewer (it used to be
  // client-local, so only the poster ever saw their own badge).
  is_fresh: boolean;
  // The entry's workout: the linked workout for posts (null when unlinked),
  // the workout itself for workout entries. Lets the client know which of
  // today's runs already carry a deliberate post.
  workout_id: string | null;
  // workout columns (also populated for posts via their linked workout)
  workout_type: string | null;
  distance: number | null;
  total_duration: number | null;
  calories: number | null;
  steps: number | null;
  // Simplified GPS trace for the entry's workout, when synced (and, for
  // posts, when the author chose to include it).
  route: [number, number][] | null;
  // shared
  is_self: boolean;
  is_hyped: boolean;
  hype_count: number;
  // Comments only exist on posts; always 0 for workout entries.
  comment_count: number;
  // Collab post fields (post entries only, same visibility rule as PostRow).
  coauthor_user_id: string | null;
  coauthor_status: "pending" | "accepted" | null;
  coauthor_username: string | null;
  coauthor_first_name: string | null;
  coauthor_last_name: string | null;
  coauthor_profile_image_url: string | null;
  // Microsecond-precise sort_ts (Postgres text form) for keyset pagination.
  cursor?: string;
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
  // PERF: the expensive per-row columns (route JSONB, is_hyped, hype_count,
  // story_photo_url) are computed ONLY for the page's rows, not for the whole
  // circle's history. The old shape put them in the SELECT list of a UNION ALL
  // that was then ORDER BY sort_ts DESC LIMIT $3 — so Postgres had to evaluate
  // them for every post AND every workout in the viewer's circle across all
  // time before the outer LIMIT could apply, and got linearly slower as the
  // workouts table grew. Now `candidates` unions only the cheap keys, `page`
  // sorts+limits them (the LIMIT is a hard barrier), and the outer SELECT
  // projects the heavy columns onto just those <= $3 rows. Output shape and
  // every value are identical to the old query; results are keyed by column
  // name so column order is irrelevant. All lookups here are already indexed
  // (idx_posts_user_created, idx_workouts_user_device_end for the candidate
  // ordering; hype_log_context_dedupe_idx / idx_hype_log_target_context for the
  // hype checks).
  const rows = await db.query<FeedEntryRow>(
    `
		${CIRCLE_CTE},
		candidates AS (
			SELECT
				'post'::text AS kind,
				p.post_id::text AS id,
				p.created_at AS sort_ts,
				p.user_id AS owner_id,
				p.workout_id AS workout_id
			FROM posts p
			WHERE p.share_to_feed AND p.deleted_at IS NULL
				-- Accepted collab posts reach BOTH authors' circles (semi-join, not
				-- a JOIN, so a post whose two authors share the viewer isn't doubled).
				AND EXISTS (
					SELECT 1 FROM circle c
					WHERE c.uid = p.user_id
						OR (p.coauthor_status = 'accepted' AND c.uid = p.coauthor_user_id)
				)
				AND p.user_id NOT IN (SELECT uid FROM blocked)
				AND (p.coauthor_status IS DISTINCT FROM 'accepted'
					OR p.coauthor_user_id NOT IN (SELECT uid FROM blocked))
				AND ${OWNER_NOT_PRIVATE_SQL("p.user_id")}

			UNION ALL

			SELECT
				'workout'::text AS kind,
				w.workout_id AS id,
				w.device_end_date AS sort_ts,
				w.user_id AS owner_id,
				w.workout_id AS workout_id
			FROM workouts w
			JOIN circle c ON c.uid = w.user_id
			LEFT JOIN notification_settings ns ON ns.user_id = w.user_id
			WHERE w.user_id NOT IN (SELECT uid FROM blocked)
				AND COALESCE(ns.share_workouts_to_feed, true) = true
				-- The feed is always YOUR circle, so 'public' must not pour
				-- strangers in; only the tightening direction applies here.
				AND ${OWNER_NOT_PRIVATE_SQL("w.user_id")}
				AND w.deleted_at IS NULL AND w.exclusion_reason IS NULL
				AND NOT EXISTS (
					SELECT 1 FROM posts p2
					WHERE p2.deleted_at IS NULL AND p2.share_to_feed
						AND (p2.workout_id = w.workout_id
							-- A collab post only stands in for the coauthor's mile when
							-- the viewer can actually SEE that post (primary author not
							-- blocked or private) — otherwise they'd get neither.
							OR (p2.coauthor_status = 'accepted'
								AND p2.coauthor_workout_id = w.workout_id
								AND p2.user_id NOT IN (SELECT uid FROM blocked)
								AND ${OWNER_NOT_PRIVATE_SQL("p2.user_id")}))
				)
		),
		page AS (
			SELECT kind, id, sort_ts, owner_id, workout_id
			FROM candidates
			WHERE ($2::timestamptz IS NULL OR sort_ts < $2::timestamptz)
			ORDER BY sort_ts DESC
			LIMIT $3
		)
		SELECT
			page.kind,
			page.id,
			page.sort_ts,
			page.owner_id AS user_id,
			u.username, u.first_name, u.last_name, u.profile_image_url,
			p.media_url, p.caption, p.stats_snapshot,
			p.local_date::text AS local_date,
			-- Owner's decision: the 24h expiry only ends the STORY (rail/viewer).
			-- A photo riding on the run's feed card stays permanently — only
			-- deleting the story removes it.
			(
				SELECT p3.media_url FROM posts p3
				WHERE page.kind = 'post'
					AND p.workout_id IS NOT NULL
					AND p3.workout_id = p.workout_id
					AND p3.user_id = p.user_id
					AND p3.post_id <> p.post_id
					AND p3.deleted_at IS NULL
					AND p3.share_to_story AND NOT p3.share_to_feed
				ORDER BY p3.created_at DESC
				LIMIT 1
			) AS story_photo_url,
			p.is_auto,
			page.workout_id,
			-- Populated for posts (via their linked workout) and workouts alike.
			wt.workout_type,
			CASE WHEN page.kind = 'workout' THEN wt.distance::double precision END AS distance,
			CASE WHEN page.kind = 'workout' THEN wt.total_duration::double precision END AS total_duration,
			CASE WHEN page.kind = 'workout' THEN wt.calories::double precision END AS calories,
			CASE WHEN page.kind = 'workout' THEN wt.steps END AS steps,
			-- Auto posts' media already IS the rendered route card, so shipping
			-- the polyline too would only duplicate pixels and bloat the page.
			-- Gated on the author's global "Share route maps" consent setting;
			-- posts additionally honor the per-post include_route choice. Raw
			-- workout routes respect the same setting (the owner always sees
			-- their own).
			CASE
				WHEN page.kind = 'post' THEN (
					SELECT wr.route FROM workout_routes wr
					WHERE p.include_route AND NOT p.is_auto
						AND (COALESCE(nsp.share_route_maps, true) OR page.owner_id = $1)
						AND wr.workout_id = p.workout_id
				)
				ELSE (
					SELECT wr.route FROM workout_routes wr
					WHERE (COALESCE(nsp.share_route_maps, true) OR page.owner_id = $1)
						AND wr.workout_id = wt.workout_id
				)
			END AS route,
			(page.owner_id = $1) AS is_self,
			-- Unified RUN rule: a post/workout linked to a run counts the run's
			-- 'mile' hypes (inbox / friends list) AND 'post' hypes on any linked
			-- post — same number on every surface for the same run.
			CASE
				WHEN page.kind = 'post' THEN EXISTS (
					SELECT 1 FROM hype_log h
					WHERE h.sender_id = $1 AND h.target_id = page.owner_id
						AND ${postHypedByViewerMatchSql("h", "p")}
				)
				ELSE EXISTS (
					SELECT 1 FROM hype_log h
					WHERE h.sender_id = $1 AND h.target_id = page.owner_id
						AND ${runHypedByViewerMatchSql("h", "wt")}
				)
			END AS is_hyped,
			CASE
				WHEN page.kind = 'post' THEN (
					SELECT COUNT(DISTINCT hc.sender_id)::int FROM hype_log hc
					WHERE hc.target_id = page.owner_id
						AND ${postHypeMatchSql("hc", "p")}
				)
				ELSE (
					SELECT COUNT(DISTINCT hc.sender_id)::int FROM hype_log hc
					WHERE hc.target_id = page.owner_id
						AND ${runHypeMatchSql("hc", "wt")}
				)
			END AS hype_count,
			CASE WHEN page.kind = 'post' THEN (
				SELECT COUNT(*)::int FROM post_comments pc
				WHERE pc.post_id = p.post_id AND pc.deleted_at IS NULL
			) ELSE 0 END AS comment_count,
			-- FRESH chip, for every viewer. Truth order: the client's own claim
			-- (posted_fresh, stamped at create when the author's 10-min window
			-- was open) wins; legacy builds that never sent it fall back to a
			-- server derivation — posted within 10 min of the workout reaching
			-- the backend. Display capped to 24h so old posts don't wear it.
			(
				page.kind = 'post'
				AND p.created_at > NOW() - INTERVAL '24 hours'
				AND (
					p.posted_fresh
					OR (
						NOT p.is_auto
						AND p.workout_id IS NOT NULL
						AND wt.created_at IS NOT NULL
						AND p.created_at <= wt.created_at + INTERVAL '10 minutes'
					)
				)
			) AS is_fresh,
			${COAUTHOR_COLUMNS},
			${URL_SAFE_CURSOR("page.sort_ts")} AS cursor
		FROM page
		JOIN users u ON u.user_id = page.owner_id
		LEFT JOIN posts p ON page.kind = 'post' AND p.post_id::text = page.id
		LEFT JOIN workouts wt ON wt.workout_id = page.workout_id
		LEFT JOIN notification_settings nsp ON nsp.user_id = page.owner_id
		ORDER BY page.sort_ts DESC
		`,
    [viewerId, before ?? null, limit],
  );
  return rows;
}

/**
 * A user's permanent feed posts (newest first) for the Instagram-style profile
 * grid. Viewer must be the author or an accepted friend, and not blocked.
 * Returns [] when not allowed to view.
 *
 * `includeStoryOnly` (self-view only — the controller enforces it) also
 * returns the author's story-only posts whose workout has NO live feed post,
 * so the owner can review them and promote one onto the feed. Story photos
 * whose run is already on the feed stay excluded — they already surface as
 * that feed post's story_photo_url slide.
 */
export async function getUserPosts(
  viewerId: string,
  authorId: string,
  limit: number,
  before?: string | null,
  includeStoryOnly = false,
): Promise<PostRow[]> {
  // No CIRCLE_CTE here: a profile read is exactly where `workout_visibility`
  // decides who gets in, and a hardcoded circle join would have made 'public'
  // impossible. The feed still uses the circle — that one IS friends-by-nature.
  const rows = await db.query<PostRow>(
    `
		SELECT ${POST_SELECT},
			${URL_SAFE_CURSOR("p.created_at")} AS cursor,
			-- The run's story photo, so the profile grid + detail cards lead
			-- with the real picture (workout card second), matching the feed.
			-- Owner's decision: story expiry does NOT remove the photo from
			-- feed/profile surfaces — only deleting the story does.
			(
				SELECT p3.media_url FROM posts p3
				WHERE p.workout_id IS NOT NULL
					AND p3.workout_id = p.workout_id
					AND p3.user_id = p.user_id
					AND p3.post_id <> p.post_id
					AND p3.deleted_at IS NULL
					AND p3.share_to_story AND NOT p3.share_to_feed
				ORDER BY p3.created_at DESC
				LIMIT 1
			) AS story_photo_url
		FROM posts p
		JOIN users u ON u.user_id = p.user_id
		WHERE (p.user_id = $2
				OR (p.coauthor_user_id = $2 AND p.coauthor_status = 'accepted'))
			AND p.deleted_at IS NULL
			AND (
				p.share_to_feed
				OR (
					$5::boolean
					AND p.user_id = $2
					AND p.user_id = $1
					AND p.share_to_story AND NOT p.share_to_feed
					AND NOT EXISTS (
						SELECT 1 FROM posts pf
						WHERE p.workout_id IS NOT NULL
							AND pf.workout_id = p.workout_id
							AND pf.user_id = p.user_id
							AND pf.share_to_feed
							AND pf.deleted_at IS NULL
					)
				)
			)
			AND ${VIEWER_MAY_SEE_WORKOUT_CONTENT_SQL("$2", "$1")}
			-- Collab rows surface the PRIMARY author's content on the coauthor's
			-- profile. Reach mirrors the unified feed: a collab deliberately
			-- shares BOTH audiences, so the viewer needn't be the author's
			-- friend — but a private or blocked author still disappears.
			AND (p.user_id = $2 OR (
				${OWNER_NOT_PRIVATE_SQL("p.user_id")}
				AND NOT EXISTS (
					SELECT 1 FROM user_blocks b
					WHERE (b.blocker_id = $1 AND b.blocked_id = p.user_id)
						OR (b.blocker_id = p.user_id AND b.blocked_id = $1)
				)
			))
			AND ($3::timestamptz IS NULL OR p.created_at < $3::timestamptz)
		ORDER BY p.created_at DESC
		LIMIT $4
		`,
    [viewerId, authorId, before ?? null, limit, includeStoryOnly],
  );
  return rows;
}

/**
 * Posts a user is TAGGED in, for the Instagram-style profile "Tagged" tab:
 * feed posts by OTHER people that either carry them as an ACCEPTED collab
 * coauthor or @mention their username in the caption. Mention matching
 * mirrors mentionService.extractMentionUsernames (token charset
 * [A-Za-z0-9._-], trailing dots stripped, case-insensitive) in SQL so the
 * tab agrees with who mention pushes went to.
 *
 * Visibility mirrors getUserPosts' collab-row reach: the viewer needn't be
 * the author's friend (a tag deliberately shares the post with the tagged
 * user's audience), but a private or blocked author still disappears, and
 * the whole tab is gated on the viewer being allowed to see the tagged
 * user's content at all. Blocks between the TAGGED user and the author also
 * hide the row — a block ends the tag in both directions.
 */
export async function getUserTaggedPosts(
  viewerId: string,
  taggedUserId: string,
  limit: number,
  before?: string | null,
): Promise<PostRow[]> {
  const users = await db.query<{ username: string | null }>(
    `SELECT username FROM users WHERE user_id = $1`,
    [taggedUserId],
  );
  const username = users[0]?.username ?? null;
  // Caption-mention pattern, matching extractMentionUsernames: the token
  // after '@' is [A-Za-z0-9._-]+ with trailing dots stripped — so after the
  // escaped username only dots may follow before a non-token char or the end.
  const mentionPattern = username
    ? `@${username.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\.*([^a-zA-Z0-9._-]|$)`
    : null;
  const rows = await db.query<PostRow>(
    `
		SELECT ${POST_SELECT},
			${URL_SAFE_CURSOR("p.created_at")} AS cursor,
			-- Same story-photo lead as the profile grid, so tagged cards match.
			(
				SELECT p3.media_url FROM posts p3
				WHERE p.workout_id IS NOT NULL
					AND p3.workout_id = p.workout_id
					AND p3.user_id = p.user_id
					AND p3.post_id <> p.post_id
					AND p3.deleted_at IS NULL
					AND p3.share_to_story AND NOT p3.share_to_feed
				ORDER BY p3.created_at DESC
				LIMIT 1
			) AS story_photo_url
		FROM posts p
		JOIN users u ON u.user_id = p.user_id
		WHERE p.deleted_at IS NULL
			AND p.share_to_feed
			AND p.user_id <> $2
			AND (
				(p.coauthor_user_id = $2 AND p.coauthor_status = 'accepted')
				OR ($5::text IS NOT NULL AND p.caption IS NOT NULL AND p.caption ~* $5)
			)
			-- Profile gate: may the viewer see the tagged user's content at all?
			AND ${VIEWER_MAY_SEE_WORKOUT_CONTENT_SQL("$2", "$1")}
			-- Author gate (mirrors getUserPosts' collab reach): the viewer's own
			-- posts always show; others' need not-private + no blocks either way.
			AND (p.user_id = $1 OR (
				${OWNER_NOT_PRIVATE_SQL("p.user_id")}
				AND NOT EXISTS (
					SELECT 1 FROM user_blocks b
					WHERE (b.blocker_id = $1 AND b.blocked_id = p.user_id)
						OR (b.blocker_id = p.user_id AND b.blocked_id = $1)
				)
			))
			-- Blocks between the tagged user and the author end the tag.
			AND NOT EXISTS (
				SELECT 1 FROM user_blocks tb
				WHERE (tb.blocker_id = $2 AND tb.blocked_id = p.user_id)
					OR (tb.blocker_id = p.user_id AND tb.blocked_id = $2)
			)
			AND ($3::timestamptz IS NULL OR p.created_at < $3::timestamptz)
		ORDER BY p.created_at DESC
		LIMIT $4
		`,
    [viewerId, taggedUserId, before ?? null, limit, mentionPattern],
  );
  return rows;
}

/**
 * Best-effort push to the author's friends that they shared a new post/story.
 * One notification per deliberate createPost — a post going to the story AND
 * the feed together still produces a single push. Respects each friend's
 * `friend_posts_enabled` (default on), excludes blocks both ways, only
 * reaches friends whose build can open the feed/stories UI (same signal as
 * userHasFeedFeature), and is capped to avoid fan-out storms.
 *
 * Anti-spam via UPGRADE, not dismissal: when the deferred "got their mile
 * in" push is still pending (the 10-min merge window, send_after_at set —
 * audience-'ask' confirm cards have it NULL and are never touched), its
 * payload is upgraded in place to carry the photo (body + data.post_id) and
 * NO separate friend_post is sent. The original recipient pool — including
 * competition co-participants and friends on pre-feed builds — still gets
 * exactly one push on the original schedule. Only when nothing is pending
 * (posted later, mile push already sent) does the immediate friend_post
 * fan-out fire. Never throws into the caller.
 */
export async function notifyFriendsOfPost(input: {
  authorId: string;
  postId: string;
  caption: string | null;
  toFeed: boolean;
  toStory: boolean;
  localDate: string;
}): Promise<void> {
  const { authorId, postId, caption, toFeed, toStory, localDate } = input;
  try {
    const trimmedCaption = caption?.trim() ?? "";
    const storyOnly = toStory && !toFeed;
    const mergedBody =
      trimmedCaption.length > 0
        ? `📸 ${trimmedCaption.slice(0, 110)}`
        : storyOnly
          ? "and shared a story from it 📸"
          : "and shared a photo from it 📸";

    const upgraded = await db.query<{ id: string }>(
      `UPDATE pending_friend_notifications
			 SET payload = jsonb_set(
				 jsonb_set(payload, '{body}', to_jsonb($3::text)),
				 '{data,post_id}', to_jsonb($4::text)
			 )
			 WHERE user_id = $1 AND event_type = 'mile_completed'
				 AND status = 'pending' AND send_after_at IS NOT NULL
				 AND local_date = $2::date
			 RETURNING id`,
      [authorId, localDate, mergedBody, postId],
    );
    if (upgraded.length > 0) {
      // The scheduled mile push now carries the photo — one merged
      // notification per run, original pool, original timing.
      return;
    }

    // Rolling-window coalesce: don't buzz friends again if this author made
    // another deliberate post in the last few hours. A morning walk and an
    // evening run (>window apart) both notify; three quick posts in a session
    // don't triple-buzz. (The mile-merge above handles the just-finished
    // case; this caps the later-post path.) The post itself still lands in
    // the feed — only the push is suppressed.
    //
    // Probed against posts (not in_app_notifications): a prior deliberate
    // post in the window is the proxy for "already notified", and this hits
    // idx_posts_user_created (user_id, created_at) instead of full-scanning
    // the ever-growing inbox table on data->>'user_id'.
    const recent = await db.query<{ id: string }>(
      `SELECT 1 AS id FROM posts
			 WHERE user_id = $1
				 AND post_id <> $2
				 AND is_auto = false
				 AND deleted_at IS NULL
				 AND created_at > NOW() - INTERVAL '6 hours'
			 LIMIT 1`,
      [authorId, postId],
    );
    if (recent.length > 0) return;

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
					 AND (
						 EXISTS (SELECT 1 FROM posts fp WHERE fp.user_id = f.friend_id)
						 OR EXISTS (
							 SELECT 1 FROM users fu
							 WHERE fu.user_id = f.friend_id
								 AND fu.terms_accepted_at IS NOT NULL
						 )
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
    const title = storyOnly
      ? `${name} added to their story ✨`
      : `${name} posted 📸`;
    const body =
      trimmedCaption.length > 0
        ? trimmedCaption.slice(0, 120)
        : storyOnly
          ? "shared a new story"
          : "shared a new post";

    for (const r of recipients) {
      sendPush(r.uid, {
        title,
        body,
        type: "friend_post",
        // kind routes the tap client-side ("story" opens the story viewer,
        // "post" lands on the feed entry); post_id is additive deep-link data.
        data: {
          user_id: authorId,
          kind: storyOnly ? "story" : "post",
          post_id: postId,
        },
      }).catch((e: any) =>
        console.error("[notifyFriendsOfPost]", e?.message ?? e),
      );
    }
  } catch (e: any) {
    console.error("[notifyFriendsOfPost] failed:", e?.message ?? e);
  }
}

/**
 * The post's author IF the viewer may see the post: viewer is the author or
 * an accepted friend, post is live on the feed, and no block exists in either
 * direction. Null when not visible — callers map that to 404 so post
 * existence isn't leaked. Shared by comments + mentions.
 */
export async function visiblePostAuthor(
  viewerId: string,
  postId: string,
): Promise<string | null> {
  const rows = await db.query<{ user_id: string }>(
    `SELECT p.user_id FROM posts p
		 WHERE p.post_id = $2 AND p.deleted_at IS NULL AND p.share_to_feed
			 AND (p.user_id = $1 OR p.coauthor_user_id = $1
				 OR ${OWNER_NOT_PRIVATE_SQL("p.user_id")})
			 AND (p.user_id = $1
				 OR p.coauthor_user_id = $1
				 OR EXISTS (
					 SELECT 1 FROM friendships f
					 WHERE f.user_id = $1 AND f.status = 'accepted'
						 AND (f.friend_id = p.user_id
							 OR (p.coauthor_status = 'accepted' AND f.friend_id = p.coauthor_user_id))
				 ))
			 AND NOT EXISTS (
				 SELECT 1 FROM user_blocks b
				 WHERE (b.blocker_id = $1 AND b.blocked_id = p.user_id)
						OR (b.blocker_id = p.user_id AND b.blocked_id = $1)
						-- Accepted collabs are hidden from feeds when EITHER author is
						-- blocked; deny direct access (comments/mentions) the same way.
						OR (p.coauthor_status = 'accepted' AND (
							(b.blocker_id = $1 AND b.blocked_id = p.coauthor_user_id)
							OR (b.blocker_id = p.coauthor_user_id AND b.blocked_id = $1)
						))
			 )`,
    [viewerId, postId],
  );
  return rows[0]?.user_id ?? null;
}

/**
 * The post's accepted coauthor, if any (comment notifications + moderation).
 */
export async function acceptedCoauthor(postId: string): Promise<string | null> {
  const rows = await db.query<{ coauthor_user_id: string }>(
    `SELECT coauthor_user_id FROM posts
		 WHERE post_id = $1 AND coauthor_status = 'accepted' AND deleted_at IS NULL`,
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
					 AND coauthor_status = 'pending' AND deleted_at IS NULL
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

/** Push the collab invite to the invited coauthor. Never throws. */
export async function notifyCoauthorInvite(
  authorId: string,
  coauthorId: string,
  postId: string,
): Promise<void> {
  try {
    if (!(await shouldSendNotification(coauthorId, authorId, "hype"))) return;
    const rows = await db.query<{ username: string | null }>(
      `SELECT username FROM users WHERE user_id = $1`,
      [authorId],
    );
    const name = rows[0]?.username ?? "A friend";
    await sendPush(coauthorId, {
      title: `${name} added you to their post 🤝`,
      body: "Accept to share this mile on your profile too",
      type: "coauthor_invite",
      data: { user_id: authorId, post_id: postId },
    });
  } catch (e: any) {
    console.error("[notifyCoauthorInvite] failed:", e?.message ?? e);
  }
}

/** Tell the author their invited coauthor accepted. Never throws. */
export async function notifyCoauthorAccepted(
  coauthorId: string,
  authorId: string,
  postId: string,
): Promise<void> {
  try {
    if (!(await shouldSendNotification(authorId, coauthorId, "hype"))) return;
    const rows = await db.query<{ username: string | null }>(
      `SELECT username FROM users WHERE user_id = $1`,
      [coauthorId],
    );
    const name = rows[0]?.username ?? "Your friend";
    await sendPush(authorId, {
      title: `${name} joined your post 🤝`,
      body: "You're sharing this mile together",
      type: "coauthor_accepted",
      data: { user_id: coauthorId, post_id: postId },
    });
  } catch (e: any) {
    console.error("[notifyCoauthorAccepted] failed:", e?.message ?? e);
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
  updates: { caption?: string | null; addToFeed?: boolean },
): Promise<UpdatePostResult> {
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
