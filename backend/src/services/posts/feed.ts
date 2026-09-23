// The feed: legacy post feed, the unified post+workout feed, one post as a feed
// entry, and the public link preview.

import { PostgresService } from "../DbService.js";
import { OWNER_NOT_PRIVATE_SQL } from "../visibilityService.js";
import {
  postHypedByViewerMatchSql,
  runHypedByViewerMatchSql,
  postHypeMatchSql,
  runHypeMatchSql,
} from "../hypeService.js";
import {
  type PostRow,
  type PostStatsSnapshot,
  type PostCompetitionRef,
  type CommentPreview,
} from "./postTypes.js";
import {
  CIRCLE_CTE,
  POST_SELECT,
  URL_SAFE_CURSOR,
  POST_FEED_GATES,
  COLLAB_REACH_SQL,
  VIEWER_WAS_ON_THIS_WALK,
  CURSOR_BEFORE,
  displayMovingSecondsSql,
  ROUTE_STARTED_AT_EXPR,
  competitionsJson,
  postCommentMatchSql,
  commentPreviewSql,
  COAUTHOR_COLUMNS,
  MULTI_COLLAB_ACTIVE,
  collabActiveSql,
} from "./postSql.js";
import { POST_WINDOW_MS } from "./postWindow.js";
import { visiblePostAuthor } from "./postAccess.js";

const db = PostgresService.getInstance();

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
		WHERE ${POST_FEED_GATES}
			-- Accepted collab posts reach BOTH authors' circles (semi-join, not a
			-- JOIN, so a post whose two authors share the viewer isn't doubled).
			-- A buddy walk this viewer was ON is theirs to see whether or not
			-- anyone on it is in their circle — same rule as the unified feed's
			-- third arm, kept here so the two feeds can't answer differently.
			AND (EXISTS (
				SELECT 1 FROM circle c
				WHERE c.uid = p.user_id
					OR (c.uid = p.coauthor_user_id AND ${COLLAB_REACH_SQL})
			) OR ${VIEWER_WAS_ON_THIS_WALK})
			AND ${CURSOR_BEFORE("p.created_at")}
		ORDER BY p.created_at DESC
		LIMIT $3
		`,
    [viewerId, before ?? null, limit],
  );
  return rows;
}

/** One leg of a daily mile that was completed across several workouts. */
export interface FeedSegment {
  workout_id: string;
  workout_type: string;
  distance: number;
  duration: number;
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
  // workout columns (also populated for posts via their linked workout).
  // On a 'daily_mile' anchor these are the DAY's rollup across every workout up
  // to and including it, not that one workout's figures.
  workout_type: string | null;
  // Entry/linked workout's feed_role — display framing only ('daily_mile'
  // = goal-completing entry, 'extra' = post-goal bonus). Never summed.
  feed_role: string | null;
  // Additive: HealthKit's indoor flag — null on older rows/clients means
  // "unknown", never "outdoor".
  is_indoor: boolean | null;
  distance: number | null;
  total_duration: number | null;
  // Moving-time display-pace divisor (rollup-aware); null on rows without it.
  moving_seconds: number | null;
  calories: number | null;
  steps: number | null;
  // How many real workouts the daily mile was stitched together from. 1 (or
  // null, on an 'extra' entry) is an ordinary single-workout day; > 1 means the
  // user got there in several goes and `segments` breaks it down. Additive —
  // shipped clients ignore both and still show the correct combined total.
  segment_count: number | null;
  segments: FeedSegment[] | null;
  // Simplified GPS trace for the entry's workout, when synced (and, for
  // posts, when the author chose to include it).
  route: number[][] | null;
  // Additive, beside `route`: per-point seconds since the first fix and that
  // fix's epoch seconds, when the uploading client sent them.
  route_times: number[] | null;
  route_started_at: number | null;
  // Additive: the owner's competitions on the entry's day (both kinds).
  competitions: PostCompetitionRef[] | null;
  // post-only, additive: the competition the poster stickered onto the photo.
  // Null on workout entries and on any post without one. The tappable chip is
  // drawn by matching this against `competitions` above — its `viewer_in` is
  // the membership gate, so no extra query decides who may open it.
  competition_id?: string | null;
  // Additive: the entry's per-mile splits, so indoor cards can draw a pace
  // wave. Pace/time only — no location — hence no share_route_maps gate (the
  // same figures are already public via stats_snapshot). Null when absent, on
  // stitched rollups (the anchor's splits describe only the LAST leg of the
  // combined mile), and on auto posts (their media already IS the baked card).
  splits:
    | {
        split_number: number;
        split_duration: number;
        split_distance: number | null;
        split_pace: number | null;
      }[]
    | null;
  // Additive: may the viewer launch this entry's flyover (owner always;
  // friends when the author's flyover_visibility permits).
  flyover_allowed: boolean | null;
  // Additive, OWNER-ONLY: the entry's workout was recorded in Stealth Mode
  // (its route withheld forever). Always false for other viewers — to them it
  // must read exactly like share_route_maps=off.
  stealth: boolean;
  // shared
  is_self: boolean;
  is_hyped: boolean;
  hype_count: number;
  // The conversation's size. Raw workout cards can be commented on too, and
  // on a buddy walk this counts every leg (`postCommentMatchSql`) — one walk
  // is one conversation.
  comment_count: number;
  // The last two comments, oldest-first (see PostRow.comment_preview).
  comment_preview?: CommentPreview[] | null;
  // Collab post fields (post entries only, same visibility rule as PostRow).
  coauthor_user_id: string | null;
  coauthor_status: "pending" | "accepted" | null;
  coauthor_username: string | null;
  coauthor_first_name: string | null;
  coauthor_last_name: string | null;
  coauthor_profile_image_url: string | null;
  // Resolved "is this collab on MY profile grid?", populated only when the
  // viewer is the coauthor (null otherwise, and on every workout entry).
  coauthor_on_profile?: boolean | null;
  // Microsecond-precise sort_ts (Postgres text form) for keyset pagination.
  cursor?: string;
}

/**
 * Everything a feed ENTRY carries, projected onto a `page` CTE of
 * (kind, id, sort_ts, owner_id, workout_id) rows. Shared verbatim by the
 * unified feed and the single-post read so a post opened directly renders
 * from byte-identical data to the same post scrolled to in the feed — the
 * rollup restatement, hype/comment counts, FRESH chip and route gating all
 * included. `$1` must be the viewer id; the projection uses no other param.
 */
/**
 * The unified feed's route column, per arm: a post's under its own
 * `include_route` + the author's consent; a raw workout's only on a
 * single-segment day (the anchor's trace is only the LAST leg of a stitched
 * mile, and drawing it under the combined stat line labels a 0.40-mile loop as
 * the whole mile — clients fall back to the branded stats face). The owner
 * always sees their own. Parameterised by the selected expression so the
 * timing columns are gated IDENTICALLY to the polyline they describe.
 */
const unifiedFeedRouteSql = (expr: string) => `CASE
				WHEN page.kind = 'post' THEN (
					SELECT ${expr} FROM workout_routes wr
					WHERE p.include_route
						AND (COALESCE(nsp.share_route_maps, true) OR page.owner_id = $1)
						AND wr.workout_id = p.workout_id
				)
				ELSE (
					SELECT ${expr} FROM workout_routes wr
					WHERE COALESCE(roll.segment_count, 1) <= 1
						AND (COALESCE(nsp.share_route_maps, true) OR page.owner_id = $1)
						AND wr.workout_id = wt.workout_id
				)
			END`;

const FEED_ENTRY_PROJECTION = `
		SELECT
			page.kind,
			page.id,
			page.sort_ts,
			page.owner_id AS user_id,
			u.username, u.first_name, u.last_name, u.profile_image_url,
			p.media_url, p.dual_media_url, p.dual_inset_corner, p.caption,
			-- A photo post on the day's anchor speaks for the whole mile, so its
			-- baked snapshot is restated in the rollup's terms. Without this a
			-- 3 x 0.33 day whose anchor carries a post would read "0.33 mi" — the
			-- other two segments are folded away and the day would appear to
			-- SHRINK versus before this feature. Only when the mile actually spans
			-- several workouts; a normal one-run day is untouched, and posts on a
			-- non-anchor workout keep their own exact stats (the invariant in
			-- .claude/rules/ios.md).
			CASE
				WHEN page.kind = 'post' AND wt.feed_role = 'daily_mile'
					AND roll.segment_count > 1 AND p.stats_snapshot IS NOT NULL
				THEN p.stats_snapshot || jsonb_build_object(
					'distance', roll.distance,
					'duration', roll.total_duration,
					-- Same moving-time display pace as POST_COLUMNS' restating —
					-- these two blocks must stay in lockstep (see that comment).
					'pace', CASE WHEN roll.distance > 0
						THEN roll.moving_duration / roll.distance END
				)
				ELSE p.stats_snapshot
			END AS stats_snapshot,
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
			-- The author's route-slide choice, so the card's ⋯ menu can offer to
			-- withdraw or restore it without a second round trip. Additive.
			p.include_route,
			-- The stickered competition. NULL on workout entries and on every
			-- post that didn't add one. Paired with the competitions array this
			-- arm already carries, whose viewer_in decides whether this viewer
			-- gets a tappable chip -- so the feed's hottest query gains a bare
			-- column and no new subquery.
			p.competition_id,
			page.workout_id,
			-- Populated for posts (via their linked workout) and workouts alike.
			wt.workout_type,
			-- Additive: HealthKit's indoor flag, for the card's indoor/outdoor
			-- chip. NULL = unknown (older rows) — clients make no claim then;
			-- routeless alone must never be read as "indoor" (privacy also
			-- blanks routes).
			wt.is_indoor,
			-- Additive, OWNER-ONLY: recorded in Stealth Mode. A stealth workout has
			-- no workout_routes row (enforced at write), so the route arms below
			-- are clean by construction; this flag only lets the OWNER's own card
			-- say why there's no map. Friends always get false.
			(page.owner_id = $1 AND COALESCE(wt.stealth, false)) AS stealth,
			-- Additive, DISPLAY-ONLY: lets clients frame the entry against the
			-- day's goal ('daily_mile' = the goal-completing entry, 'extra' =
			-- post-goal bonus miles shown as "+0.14 mi extra" instead of a
			-- bare number that reads like the whole day). Never used in sums.
			wt.feed_role,
			-- On an anchor entry these carry the DAY's rollup, not the single
			-- workout's — which is also what makes already-shipped iOS builds
			-- correct: they render whatever numbers arrive, so a stitched-together
			-- mile reads 1.06 mi on an old client with no update. COALESCE because
			-- the lateral only fires for 'daily_mile' rows; 'extra' rows keep their
			-- own figures.
			CASE WHEN page.kind = 'workout'
				THEN COALESCE(roll.distance, wt.distance)::double precision END AS distance,
			CASE WHEN page.kind = 'workout'
				THEN COALESCE(roll.total_duration, wt.total_duration)::double precision END AS total_duration,
			-- Additive: moving-time display-pace divisor for workout entries
			-- (rollup-aware on anchors). Null on old rows/Watch syncs — clients
			-- fall back to total_duration.
			CASE WHEN page.kind = 'workout'
				THEN COALESCE(roll.moving_duration, ${displayMovingSecondsSql("wt")})::double precision END AS moving_seconds,
			CASE WHEN page.kind = 'workout'
				THEN COALESCE(roll.calories, wt.calories)::double precision END AS calories,
			CASE WHEN page.kind = 'workout'
				THEN COALESCE(roll.steps, wt.steps) END AS steps,
			-- Additive, so older clients simply ignore them. segment_count = 1 is
			-- an ordinary single-workout day and clients render it exactly as
			-- before. Explicitly NULL on non-anchor entries: the lateral still
			-- produces a row for them and COUNT(*) over its empty result is 0, not
			-- NULL, which would read as "a mile made of no workouts".
			CASE WHEN wt.feed_role = 'daily_mile' THEN roll.segment_count END AS segment_count,
			roll.segments,
			-- Auto posts' media already IS the rendered route card, so shipping
			-- the polyline too would only duplicate pixels and bloat the page.
			-- Gated on the author's global "Share route maps" consent setting;
			-- posts additionally honor the per-post include_route choice. Raw
			-- workout routes respect the same setting (the owner always sees
			-- their own).
			${unifiedFeedRouteSql("wr.route")} AS route,
			-- The replay clock beside the route, under the same gates.
			${unifiedFeedRouteSql("wr.times")} AS route_times,
			${unifiedFeedRouteSql(ROUTE_STARTED_AT_EXPR)} AS route_started_at,
			-- The owner's competitions on the entry's day, both kinds.
			${competitionsJson("page.owner_id", "COALESCE(p.local_date, wt.local_date)", "p.competition_id")} AS competitions,
			-- Additive: per-mile splits for the entry's workout, so indoor cards
			-- can draw a pace wave. Same arm structure as \`route\` above, but NO
			-- share_route_maps gate — splits are pace/time, not location, and the
			-- same figures are already public via stats_snapshot. Withheld on
			-- stitched rollups for BOTH kinds (post stats are restated to the
			-- day's rollup too, and the anchor's splits describe only the LAST
			-- leg of the combined mile) and on auto posts (their media already
			-- IS the baked card). The withholds live in the CASE conditions,
			-- not inside the subqueries, so Postgres skips the idx_splits_workout
			-- probe entirely for rows that would return NULL anyway — auto posts
			-- are the feed's most common card. Inner LIMIT caps a pathological
			-- workout.
			CASE
				WHEN page.kind = 'post' AND NOT p.is_auto
					AND COALESCE(roll.segment_count, 1) <= 1 THEN (
					SELECT jsonb_agg(jsonb_build_object(
						'split_number', s.split_number,
						'split_duration', s.split_duration,
						'split_distance', s.split_distance,
						'split_pace', s.split_pace
					) ORDER BY s.split_number)
					FROM (
						SELECT ws.* FROM workout_splits ws
						WHERE ws.workout_id = p.workout_id
						ORDER BY ws.split_number
						LIMIT 30
					) s
				)
				WHEN page.kind <> 'post'
					AND COALESCE(roll.segment_count, 1) <= 1 THEN (
					SELECT jsonb_agg(jsonb_build_object(
						'split_number', s.split_number,
						'split_duration', s.split_duration,
						'split_distance', s.split_distance,
						'split_pace', s.split_pace
					) ORDER BY s.split_number)
					FROM (
						SELECT ws.* FROM workout_splits ws
						WHERE ws.workout_id = wt.workout_id
						ORDER BY ws.split_number
						LIMIT 30
					) s
				)
			END AS splits,
			-- Additive: may the VIEWER launch the cinematic flyover of this
			-- entry's route? Owner always; friends when the author's
			-- flyover_visibility allows (default 'friends'). Courtesy gate —
			-- the coords themselves are still governed by share_route_maps
			-- above; this only decides whether the guided tour is offered.
			(page.owner_id = $1
				OR COALESCE(nsp.flyover_visibility, 'friends') = 'friends')
				AS flyover_allowed,
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
			CASE
				WHEN page.kind = 'post' THEN (
					SELECT COUNT(*)::int FROM post_comments pc
					WHERE pc.deleted_at IS NULL
						AND ${postCommentMatchSql("pc", "p", "page.workout_id")}
				)
				ELSE (
					SELECT COUNT(*)::int FROM post_comments pc
					WHERE pc.workout_id = wt.workout_id AND pc.deleted_at IS NULL
				)
			END AS comment_count,
			CASE
				WHEN page.kind = 'post'
					THEN ${commentPreviewSql(postCommentMatchSql("cp", "p", "page.workout_id"))}
				ELSE ${commentPreviewSql("cp.workout_id = wt.workout_id")}
			END AS comment_preview,
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
		-- On page.post_uuid, NOT on p.post_id::text = page.id. The cast made the
		-- join condition non-indexable, so Postgres materialised the whole posts
		-- table and rescanned it for each of the page's rows; page.post_uuid is
		-- the uuid the candidate arms already had in hand, so this is a primary
		-- key probe. (post_uuid IS NOT NULL is exactly page.kind = 'post'.)
		LEFT JOIN posts p ON p.post_id = page.post_uuid
		LEFT JOIN workouts wt ON wt.workout_id = page.workout_id
		LEFT JOIN notification_settings nsp ON nsp.user_id = page.owner_id
		-- The day's rollup, for entries anchored on a 'daily_mile' workout: the
		-- combined mile that the pre-mile segments add up to, plus the segment
		-- breakdown itself. Page-bounded (<= $3 rows), one probe each on
		-- idx_workouts_user_local_date — the same shape as every other heavy
		-- column here, and the reason this isn't computed inside candidates.
		LEFT JOIN LATERAL (
			SELECT
				-- Only real workouts are segments; sub-floor junk is summed but
				-- never listed, so a 3-second phantom can't appear as a leg of
				-- someone's mile.
				COUNT(*) FILTER (WHERE m.feed_role <> 'hidden')::int AS segment_count,
				SUM(m.distance)::double precision AS distance,
				SUM(m.total_duration)::double precision AS total_duration,
				-- Per-row fallback to elapsed: a day mixing in-app legs (which
				-- carry moving time) with Watch legs (which don't) still sums.
				SUM(COALESCE(${displayMovingSecondsSql("m")}, m.total_duration))::double precision AS moving_duration,
				SUM(m.calories)::double precision AS calories,
				SUM(m.steps)::int AS steps,
				jsonb_agg(
					jsonb_build_object(
						'workout_id', m.workout_id,
						'workout_type', m.workout_type,
						'distance', m.distance,
						'duration', m.total_duration
					) ORDER BY m.device_end_date, m.workout_id
				) FILTER (WHERE m.feed_role <> 'hidden') AS segments
			FROM workouts m
			WHERE wt.feed_role = 'daily_mile'
				AND m.user_id = wt.user_id
				AND m.local_date = wt.local_date
				AND m.deleted_at IS NULL AND m.exclusion_reason IS NULL
				-- Everything up to and including the anchor. Junk BEFORE the anchor
				-- is counted so this card's distance equals what the profile,
				-- leaderboard and streak all report for that stretch of the day;
				-- junk after it belongs to the 'extra' workouts instead.
				AND (
					m.feed_role IN ('rolled_up', 'daily_mile')
					OR (m.feed_role = 'hidden' AND m.device_end_date <= wt.device_end_date)
				)
		) roll ON TRUE
		ORDER BY page.sort_ts DESC`;

/**
 * Unified, infinitely-scrollable feed: photo posts AND raw workout activity from
 * the viewer's circle, interleaved newest-first, keyset-paginated on a combined
 * timestamp (`before`). A workout that already has a feed post is omitted (the
 * post represents it), and a user's raw workouts are hidden when they've turned
 * off `share_workouts_to_feed`. No time window — paginate as far back as desired.
 */
// Hoisted to a const so the /status/schema?profile=feed probe can EXPLAIN the
// BYTE-IDENTICAL string this function runs. A profiler that measures its own
// copy of the SQL measures the wrong query the moment the two drift.
//
// PERF, in two layers. Both exist to keep this query's cost proportional to
// the PAGE and the viewer's CIRCLE, and to nothing that grows on its own.
//
// 1. The expensive per-row columns (route JSONB, is_hyped, hype_count,
//    story_photo_url) are computed ONLY for the page's rows. They used to sit
//    in the SELECT list of a UNION ALL that was then ORDER BY ... LIMIT $3, so
//    Postgres evaluated them for every post and workout in the circle's entire
//    history before the LIMIT could apply. `candidates` now carries only the
//    cheap keys, `page` sorts+limits them (a hard barrier), and the projection
//    runs on those <= $3 rows.
//
// 2. `candidates` itself is bounded, which layer 1 never was. Each arm is a
//    LATERAL per circle member, ordered by the member's own index and cut at
//    $3, so the union is at most (circle x 3 x $3) rows — instead of reading
//    every qualifying workout the circle has ever logged plus every shared post
//    in the database, and sorting the lot. Correct because a row in the global
//    top-$3 is necessarily in its own owner's top-$3. The cursor is pushed into
//    each arm too, so page 2 costs what page 1 costs.
//
// Output shape and every value are identical to the pre-LATERAL query — proven
// by diffing both against each other over a seeded dataset of collabs, blocks,
// private authors and multi-page walks, not by reading them. Results are keyed
// by column name, so column order is irrelevant.
//
// Indexes this relies on: idx_posts_user_created and idx_posts_coauthor_user
// (post arms), idx_workouts_feed_candidates (workout arm — its predicate must
// keep matching that arm's WHERE), posts_pkey for the projection's post join,
// and idx_hype_log_target_context for the hype tallies. That last one is
// PARTIAL, which is why the hype predicates state `context_id IS NOT NULL`
// (see CONTEXTFUL in hypeService).
export const UNIFIED_FEED_SQL = `
		${CIRCLE_CTE},
		candidates AS (
			-- POST candidates, one bounded probe per circle member.
			--
			-- The two arms are the two ways a post reaches this viewer: they follow
			-- the AUTHOR, or they follow an accepted COAUTHOR of a live collab. It
			-- used to be one scan of the posts table with the circle test as an
			-- EXISTS filter, which meant reading EVERY share_to_feed row in the
			-- database on every feed open — the viewer's 3-friend circle paid for
			-- the whole product's post volume — and evaluating the collab-reach
			-- privacy subplan once per (post x circle member): 7,712 seq scans of
			-- notification_settings for one page at test scale. Driving from the
			-- circle CTE instead makes each arm an index probe
			-- (idx_posts_user_created / idx_posts_coauthor_user) that reads only
			-- that member's newest $3 posts, so the cost tracks the viewer's circle
			-- and never the size of the posts table.
			--
			-- UNION, not UNION ALL: the old EXISTS was a semi-join, so a post whose
			-- author AND coauthor are both in the circle appeared once. Dedupe here
			-- keeps that. Every other gate is the same fragment in the same place.
			SELECT kind, id, post_uuid, sort_ts, owner_id, workout_id FROM (
				SELECT
					'post'::text AS kind,
					pc.post_id::text AS id,
					pc.post_id AS post_uuid,
					pc.created_at AS sort_ts,
					pc.user_id AS owner_id,
					pc.workout_id AS workout_id
				FROM circle c
				CROSS JOIN LATERAL (
					SELECT p.post_id, p.created_at, p.user_id, p.workout_id
					FROM posts p
					WHERE p.user_id = c.uid
						AND ${POST_FEED_GATES}
						AND ${CURSOR_BEFORE("p.created_at")}
					ORDER BY p.created_at DESC
					LIMIT $3
				) pc

				UNION

				SELECT
					'post'::text AS kind,
					pc.post_id::text AS id,
					pc.post_id AS post_uuid,
					pc.created_at AS sort_ts,
					pc.user_id AS owner_id,
					pc.workout_id AS workout_id
				FROM circle c
				CROSS JOIN LATERAL (
					SELECT p.post_id, p.created_at, p.user_id, p.workout_id
					FROM posts p
					WHERE p.coauthor_user_id = c.uid
						-- 78ed93a: reached via the coauthor, so the collab must be
						-- live and the coauthor not 'private' — "Only me" has to keep
						-- their name out of other people's feeds. ci-smoke asserts
						-- exactly the case that commit targeted.
						AND ${COLLAB_REACH_SQL}
						AND ${POST_FEED_GATES}
						AND ${CURSOR_BEFORE("p.created_at")}
					ORDER BY p.created_at DESC
					LIMIT $3
				) pc

				UNION

				-- THIRD arm: a buddy walk I was on reaches MY OWN feed, always.
				--
				-- Not a third way for someone else's post to find me — the only
				-- rows it can add are walks this viewer took. The two arms above
				-- both run through the circle, and a buddy walk is the one card
				-- that can fail BOTH: the poster needn't be my friend (a walk
				-- reaches friends-of-members), and the legacy scalar coauthor
				-- holds exactly ONE person, so on a crew of five, four of us are
				-- not reachable through it at all. The walk then existed for me
				-- only under Tagged, which is the wrong shelf for the one record
				-- of a mile I actually walked.
				--
				-- Deliberately outside COLLAB_REACH_SQL: that gate is a REACH
				-- decision about broadcasting a tag to a circle, and this is not
				-- reach — it is the author of the walk seeing their own walk. It
				-- keeps POST_FEED_GATES, so a block, a deletion or a story-only
				-- post hides it exactly as before.
				--
				-- Bounded the same way the arms above are, just by a different
				-- owner: driven from idx_post_coauthors_user for ONE user (the
				-- viewer), so it reads this person's own credited walks and never
				-- scales with the product's post volume. The cursor is pushed in
				-- here too, or page 2 costs what page 1 costs.
				SELECT
					'post'::text AS kind,
					pb.post_id::text AS id,
					pb.post_id AS post_uuid,
					pb.created_at AS sort_ts,
					pb.user_id AS owner_id,
					pb.workout_id AS workout_id
				FROM (
					SELECT p.post_id, p.created_at, p.user_id, p.workout_id
					FROM post_coauthors pca
					JOIN posts p ON p.post_id = pca.post_id
					WHERE pca.user_id = $1
						AND p.buddy_session_id IS NOT NULL
						AND ${MULTI_COLLAB_ACTIVE}
						AND ${POST_FEED_GATES}
						AND ${CURSOR_BEFORE("p.created_at")}
					ORDER BY p.created_at DESC
					LIMIT $3
				) pb
			) post_candidates

			UNION ALL

			SELECT
				'workout'::text AS kind,
				wc.workout_id AS id,
				NULL::uuid AS post_uuid,
				wc.device_end_date AS sort_ts,
				wc.user_id AS owner_id,
				wc.workout_id AS workout_id
			FROM circle c
			-- Same per-member bound as the post arms: idx_workouts_feed_candidates
			-- is (user_id, device_end_date DESC) with a predicate matching this
			-- WHERE exactly, so this walks that member's newest workouts in order
			-- and stops at $3 instead of reading their entire history and sorting
			-- it. That history grows by a row a day forever, which is what made the
			-- feed get slower on its own with nothing changed.
			CROSS JOIN LATERAL (
				SELECT w.workout_id, w.device_end_date, w.user_id
				FROM workouts w
				WHERE w.user_id = c.uid
					AND ${CURSOR_BEFORE("w.device_end_date")}
					AND w.deleted_at IS NULL AND w.exclusion_reason IS NULL
				-- Only two roles ever earn a card: the workout that completed the
				-- day's mile (which stands in for every pre-mile segment — see the
				-- rollup lateral below) and anything logged after it. 'rolled_up'
				-- and 'hidden' are represented by the anchor or not at all, which
				-- is what stops three 0.33 walks becoming three cards and a 3-second
				-- phantom becoming one. A plain indexed predicate on purpose:
				-- idx_workouts_feed_candidates matches this WHERE exactly, and the
				-- PERF note above rules out anything heavier inside candidates.
				AND w.feed_role IN ('daily_mile', 'extra')
				-- HOLD a just-synced workout off OTHER viewers' feeds for the
				-- CAMERA window (same GREATEST anchor as getPostWindowStatus, so
				-- a late Watch sync is held from ARRIVAL, not from a
				-- device_end_date that's already past): if the owner shoots a pic
				-- right after the walk, the photo and the route land together as
				-- ONE card instead of a route card that a photo post replaces
				-- mid-scroll. Deliberately the 10-minute camera tier and NOT the
				-- all-day photo tier — holding every card until midnight to
				-- catch a possible library post would gut the feed's liveness
				-- for the rarer case; a later library post simply lands as its
				-- own card, exactly as it did before this hold existed. The
				-- owner always sees their own workout immediately, and the
				-- friend pushes defer the same 10 minutes (notificationService),
				-- so a push can never point at a held card. Cheap arithmetic on
				-- already-read columns — no extra probe.
				AND (c.uid = $1
					OR GREATEST(w.device_end_date, COALESCE(w.created_at, w.device_end_date))
						<= NOW() - ${POST_WINDOW_MS} * INTERVAL '1 millisecond')
				-- These two NOT EXISTS were ONE clause with an OR between
				-- p2.workout_id and p2.coauthor_workout_id. Splitting them is the
				-- identity NOT EXISTS(A OR B) = NOT EXISTS(A) AND NOT EXISTS(B),
				-- so the result is unchanged — but the OR spanned two different
				-- columns, which left Postgres unable to use an index for either
				-- and scanning every shared post once per candidate workout. That
				-- cost 857 x 232 = ~198k executions of the privacy and block
				-- subplans inside, including 195,720 seq scans of
				-- notification_settings (its user_id IS a primary key; the planner
				-- picks a seq scan anyway because the table is ~114 rows, which is
				-- only a disaster at this loop count). Split, each arm matches an
				-- index — uq_posts_workout_active and idx_posts_coauthor_workout —
				-- so it is two probes per workout, and the privacy subplans run
				-- only for rows that are genuinely collab posts.
				AND NOT EXISTS (
					SELECT 1 FROM posts p2
					WHERE p2.deleted_at IS NULL AND p2.share_to_feed
						AND p2.workout_id = w.workout_id
				)
				-- A collab post only stands in for the coauthor's mile when the
				-- viewer can actually SEE that post (primary author not blocked or
				-- private) — otherwise they'd get neither. The privacy arm mirrors
				-- AUTHOR_VISIBLE_TO_VIEWER so the two stay in step: for the
				-- coauthor themselves the collab post is visible even when the
				-- author went private, and their own workout card must still give
				-- way to it. A severed collab (either author blocked the other)
				-- stands in for nothing — the ex-coauthor's own card comes back.
				AND NOT EXISTS (
					SELECT 1 FROM posts p2
					WHERE p2.deleted_at IS NULL AND p2.share_to_feed
						AND p2.coauthor_workout_id = w.workout_id
						AND ${collabActiveSql("p2")}
						AND p2.user_id NOT IN (SELECT uid FROM blocked)
						AND (p2.user_id = $1 OR p2.coauthor_user_id = $1
							OR ${OWNER_NOT_PRIVATE_SQL("p2.user_id")})
					)
				-- ...and the same for the OTHER legs of a buddy walk, resolved
				-- at READ through the participant row.
				--
				-- The two arms above are keyed on columns frozen at POST time,
				-- and for a buddy walk both are routinely empty:
				-- coauthor_workout_id is stamped by picking the coauthor's
				-- biggest workout on the post's local_date, but the common
				-- order is finish → recap → post → the friend's phone syncs,
				-- so at post time there is no workout to find and the column
				-- stays NULL forever. It also only ever holds ONE person, so a
				-- crew of three was never covered at all. The walk then shows
				-- up twice: the shared card, and the friend's own route card
				-- for the same hour of the same walk — which is exactly what
				-- one-post-per-walk exists to prevent, arriving through the
				-- feed instead of through a second post.
				--
				-- Resolved rather than stored for the same reason the crew's
				-- ROUTES are (see crewRouteSelect): the link lands minutes
				-- after the post, so any column read here is read too early.
				AND NOT EXISTS (
					SELECT 1
					FROM buddy_session_participants bspw
					JOIN posts p2 ON p2.buddy_session_id = bspw.session_id
					WHERE bspw.workout_id = w.workout_id
						AND p2.deleted_at IS NULL AND p2.share_to_feed
						AND p2.buddy_session_id IS NOT NULL
						-- A card only stands in for the walk when the viewer
						-- can actually SEE it — otherwise they'd get neither.
						-- Mirrors the coauthor arm above, plus the multi-crew
						-- case that arm's scalar columns can't express.
						AND p2.user_id NOT IN (SELECT uid FROM blocked)
						AND (p2.user_id = $1 OR p2.coauthor_user_id = $1
							OR EXISTS (
								SELECT 1 FROM post_coauthors pcw
								WHERE pcw.post_id = p2.post_id AND pcw.user_id = $1
									AND pcw.status = 'accepted'
							)
							OR ${OWNER_NOT_PRIVATE_SQL("p2.user_id")})
					)
				ORDER BY w.device_end_date DESC
				LIMIT $3
			) wc
			-- Whether a member's raw workouts reach the feed at all is a fact about
			-- the MEMBER, not about each workout, so it is asked once per member
			-- here instead of once per candidate row inside the lateral. As a row
			-- filter it cost 2,793 seq scans of notification_settings for one page
			-- (its user_id IS the primary key — the planner picks a seq scan anyway
			-- because the table is ~114 rows, which only hurts at that loop count).
			WHERE c.uid NOT IN (SELECT uid FROM blocked)
				AND COALESCE((SELECT ns.share_workouts_to_feed
					FROM notification_settings ns WHERE ns.user_id = c.uid), true)
				-- The feed is always YOUR circle, so 'public' must not pour
				-- strangers in; only the tightening direction applies here.
				AND ${OWNER_NOT_PRIVATE_SQL("c.uid")}
		),
		page AS (
			SELECT kind, id, post_uuid, sort_ts, owner_id, workout_id
			FROM candidates
			-- Redundant now that every arm bounds itself on the cursor, and kept
			-- deliberately: it is the invariant those arms have to satisfy, and it
			-- costs one comparison over at most (circle size x 3 x $3) rows.
			WHERE ($2::timestamptz IS NULL OR sort_ts < $2::timestamptz)
			ORDER BY sort_ts DESC
			LIMIT $3
		)
		${FEED_ENTRY_PROJECTION}
		`;

export async function getUnifiedFeed(
  viewerId: string,
  limit: number,
  before?: string | null,
): Promise<FeedEntryRow[]> {
  return db.query<FeedEntryRow>(UNIFIED_FEED_SQL, [
    viewerId,
    before ?? null,
    limit,
  ]);
}

/**
 * ONE post, shaped exactly like the feed entry for it. Backs opening a post
 * directly (a tap on the profile grid, a mention push, a shared link) instead
 * of hunting for it in a paginated feed — which could never work for a post
 * old enough to be several pages down, or one whose author's activity the
 * viewer doesn't otherwise follow closely.
 *
 * Authorization is `visiblePostAuthor`, the same gate comments and mentions
 * use — it mirrors the feed's circle + block rules, including accepted-coauthor
 * reach. Null when the post is gone or the viewer may not see it; the
 * controller maps that to 404 so post existence isn't leaked.
 */
export async function getFeedEntryForPost(
  viewerId: string,
  postId: string,
): Promise<FeedEntryRow | null> {
  if (!(await visiblePostAuthor(viewerId, postId))) return null;
  const rows = await db.query<FeedEntryRow>(
    `
		WITH page AS (
			SELECT
				'post'::text AS kind,
				p0.post_id::text AS id,
				p0.post_id AS post_uuid,
				p0.created_at AS sort_ts,
				p0.user_id AS owner_id,
				p0.workout_id AS workout_id
			FROM posts p0
			WHERE p0.post_id = $2::uuid AND p0.deleted_at IS NULL
		)
		${FEED_ENTRY_PROJECTION}
		`,
    [viewerId, postId],
  );
  return rows[0] ?? null;
}

export interface PublicPostPreview {
  post_id: string;
  username: string | null;
  first_name: string | null;
  /**
   * The author's avatar and streak. Additive, and NOT a widening of what this
   * endpoint exposes: both are already world-readable for any username at
   * `/public/users/:username`, and profile images are deliberately the one
   * media path left unsigned precisely because they back share pages
   * (mediaSigningService). They are here so the unfurl can be resolved in ONE
   * request — a second round trip per link preview, from a crawler that may
   * give up before it finishes, is how the card ends up half-built.
   */
  profile_image_url: string | null;
  current_streak: number | null;
}

/**
 * The unauthenticated preview behind a shared post link (mileaday.run/p/<id>).
 *
 * Deliberately just "who posted this" — no photo, no caption, no distance.
 * A post is friends-only content and a share link can be forwarded anywhere,
 * so the web page is a signpost, not a viewer: it confirms the link is real,
 * names the author (data already public via /public/users/:username), and
 * hands off to the app, which re-authorizes the viewer properly. Even the
 * `public` workout visibility means "any signed-in user", not the open web.
 *
 * Returns null for a deleted or story-only post, so a bad link 404s.
 */
export async function getPublicPostPreview(
  postId: string,
): Promise<PublicPostPreview | null> {
  const rows = await db.query<PublicPostPreview>(
    `SELECT p.post_id::text AS post_id, u.username, u.first_name,
		        u.profile_image_url, u.current_streak
		 FROM posts p
		 JOIN users u ON u.user_id = p.user_id
		 WHERE p.post_id = $1::uuid AND p.deleted_at IS NULL AND p.share_to_feed`,
    [postId],
  );
  return rows[0] ?? null;
}
