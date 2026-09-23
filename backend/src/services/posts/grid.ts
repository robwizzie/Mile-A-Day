// Profile grid: grid controls (sort/filter/pins), tagged posts and own-post
// memories.

import { PostgresService } from "../DbService.js";
import { VIEWER_MAY_SEE_WORKOUT_CONTENT_SQL, OWNER_NOT_PRIVATE_SQL } from "../visibilityService.js";
import { type PostRow } from "./postTypes.js";
import {
  POST_SELECT,
  COLLAB_ACTIVE,
  MULTI_COLLAB_ACTIVE,
  coauthorOnProfileSql,
  coauthorOnProfileMultiSql,
  URL_SAFE_CURSOR,
} from "./postSql.js";

const db = PostgresService.getInstance();

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
/**
 * How the profile grid may be ordered. Every value is keyset-paginated on
 * `created_at`, which is the only column the grid has an index on and the only
 * one a cursor can express without changing the cursor's shape — so adding a
 * sort here is free, and adding one that isn't a `created_at` walk is not.
 */
export type UserPostsSort = "newest" | "oldest";

/**
 * What the grid is filtered to. `all` is the shipped behaviour and the default
 * for any client that doesn't ask, which is every build that predates this.
 *
 *  - `photos`   — deliberate posts. A picture someone chose to take.
 *  - `auto`     — the generated route/stats cards published when the photo
 *                 prompt was skipped. Together with `photos` this partitions
 *                 the grid exactly, which is why it's `is_auto` and not a
 *                 has-a-route test: a photo post can carry a route too.
 *  - `collabs`  — posts with at least one live credited coauthor, in either
 *                 representation (the legacy scalar or post_coauthors).
 */
export type UserPostsFilter = "all" | "photos" | "auto" | "collabs";

export interface UserPostsQuery {
  sort?: UserPostsSort;
  filter?: UserPostsFilter;
  /**
   * Return pinned posts through `getUserPinnedPosts` INSTEAD of inline in the
   * paged body.
   *
   * Off by default and that is load-bearing: a shipped client knows nothing
   * about pins, so excluding them from `items` would make a pinned post vanish
   * from its grid entirely. Old clients keep seeing every post in date order
   * (with an additive `pinned_at` they ignore); new clients ask for the split
   * and render the pins as their own row on top.
   */
  splitPins?: boolean;
}

/** Instagram's number, and for the same reason: three fit one grid row. */
export const POST_PIN_LIMIT = 3;

/**
 * SQL: the filter clause for `filter`, or TRUE. `p` is the posts alias.
 *
 * Kept as a lookup rather than interpolation so the value can never reach SQL
 * — the caller's string is validated into the union by `parseUserPostsFilter`,
 * and anything unrecognised falls back to `all`.
 */
const USER_POSTS_FILTER_SQL: Record<UserPostsFilter, string> = {
  all: "TRUE",
  photos: "NOT p.is_auto",
  auto: "p.is_auto",
  collabs: `(${COLLAB_ACTIVE} OR EXISTS (
			SELECT 1 FROM post_coauthors pca
			WHERE pca.post_id = p.post_id AND ${MULTI_COLLAB_ACTIVE}
		))`,
};

export function parseUserPostsSort(raw: unknown): UserPostsSort {
  return raw === "oldest" ? "oldest" : "newest";
}

export function parseUserPostsFilter(raw: unknown): UserPostsFilter {
  return raw === "photos" || raw === "auto" || raw === "collabs" ? raw : "all";
}

const AUTO_POST_HAS_PROFILE_PHOTO = `EXISTS (
						SELECT 1 FROM posts psp
						WHERE p.workout_id IS NOT NULL
							AND psp.workout_id = p.workout_id
							AND psp.user_id = p.user_id
							AND psp.post_id <> p.post_id
							AND psp.deleted_at IS NULL
							AND psp.share_to_story AND NOT psp.share_to_feed
					)`;

/**
 * Everything a post must satisfy to appear on `$2`'s profile grid as read by
 * viewer `$1`, minus the cursor bound and the ordering.
 *
 * Extracted because the pinned row and the paged body are the same grid asked
 * two different ways, and a visibility rule that lived in only one of them
 * would be a leak in the other — the pins are the surface someone is most
 * likely to add a shortcut to later.
 *
 * Parameterised by placeholder rather than fixed to $1/$2/$5: the two callers
 * bind different numbers of values, and Postgres rejects a statement that
 * skips a $n (it can't infer the type of a parameter nothing references).
 */
const userGridWhere = (
  viewer: string,
  author: string,
  storyOnly: string,
) => `(p.user_id = ${author}
				-- Tags are the Tagged tab's job, not the grid's: a collab only
				-- joins the coauthor's Posts grid while they haven't opted out
				-- (per-post override, else their tagged_posts_on_profile).
				-- Hiding it here removes it from NOWHERE else — it stays in
				-- their Tagged tab, on the author's grid, and in both circles'
				-- feeds.
				OR (p.coauthor_user_id = ${author} AND ${COLLAB_ACTIVE}
					AND ${coauthorOnProfileSql("p", author)})
				-- ...and the same for a CREW member. The scalar beside this one
				-- holds ONE person, so on a buddy walk of five it answered for
				-- the first participant and silently excluded the other four:
				-- their "Add to grid" wrote no row and this query never looked
				-- at them, so the walk they took could not be put on their own
				-- profile by any means.
				OR EXISTS (
					SELECT 1 FROM post_coauthors pca
					WHERE pca.post_id = p.post_id AND pca.user_id = ${author}
						AND ${MULTI_COLLAB_ACTIVE}
						AND ${coauthorOnProfileMultiSql(author)}
				))
			AND p.deleted_at IS NULL
			AND (
				p.share_to_feed
				OR (
					${storyOnly}::boolean
					AND p.user_id = ${author}
					AND p.user_id = ${viewer}
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
			-- Photo-first curation: "don't put photo-less route cards on my
			-- grid". Two things this must NOT do, both of which it did.
			--
			-- It read ns.user_id = p.user_id — the AUTHOR's setting — which is
			-- right for your own posts (you are the author) and wrong for every
			-- collab, where it handed a stranger's curation preference authority
			-- over YOUR grid. A buddy walk is usually posted by whoever finished
			-- first, so whether the walk could appear on your profile depended on
			-- a switch in someone else's settings screen. It is the GRID OWNER's
			-- question, so it reads the grid owner's row.
			--
			-- And it sat OUTSIDE the per-post override above, so a blanket
			-- preference silently overruled a deliberate "Add to grid" on this
			-- one post: the user tapped it, the write succeeded, and nothing
			-- appeared. An explicit choice about a specific post is the most
			-- specific thing anyone has said and must win.
			AND (
				NOT p.is_auto
				OR ${AUTO_POST_HAS_PROFILE_PHOTO}
				-- Each arm names the grid owner, so this can only ever exempt a
				-- post for the person who explicitly asked for it. Left
				-- unqualified, the scalar arm read one coauthor's "keep this"
				-- as an exemption on the AUTHOR's grid too — handing a curation
				-- choice to the wrong person, which is the bug in mirror image.
				OR (p.coauthor_user_id = ${author} AND p.coauthor_on_profile IS TRUE)
				OR EXISTS (
					SELECT 1 FROM post_coauthors pca
					WHERE pca.post_id = p.post_id AND pca.user_id = ${author}
						AND pca.on_profile IS TRUE
				)
				OR COALESCE((
					SELECT ns.auto_posts_on_profile FROM notification_settings ns
					WHERE ns.user_id = ${author}
				), TRUE)
			)
			AND ${VIEWER_MAY_SEE_WORKOUT_CONTENT_SQL(author, viewer)}
			-- Collab rows surface the PRIMARY author's content on the coauthor's
			-- profile. Reach mirrors the unified feed: a collab deliberately
			-- shares BOTH audiences, so the viewer needn't be the author's
			-- friend — but a private or blocked author still disappears. The
			-- privacy arm alone exempts the coauthor (they co-own the post and
			-- must keep seeing it); a block still wins, in either direction.
			AND (p.user_id = ${author} OR p.coauthor_user_id = ${viewer}
				OR ${OWNER_NOT_PRIVATE_SQL("p.user_id")})
			AND (p.user_id = ${author} OR NOT EXISTS (
				SELECT 1 FROM user_blocks b
				WHERE (b.blocker_id = ${viewer} AND b.blocked_id = p.user_id)
					OR (b.blocker_id = p.user_id AND b.blocked_id = ${viewer})
			))`;

/**
 * The run's active story photo, so profile surfaces lead with the real picture
 * (workout card second), matching the feed. Owner's decision: story EXPIRY does
 * not remove the photo from feed/profile surfaces — only deleting the story
 * does.
 */
const GRID_STORY_PHOTO_SQL = `(
				SELECT p3.media_url FROM posts p3
				WHERE p.workout_id IS NOT NULL
					AND p3.workout_id = p.workout_id
					AND p3.user_id = p.user_id
					AND p3.post_id <> p.post_id
					AND p3.deleted_at IS NULL
					AND p3.share_to_story AND NOT p3.share_to_feed
				ORDER BY p3.created_at DESC
				LIMIT 1
			)`;

export async function getUserPosts(
  viewerId: string,
  authorId: string,
  limit: number,
  before?: string | null,
  includeStoryOnly = false,
  query: UserPostsQuery = {},
): Promise<PostRow[]> {
  const sort = query.sort ?? "newest";
  const filter = query.filter ?? "all";
  // "Oldest first" walks the same index the other way, so the cursor bound has
  // to invert with it — the client keeps sending back the last row it saw and
  // never has to know which direction that means.
  const cursorBound =
    sort === "oldest"
      ? `($3::timestamptz IS NULL OR p.created_at > $3::timestamptz)`
      : `($3::timestamptz IS NULL OR p.created_at < $3::timestamptz)`;
  const orderBy = sort === "oldest" ? "p.created_at ASC" : "p.created_at DESC";

  // No CIRCLE_CTE here: a profile read is exactly where `workout_visibility`
  // decides who gets in, and a hardcoded circle join would have made 'public'
  // impossible. The feed still uses the circle — that one IS friends-by-nature.
  const rows = await db.query<PostRow>(
    `
		SELECT ${POST_SELECT},
			${URL_SAFE_CURSOR("p.created_at")} AS cursor,
			${GRID_STORY_PHOTO_SQL} AS story_photo_url
		FROM posts p
		JOIN users u ON u.user_id = p.user_id
		WHERE ${userGridWhere("$1", "$2", "$5")}
			AND ${USER_POSTS_FILTER_SQL[filter]}
			-- Pins ride in the paged body unless the caller asked for them
			-- separately; $6 is that request, never a filter of its own.
			AND (NOT $6::boolean OR p.pinned_at IS NULL)
			AND ${cursorBound}
		ORDER BY ${orderBy}
		LIMIT $4
		`,
    [
      viewerId,
      authorId,
      before ?? null,
      limit,
      includeStoryOnly,
      query.splitPins === true,
    ],
  );
  return rows;
}

/**
 * The author's pinned posts, newest pin first — the row that sits above the
 * grid.
 *
 * Its own query rather than a branch in the paged one because pins are not a
 * page: there are at most POST_PIN_LIMIT of them, they ignore the sort and the
 * filter (a pin is the author saying "this one, first", and a filter that hid
 * it would make the pin look broken), and they must not consume the cursor.
 * Same visibility fragment as the body, so nothing can be pinned into view
 * that couldn't be scrolled to.
 */
export async function getUserPinnedPosts(
  viewerId: string,
  authorId: string,
): Promise<PostRow[]> {
  return db.query<PostRow>(
    `
		SELECT ${POST_SELECT},
			${URL_SAFE_CURSOR("p.created_at")} AS cursor,
			${GRID_STORY_PHOTO_SQL} AS story_photo_url
		FROM posts p
		JOIN users u ON u.user_id = p.user_id
		WHERE ${userGridWhere("$1", "$2", "$3")}
			AND p.pinned_at IS NOT NULL
			-- A pin only ever belongs to the person whose grid this is: pinning
			-- is the AUTHOR's curation of their own profile, so a collab pinned
			-- by its author must not jump to the top of the coauthor's grid too.
			AND p.user_id = $2
		ORDER BY p.pinned_at DESC
		LIMIT $4
		`,
    [viewerId, authorId, false, POST_PIN_LIMIT],
  );
}

/**
 * Pin / unpin one of your OWN posts to the top of your grid.
 *
 * Returns "limit" rather than silently dropping the oldest pin: three is a
 * small enough number that a user who hits it meant to choose, and an
 * unpin-something-else prompt is a better answer than a pin that quietly
 * evicted one they still wanted.
 *
 * Deliberately author-only and not offered to a tagged coauthor — a pin is
 * curation of a grid, and the collab is on the coauthor's grid at the author's
 * invitation, which `coauthor_on_profile` already lets them refuse wholesale.
 */
export async function setPostPinned(
  authorId: string,
  postId: string,
  pinned: boolean,
): Promise<"ok" | "not_found" | "limit"> {
  if (!pinned) {
    const cleared = await db.query<{ post_id: string }>(
      `UPDATE posts SET pinned_at = NULL
			 WHERE post_id = $1 AND user_id = $2 AND deleted_at IS NULL
			 RETURNING post_id`,
      [postId, authorId],
    );
    return cleared.length > 0 ? "ok" : "not_found";
  }

  // One statement so two taps can't race past the cap: the count is taken
  // inside the same UPDATE that would exceed it, and a post that is ALREADY
  // pinned re-stamps freely (it consumes no new slot, it just moves to front).
  const rows = await db.query<{ post_id: string }>(
    `UPDATE posts SET pinned_at = NOW()
		 WHERE post_id = $1 AND user_id = $2 AND deleted_at IS NULL
			 AND (
				pinned_at IS NOT NULL
				OR (SELECT COUNT(*) FROM posts pp
					WHERE pp.user_id = $2 AND pp.pinned_at IS NOT NULL
						AND pp.deleted_at IS NULL) < $3
			 )
		 RETURNING post_id`,
    [postId, authorId, POST_PIN_LIMIT],
  );
  if (rows.length > 0) return "ok";

  // Nothing updated: either the post isn't theirs, or the cap is full. Tell
  // those apart — "you already have 3 pinned" is actionable, "not found" is not.
  const exists = await db.query<{ post_id: string }>(
    `SELECT post_id FROM posts
		 WHERE post_id = $1 AND user_id = $2 AND deleted_at IS NULL`,
    [postId, authorId],
  );
  return exists.length > 0 ? "limit" : "not_found";
}

/**
 * Posts a user is TAGGED in, for the Instagram-style profile "Tagged" tab:
 * feed posts by OTHER people that either carry them as an ACCEPTED collab
 * coauthor or @mention their username in the caption. A pending collab invite
 * is NOT a tag yet — it stays out of the tab entirely until accepted, for
 * every viewer including the author (COAUTHOR_VISIBLE gates the coauthor
 * LABEL on a displayed post, never tab ENTRY — don't reuse it here). Mention
 * matching
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
				(p.coauthor_user_id = $2 AND ${COLLAB_ACTIVE})
				-- A CREW member is tagged in exactly the sense this tab means.
				-- Only the legacy scalar was asked, so on a buddy walk of five
				-- the walk appeared in one participant's Tagged tab and in
				-- nobody else's — the other four were credited on the card,
				-- named in its header, and could not find it anywhere on their
				-- own profile.
				OR EXISTS (
					SELECT 1 FROM post_coauthors pca
					WHERE pca.post_id = p.post_id AND pca.user_id = $2
						AND ${MULTI_COLLAB_ACTIVE}
				)
				OR ($5::text IS NOT NULL AND p.caption IS NOT NULL AND p.caption ~* $5)
			)
			-- Profile gate: may the viewer see the tagged user's content at all?
			AND ${VIEWER_MAY_SEE_WORKOUT_CONTENT_SQL("$2", "$1")}
			-- Author gate (mirrors getUserPosts' collab reach): the viewer's own
			-- posts always show; others' need not-private + no blocks either way.
			-- Being an author of the collab exempts the PRIVACY arm only — a
			-- block still hides the row, in either direction.
			AND (p.user_id = $1 OR p.coauthor_user_id = $1
				OR ${OWNER_NOT_PRIVATE_SQL("p.user_id")})
			AND (p.user_id = $1 OR NOT EXISTS (
				SELECT 1 FROM user_blocks b
				WHERE (b.blocker_id = $1 AND b.blocked_id = p.user_id)
					OR (b.blocker_id = p.user_id AND b.blocked_id = $1)
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
