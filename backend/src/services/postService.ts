import { PostgresService } from "./DbService.js";
import {
  MIN_PLAUSIBLE_MILE_SECONDS,
  MAX_PLAUSIBLE_MILE_SECONDS,
} from "./mileTime.js";
import { CLIENT_FEATURES, userSupports } from "./clientFeatures.js";
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
import { stripMediaQuery } from "./mediaSigningService.js";
// One-way: workoutService does not import postService, so this introduces no
// cycle. Used by the crew-photo nudge to check the recipient's local day still
// allows a photo before inviting them to add one.
import { getDailyGoalStatus } from "./workoutService.js";

const db = PostgresService.getInstance();

// Shared circle + symmetric-block fragment. `$1` is always the viewer id.
// `circle` = the viewer's accepted friends plus the viewer themself; blocked
// ids (either direction) are excluded so neither party sees the other.
//
// Exported so other friend-scoped reads (ghostService) get the SAME circle and
// the SAME symmetric block rule rather than re-deriving it — leaderboardService
// re-derived it and quietly lost the block half. Because it hardcodes `$1`, any
// query using it must keep the viewer as its first parameter.
export const CIRCLE_CTE = `
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
  /**
   * Ghost race, present only when the ghost was BEATEN: seconds of margin and
   * the ghost's mile time.
   *
   * Deliberately carried in the snapshot rather than in its own column. The
   * snapshot is jsonb that every feed projection already returns verbatim, so
   * a ghost win reaches the feed, the profile grid, stories and post detail
   * without touching one of those guard-heavy SELECTs.
   *
   * Display only, and client-asserted — `sanitizeGhostStats` clamps it to
   * plausible values so a bad client can only brag with a believable number on
   * its OWN post. Anything that must be TRUSTED (medals) counts
   * `workouts.ghost_margin_seconds` instead, which arrives from the synced
   * HKWorkout on the same footing as distance.
   */
  ghost_margin_seconds?: number | null;
  ghost_target_seconds?: number | null;
}

/**
 * Drop a ghost claim that isn't plausible, keeping the rest of the snapshot.
 * Bounds mirror the client's `GhostTarget.isPlausible` (4:01…40:00); a margin
 * can never exceed the ghost it beat.
 */
export function sanitizeGhostStats(
  stats: PostStatsSnapshot | null,
): PostStatsSnapshot | null {
  if (!stats) return stats;
  const margin = Number(stats.ghost_margin_seconds);
  const target = Number(stats.ghost_target_seconds);
  const ok =
    Number.isFinite(margin) &&
    Number.isFinite(target) &&
    margin > 0 &&
    target >= MIN_PLAUSIBLE_MILE_SECONDS &&
    target <= MAX_PLAUSIBLE_MILE_SECONDS &&
    margin <= target;
  if (ok) return stats;
  const { ghost_margin_seconds, ghost_target_seconds, ...rest } = stats;
  return rest;
}

/**
 * One credited participant on a multi-person collab post.
 *
 * Cap of 8 matches BUDDY_MAX_PARTICIPANTS — a collab post exists to credit a
 * buddy walk, so it can never need more names than a walk can hold.
 */
export const MAX_POST_COAUTHORS = 8;

export interface PostCoauthor {
  user_id: string;
  username: string | null;
  first_name: string | null;
  last_name: string | null;
  profile_image_url: string | null;
  status: "pending" | "accepted" | "declined";
  // THIS participant's own photo on the shared post — the slide that makes a
  // buddy walk one post with everyone's pictures on it instead of one post per
  // person. Null until they add one (and for every pre-existing collab).
  // Blanked to "" by lockUnearnedPhotos alongside the author's, so the
  // earn-to-view gate can't be walked around by reading the crew.
  media_url?: string | null;
  // Their GPS trace for the walk, resolved at READ time from the buddy
  // session's participant row rather than stored — the sync reconciler stamps
  // that workout id a minute or two after the walk ends, which is AFTER the
  // person who posts the moment they finish has already posted. Honors their
  // own "Share route maps" consent, so this is null for anyone who opted out
  // and for an indoor walk with nothing to draw.
  route?: unknown;
  // THIS participant's own two switches on the shared post, and null for
  // everybody except the participant themselves — one person's curation is not
  // another's to read. `on_feed` = does the post reach MY friends' feeds
  // (nothing else moves when it's off: the tag stays, the author's circle
  // keeps it, and I still see it). `include_route` = is MY trace drawn on it,
  // overriding my global "Share route maps" for this one walk; null there
  // means "follow my setting", which is what every pre-existing row does.
  on_feed?: boolean | null;
  include_route?: boolean | null;
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
  // Linked workout's feed_role — display framing only (see the projection
  // comments); null when the post has no workout.
  feed_role: string | null;
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
  // Multi-person collab (Buddy Walks). NULL for every post that predates the
  // feature, so the payload shape is unchanged for the legacy corpus and old
  // clients go on reading the scalar fields above.
  coauthors?: PostCoauthor[] | null;
  // The WALK's combined figures on a buddy post — "3.2 mi between us", the
  // number the recap headlines and the card never showed. Null on every
  // non-buddy post and on every older server.
  buddy_group?: { distance_miles: number; crew_size: number } | null;
  // Resolved "is this collab on MY profile grid?" — only populated when the
  // VIEWER is the coauthor (it's their setting to read), null otherwise.
  // Drives the card's Hide/Show-on-profile action. Additive field.
  coauthor_on_profile?: boolean | null;
  // Sibling of coauthor_on_profile, same rule: only populated when the VIEWER
  // is the coauthor. "Does this collab reach my own friends' feeds?" Additive.
  coauthor_on_feed?: boolean | null;
  // Non-null when the AUTHOR has pinned this post to the top of their grid.
  // Everyone sees the pins (that's the point of a pin) — only the author can
  // set them. Additive field; null on every post that isn't pinned.
  pinned_at?: string | null;
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
	-- Linked workout's feed_role, display framing only (extra vs goal
	-- entry) — same additive field the unified feed carries.
	(SELECT w0.feed_role FROM workouts w0 WHERE w0.workout_id = p.workout_id)
		AS feed_role,
	-- Restated in rollup terms when this post is attached to the workout that
	-- completed a mile made of several walks — the SAME projection the unified
	-- feed applies (getUnifiedFeed). Shared here so the profile grid, story
	-- viewer and memories can't report 0.33 mi for a run the feed calls 1.06.
	-- A post on a non-anchor workout keeps its own exact stats.
	-- COALESCE, not a bare subquery: a post with no linked workout matches no
	-- row and would otherwise come back with its stats nulled out entirely.
	COALESCE((
		SELECT CASE
			WHEN w_.feed_role = 'daily_mile' AND p.stats_snapshot IS NOT NULL
				AND roll_.segment_count > 1
			THEN p.stats_snapshot || jsonb_build_object(
				'distance', roll_.distance,
				'duration', roll_.duration,
				-- Display pace divides by MOVING time where the tracker
				-- recorded it (falling back per-row to elapsed), so a
				-- stop-heavy day doesn't restate to an absurd pace. The
				-- 'duration' key above stays the elapsed truth.
				'pace', CASE WHEN roll_.distance > 0
					THEN roll_.moving_duration / roll_.distance END
			)
			ELSE p.stats_snapshot
		END
		FROM workouts w_
		CROSS JOIN LATERAL (
			SELECT
				COUNT(*) FILTER (WHERE m.feed_role <> 'hidden')::int AS segment_count,
				SUM(m.distance)::double precision AS distance,
				SUM(m.total_duration)::double precision AS duration,
				SUM(COALESCE(m.moving_seconds, m.total_duration))::double precision AS moving_duration
			FROM workouts m
			WHERE m.user_id = w_.user_id AND m.local_date = w_.local_date
				AND m.deleted_at IS NULL AND m.exclusion_reason IS NULL
				AND (
					m.feed_role IN ('rolled_up', 'daily_mile')
					OR (m.feed_role = 'hidden' AND m.device_end_date <= w_.device_end_date)
				)
		) roll_
		WHERE w_.workout_id = p.workout_id
	), p.stats_snapshot) AS stats_snapshot,
	p.local_date::text AS local_date,
	p.share_to_feed,
	p.share_to_story,
	p.story_expires_at,
	p.created_at,
	p.is_auto,
	p.include_route,
	p.pinned_at,
	(SELECT w.workout_type FROM workouts w WHERE w.workout_id = p.workout_id) AS workout_type`;

/**
 * SQL: is the collab on `a` still a real collab AT ALL? Viewer-independent:
 * accepted, and neither author has blocked the other. A block between the two
 * ENDS the collab for everybody — it already drops the row from the coauthor's
 * tagged tab (getUserTaggedPosts), and leaving the feed showing "alice & bob"
 * after bob blocked alice contradicts that. Severing the tag, not the post: the
 * media and the run are the author's, so it simply reverts to a solo post.
 */
const collabActiveSql = (a: string) => `(${a}.coauthor_status = 'accepted'
	AND NOT EXISTS (
		SELECT 1 FROM user_blocks cb
		WHERE (cb.blocker_id = ${a}.user_id AND cb.blocked_id = ${a}.coauthor_user_id)
			OR (cb.blocker_id = ${a}.coauthor_user_id AND cb.blocked_id = ${a}.user_id)
	))`;

/**
 * SQL: is the collab TAG on `a` shown to viewer `$1`?
 *
 * The two people involved always see a LIVE collab (that's how a pending
 * invite reaches the person who has to answer it). For everyone else it also
 * needs the coauthor not set to 'private' — "Only me" promises a user their
 * name never appears in someone else's feed, and a collab tag is exactly that.
 * A withheld tag doesn't remove the post: it stays the AUTHOR's post, shown to
 * the author's circle with no coauthor on it (collabReachSql drops the matching
 * reach). Viewer-side blocks are handled separately and hide the whole post.
 */
const coauthorVisibleSql = (
  a: string,
) => `(${a}.coauthor_user_id IS NOT NULL AND (
	${a}.user_id = $1
	OR ${a}.coauthor_user_id = $1
	OR (${collabActiveSql(a)} AND ${OWNER_NOT_PRIVATE_SQL(`${a}.coauthor_user_id`)})
))`;
const COAUTHOR_VISIBLE = coauthorVisibleSql("p");

/**
 * SQL: may the collab on `a` extend the post's reach to the COAUTHOR's circle?
 * Same rule as the tag above — a live collab with a non-private coauthor — plus
 * that coauthor's own `coauthor_on_feed` switch, which is the difference
 * between "don't put my name on it" (privacy) and "credit me, just don't
 * broadcast it to my friends" (reach). NULL there means TRUE, so this can only
 * ever withhold reach a user explicitly gave up.
 *
 * The `= $1` arm stays OUTSIDE both gates on purpose: turning your own reach
 * off must not delete the post from your OWN feed. It also can't hide the post
 * from the AUTHOR's friends — that post is theirs, and this switch was never
 * offered as a veto over someone else's audience.
 *
 * Written as its own fragment because the reach checks sit in circle semi-joins
 * while the tag check sits in the SELECT list.
 */
const collabReachSql = (a: string) => `(${collabActiveSql(a)} AND (
	${a}.coauthor_user_id = $1
	OR (${OWNER_NOT_PRIVATE_SQL(`${a}.coauthor_user_id`)}
		AND COALESCE(${a}.coauthor_on_feed, TRUE))
))`;
const COLLAB_REACH_SQL = collabReachSql("p");
const COLLAB_ACTIVE = collabActiveSql("p");

/**
 * SQL: does this collab belong on the COAUTHOR's own profile GRID?
 *
 * Scope is deliberately narrow — the grid and nothing else. A collab still
 * reaches both circles' feeds (collabReachSql), still shows on the author's
 * profile, and still lands in the coauthor's Tagged tab; this only answers
 * "is it part of the curated Posts grid", which is the one place Instagram
 * keeps tags OUT of and we were putting them IN.
 *
 * Tri-state resolution, in order: the per-post override, then the coauthor's
 * `tagged_posts_on_profile` setting, then TRUE. NULL (every pre-existing row,
 * and every new tag) means "follow my setting", so flipping that one switch
 * covers the tags a user ALREADY has — the actual complaint — instead of only
 * future ones. Writing the override is what pins a single post either way.
 *
 * `coauthorParam` must be the id of the person whose grid is being built.
 */
const coauthorOnProfileSql = (a: string, coauthorParam: string) => `COALESCE(
	${a}.coauthor_on_profile,
	(SELECT ns.tagged_posts_on_profile FROM notification_settings ns
		WHERE ns.user_id = ${coauthorParam}),
	TRUE
)`;

// ─── Multi-person collabs (post_coauthors) ──────────────────────────────
//
// A Buddy Walk post can credit up to 8 people, which the legacy scalar columns
// (coauthor_user_id / _status / _workout_id) cannot express. Buddy posts write
// BOTH representations: a post_coauthors row per participant AND the legacy
// scalars pointing at the first one, so a shipped client that knows nothing
// about this renders a coherent 2-person collab instead of breaking.
//
// EVERY fragment below is an EXISTS over post_coauthors, so it evaluates FALSE
// for any post without rows there — which is every post that existed before
// this feature. That is what keeps the direct-access guard byte-equivalent for
// the legacy corpus: these clauses can only ever GRANT reach to a genuine
// multi-collab, or DENY it on a block. `$1` must be the viewer id.
//
// Each one is the multi-person mirror of the scalar fragment above it, and
// must STAY a mirror: a participant is a coauthor by another name, so the
// active/privacy/block rules are the same rules.

/**
 * SQL: is participant `pca` still really on the post? The multi-person mirror
 * of `collabActiveSql` — accepted, and no block between the author and that
 * participant (a block between them ends the tag for everyone).
 */
const MULTI_COLLAB_ACTIVE = `(pca.status = 'accepted'
	AND NOT EXISTS (
		SELECT 1 FROM user_blocks mcb
		WHERE (mcb.blocker_id = p.user_id AND mcb.blocked_id = pca.user_id)
			OR (mcb.blocker_id = pca.user_id AND mcb.blocked_id = p.user_id)
	))`;

// Is the viewer themselves credited on this post? Un-answered invites count —
// that's how a pending invite reaches the person who has to answer it.
const VIEWER_IS_MULTI_COAUTHOR = `EXISTS (
	SELECT 1 FROM post_coauthors pca
	WHERE pca.post_id = p.post_id AND pca.user_id = $1
		AND pca.status <> 'declined'
)`;

// A live multi-collab reaches every participant's friend circle, exactly as a
// live legacy collab reaches the coauthor's — and stops at the same place, a
// participant whose own visibility is 'private' (collabReachSql's rule).
const FRIEND_OF_MULTI_COAUTHOR = `EXISTS (
	SELECT 1 FROM post_coauthors pca
	JOIN friendships f ON f.friend_id = pca.user_id
	WHERE pca.post_id = p.post_id AND ${MULTI_COLLAB_ACTIVE}
		AND f.user_id = $1 AND f.status = 'accepted'
		AND (pca.user_id = $1
			OR (${OWNER_NOT_PRIVATE_SQL("pca.user_id")} AND COALESCE(pca.on_feed, TRUE)))
)`;

// Blocks are checked against every LIVE participant, in both directions — the
// same rule (and the same COLLAB_ACTIVE gate) the legacy coauthor block check
// applies, so a participant the author has already blocked off the post can't
// go on hiding it from third parties.
const BLOCKED_VS_MULTI_COAUTHOR = `EXISTS (
	SELECT 1 FROM post_coauthors pca
	JOIN user_blocks b
		ON (b.blocker_id = $1 AND b.blocked_id = pca.user_id)
		OR (b.blocker_id = pca.user_id AND b.blocked_id = $1)
	WHERE pca.post_id = p.post_id AND ${MULTI_COLLAB_ACTIVE}
)`;

/**
 * SQL: one credited participant's route polyline, or NULL.
 *
 * Resolved at READ time rather than stored, and that is the whole point. A
 * participant's workout id is stamped by `reconcileBuddySessions` when THEIR
 * HKWorkout syncs — a minute or two after the walk — while the person who
 * posts does so the moment they finish. Baking the route (or even the workout
 * id) at create time would therefore bake in nothing for almost every crew
 * member, permanently. Resolving it here means a route that lands late simply
 * appears on the card, with no backfill and no second write path.
 *
 * Three gates, all of them the same rules the author's own route already
 * obeys (see the `route` projection in UNIFIED_FEED_SQL):
 *  - `include_route`: the poster's per-post choice covers the whole card. A
 *    walk shared without a map does not sprout four of them.
 *  - the participant's OWN route consent — never the poster's. Being credited
 *    on someone's post is not consent to publish your trace. Resolved in the
 *    same tri-state order the grid switch uses: this post's
 *    `post_coauthors.include_route` override first, then their global
 *    `share_route_maps`, then TRUE. NULL override = "follow my setting", which
 *    is every row that predates the override, so the global switch keeps
 *    covering them.
 *  - `NOT p.is_auto`: an auto card's media already IS a rendered route.
 *
 * Falls back to `post_coauthors.workout_id` when the post carries one (the
 * legacy accept path stamps it), so this is not buddy-only.
 */
const CREW_ROUTE_SQL = `(
	SELECT wr.route FROM workout_routes wr
	WHERE p.include_route AND NOT p.is_auto
		AND (
			COALESCE(
				pca.include_route,
				(SELECT ns.share_route_maps FROM notification_settings ns
				  WHERE ns.user_id = pca.user_id),
				true
			)
			OR pca.user_id = $1
		)
		AND wr.workout_id = COALESCE(
			pca.workout_id,
			(SELECT bsp.workout_id FROM buddy_session_participants bsp
			  WHERE bsp.session_id = pca.buddy_session_id
				AND bsp.user_id = pca.user_id)
		)
)`;

/**
 * SQL: the WALK's combined figures for a buddy post — "3.2 mi between us".
 *
 * The recap headlines this number at hero size and the post never showed it,
 * so the card that exists to say "we did this together" led with one person's
 * distance. Derived, never stored, for the same reason the routes are: it
 * moves as each participant's workout reconciles, and a value frozen at post
 * time would be whatever was known in the first ten seconds.
 *
 * Counts the SAME membership every other buddy surface counts — `active` and
 * `finished`, the set the roster draws and the pooled total sums — and prefers
 * each person's reconciled `final_distance_miles`, falling back to their live
 * figure until it lands. NULL for every non-buddy post, which is the whole
 * legacy corpus.
 */
const BUDDY_GROUP_JSON = `(
	SELECT jsonb_build_object(
		'distance_miles', ROUND(SUM(
			COALESCE(bsp.final_distance_miles, bsp.distance_miles, 0)
		)::numeric, 2)::double precision,
		'crew_size', COUNT(*)
	)
	FROM buddy_session_participants bsp
	WHERE bsp.session_id = COALESCE(
			p.buddy_session_id,
			(SELECT pcg.buddy_session_id FROM post_coauthors pcg
			  WHERE pcg.post_id = p.post_id AND pcg.buddy_session_id IS NOT NULL
			  LIMIT 1)
		)
		AND bsp.status IN ('active', 'finished')
	HAVING COUNT(*) > 1
)`;

// Credited participants, as a JSON array for the client. NULL when the post has
// none, which is every pre-existing post — so the payload shape is unchanged
// for the entire legacy corpus and old clients keep reading the scalar columns.
//
// Tag visibility mirrors coauthorVisibleSql: the author and the participant
// themselves always see the row (pending included, so an invite is answerable);
// everyone else sees only live, non-private participants.
const MULTI_COAUTHORS_JSON = `(
	SELECT jsonb_agg(jsonb_build_object(
		'user_id', mcu.user_id,
		'username', mcu.username,
		'first_name', mcu.first_name,
		'last_name', mcu.last_name,
		'profile_image_url', mcu.profile_image_url,
		'status', pca.status,
		'media_url', pca.media_url,
		'route', ${CREW_ROUTE_SQL},
		-- A participant's own curation, readable only BY that participant.
		-- Returning it to the whole crew would publish "bob kept this out of
		-- his friends' feeds" to bob's friends, which is the opposite of what
		-- he asked for.
		'on_feed', CASE WHEN pca.user_id = $1
			THEN COALESCE(pca.on_feed, TRUE) END,
		'include_route', CASE WHEN pca.user_id = $1
			THEN pca.include_route END
	) ORDER BY pca.created_at)
	FROM post_coauthors pca
	JOIN users mcu ON mcu.user_id = pca.user_id
	WHERE pca.post_id = p.post_id
		AND (p.user_id = $1 OR pca.user_id = $1
			OR (${MULTI_COLLAB_ACTIVE} AND ${OWNER_NOT_PRIVATE_SQL("pca.user_id")}))
)`;

/**
 * SQL: may viewer `$1` see post `p` given the AUTHOR's visibility? Every
 * credited person always sees their own collab (a private author's post leaves
 * everyone else's feed, but never their own or their coauthors').
 */
const AUTHOR_VISIBLE_TO_VIEWER = `(
	p.user_id = $1
	OR p.coauthor_user_id = $1
	OR ${VIEWER_IS_MULTI_COAUTHOR}
	OR ${OWNER_NOT_PRIVATE_SQL("p.user_id")}
)`;

/**
 * Everything a post `p` must satisfy to be a feed candidate, EXCEPT how it
 * reached the viewer (author vs coauthor) — that part differs per arm.
 *
 * Named because the unified feed now asks it from two arms and getFeed asks it
 * from one, and the three drifted apart once already: one copy dropped a
 * private author's post from their OWN feed (bare OWNER_NOT_PRIVATE_SQL has no
 * self exception — "Only me" still has to include me) while another let a
 * private coauthor's reach through, so the same post got two different answers
 * depending on which query asked. One fragment, one answer.
 */
const POST_FEED_GATES = `(
	p.share_to_feed
	AND p.deleted_at IS NULL
	AND ${AUTHOR_VISIBLE_TO_VIEWER}
	AND p.user_id NOT IN (SELECT uid FROM blocked)
	AND (NOT ${COLLAB_ACTIVE}
		OR p.coauthor_user_id NOT IN (SELECT uid FROM blocked))
)`;

/**
 * The keyset bound, `$2` being the cursor (NULL on the first page).
 *
 * Pushed into each candidate arm rather than applied once above them: a bound
 * the arm knows about is a starting point for its index scan, whereas the same
 * bound applied afterwards makes the arm produce its newest rows only to have
 * them thrown away — which is how page 2 used to cost the same as page 1.
 */
const CURSOR_BEFORE = (col: string) =>
  `($2::timestamptz IS NULL OR ${col} < $2::timestamptz)`;
const COAUTHOR_COLUMNS = `
	CASE WHEN ${COAUTHOR_VISIBLE} THEN p.coauthor_user_id END AS coauthor_user_id,
	CASE WHEN ${COAUTHOR_VISIBLE} THEN p.coauthor_status END AS coauthor_status,
	(SELECT cu.username FROM users cu WHERE cu.user_id = p.coauthor_user_id AND ${COAUTHOR_VISIBLE}) AS coauthor_username,
	(SELECT cu.first_name FROM users cu WHERE cu.user_id = p.coauthor_user_id AND ${COAUTHOR_VISIBLE}) AS coauthor_first_name,
	(SELECT cu.last_name FROM users cu WHERE cu.user_id = p.coauthor_user_id AND ${COAUTHOR_VISIBLE}) AS coauthor_last_name,
	(SELECT cu.profile_image_url FROM users cu WHERE cu.user_id = p.coauthor_user_id AND ${COAUTHOR_VISIBLE}) AS coauthor_profile_image_url,
	${MULTI_COAUTHORS_JSON} AS coauthors,
	${BUDDY_GROUP_JSON} AS buddy_group,
	-- Only meaningful to the coauthor themselves (it's their grid), so it's
	-- NULL for everyone else rather than leaking one user's curation choice
	-- to the other. CASE guarantees the subquery only runs on collab rows the
	-- viewer is actually part of.
	CASE WHEN p.coauthor_user_id = $1
		THEN ${coauthorOnProfileSql("p", "$1")} END AS coauthor_on_profile,
	-- Same rule, same reason: the coauthor's reach switch is theirs to read.
	CASE WHEN p.coauthor_user_id = $1
		THEN COALESCE(p.coauthor_on_feed, TRUE) END AS coauthor_on_feed`;

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
		WHERE pc.deleted_at IS NULL
			AND (
				pc.post_id = p.post_id
				OR (p.workout_id IS NOT NULL AND pc.workout_id = p.workout_id)
			)
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
  // Multi-person collab (Buddy Walks). When present, EVERY id here gets a
  // post_coauthors row AND the first also fills the legacy scalar columns
  // above, so shipped clients still render a coherent 2-person collab.
  // Validated identically to coauthorUserId: accepted friend, no block either
  // way, never self. Invalid ids are dropped rather than failing the post —
  // one friend who unfriended you mid-walk shouldn't lose the whole recap.
  coauthorUserIds?: string[] | null;
  // Links the post back to the session it came from (analytics + recap).
  buddySessionId?: string | null;
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
  const collabAllowed = !isAutoValue && input.shareToFeed;

  // Multi-person collab. Each candidate is validated with the SAME predicate
  // the single-coauthor path uses, but invalid ones are DROPPED instead of
  // throwing: a buddy recap crediting four people shouldn't fail outright
  // because one of them unfriended you between the walk and the post.
  const multiCoauthorIds: string[] = [];
  if (collabAllowed && input.coauthorUserIds?.length) {
    const candidates = Array.from(new Set(input.coauthorUserIds)).filter(
      (id) => id && id !== input.userId,
    );
    for (const candidate of candidates.slice(0, MAX_POST_COAUTHORS)) {
      const ok = await db.query(
        `SELECT 1 FROM friendships f
				 WHERE f.user_id = $1 AND f.friend_id = $2 AND f.status = 'accepted'
					 AND NOT EXISTS (
						 SELECT 1 FROM user_blocks b
						 WHERE (b.blocker_id = $1 AND b.blocked_id = $2)
								OR (b.blocker_id = $2 AND b.blocked_id = $1)
					 )`,
        [input.userId, candidate],
      );
      if (ok.length > 0) multiCoauthorIds.push(candidate);
    }
  }

  // The legacy scalar mirrors the FIRST multi-coauthor when one wasn't named
  // explicitly. That mirror is what keeps a shipped client — which has no idea
  // post_coauthors exists — rendering the post as a normal 2-person collab
  // rather than as a solo post with three uncredited people in the photo.
  const coauthorId = !collabAllowed
    ? null
    : (input.coauthorUserId ?? multiCoauthorIds[0] ?? null);
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
    // An explicitly-named bad coauthor is still a hard error (unchanged
    // behavior); a mirrored one was already validated above, so this can only
    // fire for the explicit path.
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
				coauthor_workout_id, posted_fresh, buddy_session_id
			)
			VALUES (
				$1, $2, $3, $4, $5::jsonb, $6::date, $7, $8,
				CASE WHEN $8 THEN NOW() + INTERVAL '24 hours' ELSE NULL END,
				-- Tagging is IMMEDIATE, Instagram-style: a collab lands on the
				-- coauthor's profile the moment it's posted, and their way out is
				-- to remove themselves (respondToCoauthorInvite with accept=false).
				-- It used to insert 'pending' and wait for an accept that most
				-- people never saw, so collabs simply never appeared.
				$9, $10, $11, CASE WHEN $11::text IS NULL THEN NULL ELSE 'accepted' END,
				-- Their side of the day's run, picked the same way the old accept
				-- path picked it. Stamped here now that there's no accept step.
				(
					SELECT w.workout_id FROM workouts w
					WHERE w.user_id = $11 AND w.local_date = $6::date
						AND w.deleted_at IS NULL AND w.exclusion_reason IS NULL
					ORDER BY w.distance DESC LIMIT 1
				),
				$12,
				-- Recorded on the POST, not only per participant: post_coauthors
				-- has no row for the author, so a walk whose crew all dropped out
				-- (or a solo finisher's) had a post nothing could find by session.
				-- The recap's "has this walk been posted yet" reads this.
				$13
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
					coauthor_workout_id = EXCLUDED.coauthor_workout_id,
					posted_fresh = EXCLUDED.posted_fresh,
					-- Same reasoning as the coauthor columns above: the guard only
					-- ever overwrites an AUTO post, and an auto card is never a
					-- buddy post, so EXCLUDED wholesale is safe. Taking it also
					-- means the deliberate post that REPLACES the auto card
					-- inherits the session link rather than losing it.
					buddy_session_id = EXCLUDED.buddy_session_id${flagUpdates}
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
      // Feed-only, same as the collab it describes: a story is not "the walk's
      // post", so linking one would make the recap report a walk as shared
      // when nothing reached the feed.
      !isAutoValue && input.shareToFeed ? (input.buddySessionId ?? null) : null,
    ],
  );
  if (rows[0]) {
    if (multiCoauthorIds.length > 0) {
      await attachMultiCoauthors(
        rows[0].post_id,
        input.userId,
        multiCoauthorIds,
        coauthorId,
        input.buddySessionId ?? null,
      );
      // Re-read so the caller's payload carries the coauthors array it just
      // created, rather than the pre-attachment snapshot.
      const refreshed = await db.query<PostRow>(
        `${CREATED_POST_SELECT}
			   FROM posts p
			   JOIN users u ON u.user_id = p.user_id
			  WHERE p.post_id = $2`,
        [input.userId, rows[0].post_id],
      );
      if (refreshed[0]) return refreshed[0];
    }
    return rows[0];
  }

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
async function attachMultiCoauthors(
  postId: string,
  authorId: string,
  coauthorIds: string[],
  mirroredCoauthorId: string | null,
  buddySessionId: string | null,
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
  const toNotify = coauthorIds.filter((id) => id !== mirroredCoauthorId);
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

/** Distance for a workout that exists and belongs to the user (post-link guard). */
export async function getOwnedWorkoutDistance(
  userId: string,
  workoutId: string,
): Promise<number | null> {
  const rows = await db.query<{ distance: number | string | null }>(
    `SELECT distance FROM workouts WHERE workout_id = $1 AND user_id = $2`,
    [workoutId, userId],
  );
  const distance = Number(rows[0]?.distance);
  return Number.isFinite(distance) ? distance : null;
}

/**
 * The DAY's rollup distance for a post's linked workout — i.e. the number every
 * read surface already restates a `daily_mile` anchor with (see POST_COLUMNS).
 * Null when the workout isn't the day's anchor, so callers fall back to the
 * workout's own distance.
 *
 * Exists so the auto-post stats guard accepts a card that bakes the day's total
 * (what the feed will display) as well as one that bakes the single leg. Same
 * membership rule as the feed lateral: everything rolled into the anchor, plus
 * sub-floor junk logged up to it.
 */
export async function getOwnedWorkoutRollupDistance(
  userId: string,
  workoutId: string,
): Promise<number | null> {
  const rows = await db.query<{ distance: number | string | null }>(
    `SELECT SUM(m.distance)::double precision AS distance
		 FROM workouts w
		 JOIN workouts m ON m.user_id = w.user_id AND m.local_date = w.local_date
			 AND m.deleted_at IS NULL AND m.exclusion_reason IS NULL
			 AND (
				 m.feed_role IN ('rolled_up', 'daily_mile')
				 OR (m.feed_role = 'hidden' AND m.device_end_date <= w.device_end_date)
			 )
		 WHERE w.workout_id = $1 AND w.user_id = $2 AND w.feed_role = 'daily_mile'`,
    [workoutId, userId],
  );
  const distance = Number(rows[0]?.distance);
  return Number.isFinite(distance) ? distance : null;
}

/**
 * How long after a qualifying walk/run a photo may be CAPTURED and posted.
 *
 * This bounds the live camera only. A photo the user already took on the walk
 * and picks out of their camera roll is not on a clock — see
 * `photoSourceRequiresCameraWindow`.
 *
 * The client owns the same number (`FreshPostWindowManager.duration`) and runs
 * the visible countdown off it — keep the two equal.
 */
export const POST_WINDOW_MS = 10 * 60 * 1000;

/**
 * Where the photo being posted came from, as declared by the client.
 *
 *  - `camera`   — shot just now with the in-app camera. Held to the ten
 *                 minutes: that's the whole claim the countdown makes.
 *  - `library`  — picked out of the camera roll. The client's importer only
 *                 ever SHOWS photos whose library creation time falls inside
 *                 the workout, so it's still a photo of the walk; the user just
 *                 got to it later. Open for the rest of the day.
 *  - `existing` — a photo already posted (a story being promoted onto the
 *                 feed). It was captured under whichever rule applied then, so
 *                 re-charging it the camera window would only punish the user
 *                 for having shared to their story first.
 *
 * Absent or unrecognised means an older build that predates the split, and
 * those only ever post live captures — so the default is the camera window,
 * i.e. exactly the behaviour those builds already ship against.
 */
export type PostPhotoSource = "camera" | "library" | "existing";

export function photoSourceRequiresCameraWindow(source: unknown): boolean {
  return source !== "library" && source !== "existing";
}

/**
 * Slack past the visible window, server-side only and never shown to the user.
 *
 * The client's countdown starts when the APP first sees the finished workout;
 * this one starts when the SERVER first does, which is necessarily the same
 * instant or later — so our window already closes no earlier than theirs. The
 * grace covers the round trip on top of that: someone who taps Share with five
 * seconds left still has to upload a 1080x1350 JPEG before the create call
 * lands. Rejecting that would be punishing a slow network, not a late post.
 */
export const POST_WINDOW_GRACE_MS = 2 * 60 * 1000;

export interface PostWindowStatus {
  /**
   * May a LIVE CAPTURE be posted right now? The ten-minute window, plus the
   * private grace. This is what the visible countdown counts down to.
   */
  cameraOpen: boolean;
  /**
   * May a photo be posted at all? True for the rest of the day once a
   * qualifying walk or run has landed — that's what a camera-roll pick and a
   * story promotion answer to. False all day for someone who hasn't moved,
   * which is the rule that actually keeps the feed about moving.
   */
  photoOpen: boolean;
  /** The qualifying workout whose window is the most recent one today. */
  workoutId: string | null;
  /** When that window opened, and when it closes for DISPLAY (no grace). */
  openedAt: string | null;
  closesAt: string | null;
  /** Countdown to the displayed close, floored at 0. */
  secondsRemaining: number;
}

const CLOSED_WINDOW: PostWindowStatus = {
  cameraOpen: false,
  photoOpen: false,
  workoutId: null,
  openedAt: null,
  closesAt: null,
  secondsRemaining: 0,
};

/**
 * The photo-posting window for a user's day. TWO tiers, not one.
 *
 * A photo post has to belong to a walk or run — that is the whole point of the
 * feed, and an unbounded composer turns it into a general-purpose photo stream
 * that happens to sit next to some mileage. But "belongs to the walk" is a
 * claim about the PHOTO, and only one of the two ways to get a photo needs a
 * clock to make that claim:
 *
 *  - The live camera claims "this is happening now", so it's bounded to ten
 *    minutes (`cameraOpen`). Past that the claim isn't true any more.
 *  - A camera-roll pick claims "I took this on the walk", which the client
 *    proves by capture time, not by how fast the user got to their phone. It
 *    stays open for the rest of the day (`photoOpen`). Being made to choose
 *    between finishing your cooldown and keeping your photo was the whole
 *    complaint — nothing about the photo changes at minute eleven.
 *
 * Both tiers still require a qualifying workout today, so neither is a way to
 * post without moving.
 *
 * "Qualifying" is already computed and maintained for us: `feed_role` is
 * `daily_mile` on the workout that reached the day's goal and `extra` on every
 * substantive one after it, which is exactly "the goal, plus each additional
 * goal reached". Reusing it means this can never disagree with what the feed
 * shows, and it inherits the anchor's stickiness and sub-floor filtering for
 * free. `rolled_up` and `hidden` deliberately don't open a window: the first is
 * a leg folded into the anchor's card, the second is a phantom.
 *
 * The window is anchored to whichever came LAST, the workout ending or the
 * server first hearing about it. A Watch run that syncs twenty minutes after it
 * ended is not a late post — it's the first moment the user could have posted
 * it at all, and `created_at` survives re-uploads (it isn't in the sync
 * upsert's DO UPDATE list) so a fullSync can't reopen a window that closed.
 */
export async function getPostWindowStatus(
  userId: string,
  localDate: string,
  now: number = Date.now(),
): Promise<PostWindowStatus> {
  const rows = await db.query<{
    workout_id: string;
    opened_at: Date | string | null;
  }>(
    `SELECT workout_id,
			GREATEST(device_end_date, COALESCE(created_at, device_end_date)) AS opened_at
		 FROM workouts
		 WHERE user_id = $1 AND local_date = $2::date
			 AND deleted_at IS NULL AND exclusion_reason IS NULL
			 AND feed_role IN ('daily_mile', 'extra')
		 ORDER BY opened_at DESC, workout_id DESC
		 LIMIT 1`,
    [userId, localDate],
  );
  const row = rows[0];
  if (!row?.opened_at) return CLOSED_WINDOW;
  // Raw-SQL timestamptz comes back as a Date; be tolerant of either shape.
  const openedAt = new Date(row.opened_at);
  if (Number.isNaN(openedAt.getTime())) return CLOSED_WINDOW;

  const closesAt = openedAt.getTime() + POST_WINDOW_MS;
  return {
    cameraOpen: now < closesAt + POST_WINDOW_GRACE_MS,
    // A qualifying workout exists for this local day, which is the entire
    // condition — the row we just found IS it. It stops being true when the
    // day rolls over, since `localDate` is what scopes the query.
    photoOpen: true,
    workoutId: row.workout_id,
    openedAt: openedAt.toISOString(),
    closesAt: new Date(closesAt).toISOString(),
    secondsRemaining: Math.max(0, Math.round((closesAt - now) / 1000)),
  };
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
    coauthors?: { user_id: string; media_url?: string | null }[] | null;
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
    // A buddy post carries the whole crew's photos, so gating only the
    // author's would hand the viewer three unearned pictures on the very card
    // the gate exists for. The viewer's OWN slide survives — same "you can
    // always see your own" rule the author gets one branch up.
    for (const c of r.coauthors ?? []) {
      if (c.user_id === viewerId || !c.media_url) continue;
      c.media_url = "";
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
		WHERE ${POST_FEED_GATES}
			-- Accepted collab posts reach BOTH authors' circles (semi-join, not a
			-- JOIN, so a post whose two authors share the viewer isn't doubled).
			AND EXISTS (
				SELECT 1 FROM circle c
				WHERE c.uid = p.user_id
					OR (c.uid = p.coauthor_user_id AND ${COLLAB_REACH_SQL})
			)
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
const FEED_ENTRY_PROJECTION = `
		SELECT
			page.kind,
			page.id,
			page.sort_ts,
			page.owner_id AS user_id,
			u.username, u.first_name, u.last_name, u.profile_image_url,
			p.media_url, p.caption,
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
			page.workout_id,
			-- Populated for posts (via their linked workout) and workouts alike.
			wt.workout_type,
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
				THEN COALESCE(roll.moving_duration, wt.moving_seconds)::double precision END AS moving_seconds,
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
			CASE
				WHEN page.kind = 'post' THEN (
					SELECT wr.route FROM workout_routes wr
					WHERE p.include_route AND NOT p.is_auto
						AND (COALESCE(nsp.share_route_maps, true) OR page.owner_id = $1)
						AND wr.workout_id = p.workout_id
				)
				ELSE (
					SELECT wr.route FROM workout_routes wr
					-- Withheld on a multi-segment rollup: the anchor's trace is only
					-- the LAST leg, so drawing it under a combined "1.06 mi" stat
					-- line labels a 0.40-mile loop as the whole mile. Clients fall
					-- back to the branded stats face, which shipped builds already
					-- handle.
					WHERE COALESCE(roll.segment_count, 1) <= 1
						AND (COALESCE(nsp.share_route_maps, true) OR page.owner_id = $1)
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
			CASE
				WHEN page.kind = 'post' THEN (
					SELECT COUNT(*)::int FROM post_comments pc
					WHERE pc.deleted_at IS NULL
						AND (
							pc.post_id = p.post_id
							OR (page.workout_id IS NOT NULL AND pc.workout_id = page.workout_id)
						)
				)
				ELSE (
					SELECT COUNT(*)::int FROM post_comments pc
					WHERE pc.workout_id = wt.workout_id AND pc.deleted_at IS NULL
				)
			END AS comment_count,
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
				SUM(COALESCE(m.moving_seconds, m.total_duration))::double precision AS moving_duration,
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
    `SELECT p.post_id::text AS post_id, u.username, u.first_name
		 FROM posts p
		 JOIN users u ON u.user_id = p.user_id
		 WHERE p.post_id = $1::uuid AND p.deleted_at IS NULL AND p.share_to_feed`,
    [postId],
  );
  return rows[0] ?? null;
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
					AND ${coauthorOnProfileSql("p", author)}))
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
  const orderBy =
    sort === "oldest" ? "p.created_at ASC" : "p.created_at DESC";

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
const DIRECT_POST_ACCESS_SQL = `p.deleted_at IS NULL AND p.share_to_feed
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

/**
 * A photo posted from a buddy walk, keyed back to the session it came from.
 *
 * Feeds the buddy history screen. The posts themselves are ordinary feed posts;
 * what links them to a walk is the `buddy_session_id` the post wizard stamps on
 * every `post_coauthors` row it writes. Visibility runs through
 * `DIRECT_POST_ACCESS_SQL` — the SAME guard comments, mentions and inbox
 * previews use — rather than "you were both on the walk": having walked with
 * someone is not standing permission to see a photo they later took private,
 * un-shared, or that a block has since put out of reach.
 */
export interface BuddySessionPhoto {
  buddy_session_id: string;
  post_id: string;
  user_id: string;
  media_url: string;
  caption: string | null;
  local_date: string | null;
  is_auto: boolean;
  /** Set by lockUnearnedPhotos when today's photo is withheld. */
  photo_locked?: boolean;
}

/**
 * Photos from the given buddy sessions that `viewerId` may see, at most
 * `perSession` each (oldest first — the first photo posted is the one everyone
 * recognises as "the" picture from that walk).
 *
 * Sign media urls before responding.
 */
export async function buddySessionPhotos(
  viewerId: string,
  sessionIds: string[],
  perSession = 4,
): Promise<BuddySessionPhoto[]> {
  const ids = sessionIds.filter((id) => /^[0-9a-f]{1,32}$/i.test(id));
  if (ids.length === 0) return [];
  return db.query<BuddySessionPhoto>(
    // The join fans out one row per credited participant, so the link set is
    // collapsed to DISTINCT post ids BEFORE the per-session ranking — otherwise
    // a 4-person walk's single photo would fill the whole per-session budget
    // four times over. Aliased `pcb` because DIRECT_POST_ACCESS_SQL's own
    // subqueries already use `pca`.
    `WITH linked AS (
			SELECT DISTINCT pcb.buddy_session_id, p.post_id, p.created_at
			FROM post_coauthors pcb
			JOIN posts p ON p.post_id = pcb.post_id
			WHERE pcb.buddy_session_id = ANY($2::text[])
				AND p.media_url IS NOT NULL AND p.media_url <> ''
				AND ${DIRECT_POST_ACCESS_SQL}
		), ranked AS (
			SELECT l.buddy_session_id, p.post_id, p.user_id, p.media_url, p.caption,
						 p.local_date::text AS local_date, p.is_auto,
						 ROW_NUMBER() OVER (
							 PARTITION BY l.buddy_session_id ORDER BY l.created_at ASC
						 ) AS rn
			FROM linked l
			JOIN posts p ON p.post_id = l.post_id
		)
		SELECT buddy_session_id, post_id, user_id, media_url, caption, local_date,
					 is_auto
		FROM ranked
		WHERE rn <= $3
		ORDER BY buddy_session_id, rn`,
    [viewerId, ids, Math.min(Math.max(perSession, 1), 10)],
  );
}

/**
 * The feed post that already stands for a buddy walk, if there is one.
 *
 * This is what makes a buddy walk ONE post. Before it, "has this walk been
 * shared" was answered from `PostedWorkoutRegistry` — a UserDefaults list on
 * the poster's own phone — so the second person on the walk opened a recap
 * whose CTA was still lit, posted the same walk again, and the feed carried
 * the same hour twice with the crew split across both cards.
 *
 * Answered for ANY participant, not just the author: the whole point is that
 * the other four people are told the walk is already up (and offered a slide
 * on it) instead of being invited to duplicate it.
 *
 * Deliberately NOT visibility-gated the way a feed read is. Everyone here was
 * on the walk, and the answer carries no content — an id, a name, and whether
 * the caller has added their own photo. A viewer who cannot actually see the
 * post still needs to be told not to make a second one, and `addCrewPhoto`
 * re-authorizes on its own terms anyway.
 */
export interface BuddySessionPost {
  post_id: string;
  author_user_id: string;
  author_name: string | null;
  /** Has the CALLER already put their own photo on it? */
  my_photo_added: boolean;
  /** Is the caller credited at all (author or accepted participant)? */
  am_i_credited: boolean;
  created_at: string;
}

export async function buddySessionPost(
  sessionId: string,
  viewerId: string,
): Promise<BuddySessionPost | null> {
  if (!/^[0-9a-f]{1,32}$/i.test(sessionId)) return null;
  const rows = await db.query<BuddySessionPost>(
    // Two ways a post is "this session's": the column the wizard stamps on the
    // post itself, and a post_coauthors row carrying the session. The second
    // arm is what finds posts made before posts.buddy_session_id existed, so
    // this needs no backfill to start working on the existing corpus.
    `SELECT p.post_id, p.user_id AS author_user_id,
					COALESCE(u.username, u.first_name) AS author_name,
					p.created_at::text AS created_at,
					EXISTS (
						SELECT 1 FROM post_coauthors mine
						WHERE mine.post_id = p.post_id AND mine.user_id = $2
							AND mine.status = 'accepted'
							AND mine.media_url IS NOT NULL AND mine.media_url <> ''
					) AS my_photo_added,
					(p.user_id = $2 OR EXISTS (
						SELECT 1 FROM post_coauthors mine2
						WHERE mine2.post_id = p.post_id AND mine2.user_id = $2
							AND mine2.status = 'accepted'
					)) AS am_i_credited
			 FROM posts p
			 JOIN users u ON u.user_id = p.user_id
			WHERE p.deleted_at IS NULL AND p.share_to_feed
				AND (
					p.buddy_session_id = $1
					OR EXISTS (
						SELECT 1 FROM post_coauthors pcs
						WHERE pcs.post_id = p.post_id AND pcs.buddy_session_id = $1
					)
				)
			ORDER BY p.created_at ASC
			LIMIT 1`,
    [sessionId, viewerId],
  );
  return rows[0] ?? null;
}

/**
 * Put a credited participant's own photo on a shared buddy post.
 *
 * The alternative — which is what shipped — was that everyone else on the walk
 * made their own post, so a walk two people took produced two cards, each
 * crediting the other, each with half the pictures. This is the same user
 * action ("share my photo of this walk") landing on the card that already
 * exists.
 *
 * Authorization is membership, not friendship: you may add a photo to a post
 * you are ACCEPTED on, and to nothing else. The author's own photo is
 * `posts.media_url` and is set at create — they are not a post_coauthors row,
 * so they cannot reach this path and do not need to.
 *
 * The day/camera tiers apply exactly as they do to a first post
 * (`photoSourceRequiresCameraWindow`): this is a photo reaching the feed, and
 * routing it through a different door must not buy a looser rule than posting
 * it directly would have. Callers pass the client's declared `photo_source`.
 *
 * Idempotent by design — re-adding REPLACES. A participant swapping their
 * picture is editing their own slide, not opening a second one.
 */
export async function addCrewPhoto(
  postId: string,
  userId: string,
  mediaUrl: string,
): Promise<boolean> {
  const rows = await db.query<{ post_id: string }>(
    `UPDATE post_coauthors
				SET media_url = $3, photo_added_at = NOW()
			WHERE post_id = $1 AND user_id = $2 AND status = 'accepted'
				AND EXISTS (
					SELECT 1 FROM posts p
					WHERE p.post_id = $1 AND p.deleted_at IS NULL AND p.share_to_feed
				)
			RETURNING post_id`,
    [postId, userId, stripMediaQuery(mediaUrl)],
  );
  return rows.length > 0;
}

/**
 * "3 of you were out, 1 photo so far" — the nudge that turns a buddy post into
 * something people come back to.
 *
 * ## Why this points at the CAMERA ROLL, not the camera
 *
 * Photo posting has two tiers (`getPostWindowStatus`): `cameraOpen`, the ten
 * minutes after a qualifying walk, and `photoOpen`, the rest of that local day.
 * This fires roughly an hour after the walk ends, so the camera window is
 * long shut by construction — every one of these nudges is a LIBRARY-tier ask,
 * and the copy has to say so. Telling someone to "grab a photo" when the
 * shutter has been closed for fifty minutes is the same dead end the
 * `post_window_closed` error used to be.
 *
 * It is also gated on `photoOpen` per recipient rather than assumed: someone
 * whose local day has already rolled over cannot post at all, and a push
 * inviting them to do it would tap through to a locked composer. That check is
 * the reason this is a per-user loop rather than one bulk query.
 *
 * ## Once each, and never a backlog
 *
 * `post_coauthors.photo_nudge_sent_at` is the claim, stamped before the send.
 * It has no DEFAULT on purpose (backend.md: a `DEFAULT now()` on an existing
 * table stores one missing-value for every historical row, so an "older than
 * an hour" gate stays silent for an hour and then fires on the whole archive in
 * one tick). The window below — sessions that ended between one and six hours
 * ago — is the second guard: a deploy after a quiet night has nothing to catch
 * up on.
 */
export async function sweepCrewPhotoNudges(): Promise<number> {
  const candidates = await db.query<{
    post_id: string;
    user_id: string;
    session_id: string;
    crew_size: string;
    photos_so_far: string;
  }>(
    `SELECT pca.post_id, pca.user_id, pca.buddy_session_id AS session_id,
            (SELECT COUNT(*) FROM buddy_session_participants bsp
              WHERE bsp.session_id = pca.buddy_session_id
                AND bsp.status IN ('active', 'finished'))::text AS crew_size,
            (1 + (SELECT COUNT(*) FROM post_coauthors done
                   WHERE done.post_id = pca.post_id
                     AND done.status = 'accepted'
                     AND done.media_url IS NOT NULL
                     AND done.media_url <> ''))::text AS photos_so_far
       FROM post_coauthors pca
       JOIN posts p ON p.post_id = pca.post_id
       JOIN buddy_sessions s ON s.id = pca.buddy_session_id
      WHERE pca.status = 'accepted'
        AND pca.photo_nudge_sent_at IS NULL
        AND (pca.media_url IS NULL OR pca.media_url = '')
        AND p.deleted_at IS NULL AND p.share_to_feed
        AND s.status = 'completed'
        AND s.ended_at BETWEEN NOW() - INTERVAL '6 hours'
                           AND NOW() - INTERVAL '55 minutes'
      LIMIT 200`,
  );

  let sent = 0;
  for (const row of candidates) {
    try {
      // Claim FIRST. A push that fails is better lost than repeated every five
      // minutes for six hours.
      const claimed = await db.query<{ post_id: string }>(
        `UPDATE post_coauthors SET photo_nudge_sent_at = NOW()
          WHERE post_id = $1 AND user_id = $2 AND photo_nudge_sent_at IS NULL
          RETURNING post_id`,
        [row.post_id, row.user_id],
      );
      if (claimed.length === 0) continue;

      if (
        !(await userSupports(row.user_id, CLIENT_FEATURES.buddyGroupPostV1))
      ) {
        continue;
      }
      const goal = await getDailyGoalStatus(row.user_id);
      // Their local day has rolled over (or they never qualified today) — the
      // composer this push opens would refuse the photo, so don't send it.
      if (!goal.completed) continue;
      const window = await getPostWindowStatus(row.user_id, goal.localDate);
      if (!window.photoOpen) continue;

      const crew = Number(row.crew_size);
      const photos = Number(row.photos_so_far);
      await sendPush(row.user_id, {
        title:
          photos === 1
            ? `${crew} of you were out — 1 photo so far 📸`
            : `${crew} of you were out — ${photos} photos so far 📸`,
        // The ask is explicitly for a photo already TAKEN. See the doc comment:
        // the ten-minute camera window shut long before this fired.
        body: "Add one from your camera roll to the walk's post.",
        type: "crew_photo_nudge",
        data: { post_id: row.post_id, buddy_session_id: row.session_id },
      });
      sent += 1;
    } catch (e: any) {
      console.error("[sweepCrewPhotoNudges] failed:", e?.message ?? e);
    }
  }
  return sent;
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
  const rows = await db.query<{ author_id: string }>(
    `UPDATE posts SET coauthor_on_profile = $3
		 WHERE post_id = $2 AND coauthor_user_id = $1 AND deleted_at IS NULL
		 RETURNING user_id AS author_id`,
    [userId, postId, onProfile],
  );
  return rows[0] ?? null;
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

/**
 * Would a NEW tag on `coauthorId` land on their profile grid? Reads the
 * setting alone — a brand-new tag has no per-post override yet. Only used to
 * word the tag push truthfully; the grid query resolves this itself.
 */
async function taggedPostsLandOnProfile(coauthorId: string): Promise<boolean> {
  const rows = await db.query<{ on_profile: boolean | null }>(
    `SELECT tagged_posts_on_profile AS on_profile
		 FROM notification_settings WHERE user_id = $1`,
    [coauthorId],
  );
  return rows[0]?.on_profile ?? true;
}

/**
 * Push "you've been tagged" to the coauthor. Never throws.
 *
 * The post is ALREADY on their profile by the time this sends — there's no
 * invite to answer, so the push is an FYI with a way out, not a decision.
 * Devices that registered the collab-tag capability additionally get a
 * "Remove me" action button, so opting out never requires opening the app.
 */
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
    const canRemoveInline = await userSupports(
      coauthorId,
      CLIENT_FEATURES.collabTagV1,
    );
    // Say where it actually went. Telling someone with tags-off-my-grid that
    // it's "on your profile now" is simply false, and it's the one line that
    // would send them hunting for a post that isn't there.
    const onProfile = await taggedPostsLandOnProfile(coauthorId);
    await sendPush(coauthorId, {
      title: `${name} tagged you in their post 🤝`,
      body: onProfile
        ? "It's on your profile now — you can remove yourself any time."
        : "It's in your Tagged tab — you can remove yourself any time.",
      // Type unchanged: every shipped build routes `coauthor_invite`, and a new
      // string would tap to nothing on all of them.
      type: "coauthor_invite",
      ...(canRemoveInline ? { category: "COAUTHOR_TAG" } : {}),
      data: { user_id: authorId, post_id: postId },
    });
  } catch (e: any) {
    console.error("[notifyCoauthorInvite] failed:", e?.message ?? e);
  }
}

/**
 * "Sam added their photo to your walk."
 *
 * The moment that makes a shared card feel alive rather than static: without
 * it, a buddy post is a thing one person made and everyone else silently
 * appended to, and nobody ever goes back to look. Goes to the AUTHOR and to
 * every other credited participant, because on a four-person walk the third
 * photo landing is news to all three of the others, not just the poster.
 *
 * Type string is new, so it's gated on `buddyGroupPostV1` — an older build has
 * no route for it and would show a banner that taps to nothing. Same reason
 * the `post_id` rides in `data`: the client opens the post directly. Every
 * value there stays a STRING (shipped builds decode the inbox as
 * `[String: String]`, and one number breaks the whole decode).
 *
 * Never throws — a failed push must not fail the photo.
 */
export async function notifyCrewPhoto(
  postId: string,
  actorId: string,
): Promise<void> {
  try {
    const rows = await db.query<{ user_id: string }>(
      // Everyone on the post except whoever just added the photo. The author
      // is unioned in explicitly: they have no post_coauthors row of their own.
      `SELECT p.user_id FROM posts p
        WHERE p.post_id = $1 AND p.deleted_at IS NULL AND p.user_id <> $2
        UNION
       SELECT pca.user_id FROM post_coauthors pca
        WHERE pca.post_id = $1 AND pca.status = 'accepted' AND pca.user_id <> $2`,
      [postId, actorId],
    );
    if (rows.length === 0) return;

    const actor = await db.query<{ username: string | null }>(
      `SELECT username FROM users WHERE user_id = $1`,
      [actorId],
    );
    const name = actor[0]?.username ?? "A friend";

    for (const { user_id: recipient } of rows) {
      if (!(await shouldSendNotification(recipient, actorId, "hype"))) continue;
      if (!(await userSupports(recipient, CLIENT_FEATURES.buddyGroupPostV1))) {
        continue;
      }
      await sendPush(recipient, {
        title: `${name} added their photo 📸`,
        body: "It's on your walk's post — go see it.",
        type: "crew_photo",
        data: { user_id: actorId, post_id: postId },
      });
    }
  } catch (e: any) {
    console.error("[notifyCrewPhoto] failed:", e?.message ?? e);
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

// ─── Story Highlights ────────────────────────────────────────────────────
//
// A highlight is a named, ordered list of the OWNER's own posts, pinned to
// their profile above the grid. It stores no media and copies nothing: every
// read re-resolves the member posts, so a post that is later deleted or made
// private simply leaves the highlight, with no orphaned copy to clean up.
//
// The reason the feature exists is the expiry. A story is the only content in
// this app with one, and `story_expires_at` retiring it from the rail is
// exactly why nobody bothers making one. Adding a story to a highlight is
// therefore a PUBLICATION decision — it takes a photo that was going to
// disappear and makes it permanent for whoever can already see the profile —
// which is why `highlightMemberWhere` deliberately drops the `share_to_feed`
// requirement the grid enforces while keeping every other rule (the owner's
// workout_visibility, blocks in either direction, and the caller's
// lockUnearnedPhotos gate on the way out) exactly as it is.

// Same shape check the controllers apply before a ::uuid cast, restated here
// rather than imported: a service reaching into a controller inverts the
// dependency, and this list arrives as a client-supplied array that never
// passes through a route param.
const HIGHLIGHT_UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const isUuid = (value: string): boolean => HIGHLIGHT_UUID_RE.test(value);

/** Enough for a profile rail; past this the row stops being scannable. */
export const MAX_HIGHLIGHTS_PER_USER = 20;
/** Per highlight. A highlight is a story, not an archive. */
export const MAX_HIGHLIGHT_ITEMS = 100;
export const MAX_HIGHLIGHT_TITLE = 30;

export interface PostHighlight {
  highlight_id: string;
  user_id: string;
  title: string;
  cover_post_id: string | null;
  /**
   * An uploaded cover image, or null when the cover comes from a member post.
   * Additive: `cover_media_url` already resolves it, so a client that ignores
   * this field still draws the right circle — it exists so the editor can say
   * "custom cover set" and offer to drop back to a member's photo.
   */
  cover_image_url: string | null;
  /**
   * Resolved cover photo — the uploaded cover if there is one, else the
   * chosen member post, else the first member. Every client reads this one
   * field, which is why a custom cover needs no client change to appear.
   */
  cover_media_url: string | null;
  item_count: number;
  sort_index: number;
  created_at: string;
  updated_at: string;
}

/**
 * SQL: may viewer `viewer` see owner `owner`'s post `p` AS A HIGHLIGHT MEMBER?
 *
 * The grid's rules minus `share_to_feed` (membership is the publish decision,
 * see above) and minus the collab arm (a highlight only ever holds the owner's
 * own posts, enforced at write time). Everything that protects another person
 * — visibility, blocks — is unchanged and stated here rather than assumed.
 */
const highlightMemberWhere = (viewer: string, owner: string) => `(
			p.user_id = ${owner}
			AND p.deleted_at IS NULL
			AND ${VIEWER_MAY_SEE_WORKOUT_CONTENT_SQL(owner, viewer)}
			AND (p.user_id = ${viewer} OR ${OWNER_NOT_PRIVATE_SQL("p.user_id")})
			AND (p.user_id = ${viewer} OR NOT EXISTS (
				SELECT 1 FROM user_blocks b
				WHERE (b.blocker_id = ${viewer} AND b.blocked_id = p.user_id)
					OR (b.blocker_id = p.user_id AND b.blocked_id = ${viewer})
			))
		)`;

/**
 * The owner's highlight rail. Counts and covers are resolved against the same
 * visibility rule the members are, so a highlight whose every post has become
 * invisible to this viewer reports 0 rather than a count they can't reach —
 * and the caller drops those, instead of drawing a circle that opens empty.
 */
export async function listUserHighlights(
  viewerId: string,
  ownerId: string,
): Promise<PostHighlight[]> {
  return db.query<PostHighlight>(
    `
		SELECT h.highlight_id,
			h.user_id,
			h.title,
			h.cover_post_id,
			h.cover_image_url,
			COALESCE(h.cover_image_url, (
				SELECT p.media_url FROM post_highlight_items i
				JOIN posts p ON p.post_id = i.post_id
				WHERE i.highlight_id = h.highlight_id
					AND ${highlightMemberWhere("$1", "h.user_id")}
				-- The chosen cover wins; otherwise the first member does, so a
				-- highlight always has a face even after its cover is deleted.
				ORDER BY (p.post_id = h.cover_post_id) DESC, i.sort_index, i.added_at
				LIMIT 1
			)) AS cover_media_url,
			(
				SELECT COUNT(*)::int FROM post_highlight_items i
				JOIN posts p ON p.post_id = i.post_id
				WHERE i.highlight_id = h.highlight_id
					AND ${highlightMemberWhere("$1", "h.user_id")}
			) AS item_count,
			h.sort_index,
			h.created_at,
			h.updated_at
		FROM post_highlights h
		WHERE h.user_id = $2
		ORDER BY h.sort_index ASC, h.created_at ASC
		LIMIT $3
		`,
    [viewerId, ownerId, MAX_HIGHLIGHTS_PER_USER],
  );
}

export interface HighlightDetail {
  highlight_id: string;
  user_id: string;
  title: string;
  items: PostRow[];
}

/** One highlight, opened. Members in the owner's chosen order. */
export async function getHighlight(
  viewerId: string,
  highlightId: string,
): Promise<HighlightDetail | null> {
  const head = await db.query<{
    highlight_id: string;
    user_id: string;
    title: string;
  }>(
    `SELECT highlight_id, user_id, title FROM post_highlights WHERE highlight_id = $1`,
    [highlightId],
  );
  if (head.length === 0) return null;

  const items = await db.query<PostRow>(
    `
		SELECT ${POST_SELECT},
			${URL_SAFE_CURSOR("p.created_at")} AS cursor
		FROM post_highlight_items i
		JOIN posts p ON p.post_id = i.post_id
		JOIN users u ON u.user_id = p.user_id
		WHERE i.highlight_id = $2
			AND ${highlightMemberWhere("$1", "$3")}
		ORDER BY i.sort_index ASC, i.added_at ASC
		LIMIT $4
		`,
    [viewerId, highlightId, head[0].user_id, MAX_HIGHLIGHT_ITEMS],
  );

  return {
    highlight_id: head[0].highlight_id,
    user_id: head[0].user_id,
    title: head[0].title,
    items,
  };
}

export type HighlightWriteResult =
  | { ok: true; highlight_id: string }
  | { ok: false; error: "not_found" | "limit" | "invalid_title" | "no_posts" };

function normalizeHighlightTitle(raw: unknown): string | null {
  const title = typeof raw === "string" ? raw.trim() : "";
  if (!title || title.length > MAX_HIGHLIGHT_TITLE) return null;
  return title;
}

/**
 * Which of `postIds` are genuinely the caller's own live posts, in the order
 * they were given. Everything else is DROPPED rather than rejected: the client
 * builds this list from a grid it may have loaded minutes ago, and a post
 * deleted in the meantime should not fail the whole save.
 */
async function ownedPostIds(
  userId: string,
  postIds: string[],
): Promise<string[]> {
  const wanted = Array.from(new Set(postIds.filter(isUuid))).slice(
    0,
    MAX_HIGHLIGHT_ITEMS,
  );
  if (wanted.length === 0) return [];
  const rows = await db.query<{ post_id: string }>(
    `SELECT post_id FROM posts
		 WHERE post_id = ANY($1::uuid[]) AND user_id = $2 AND deleted_at IS NULL`,
    [wanted, userId],
  );
  const live = new Set(rows.map((r) => r.post_id));
  return wanted.filter((id) => live.has(id));
}

/**
 * The uploaded cover image for a write, or `undefined` for "leave it alone".
 *
 * `cover_image_url` is validated by the CONTROLLER (same ownership + on-disk
 * checks a post's media gets) and reaches here already stripped of its
 * signature, so a service that can't do filesystem checks never has to guess.
 * An empty string means "drop the custom cover and go back to a member's
 * photo" — the client can't express a JSON null through an encoder that omits
 * nil, so the empty string is the clear.
 */
function normalizeCoverImage(raw: unknown): string | null | undefined {
  if (typeof raw !== "string") return undefined;
  return raw.trim() === "" ? null : raw;
}

export async function createHighlight(
  userId: string,
  input: {
    title: unknown;
    post_ids?: unknown;
    cover_post_id?: unknown;
    cover_image_url?: unknown;
  },
): Promise<HighlightWriteResult> {
  const title = normalizeHighlightTitle(input.title);
  if (!title) return { ok: false, error: "invalid_title" };

  const count = await db.query<{ n: string }>(
    `SELECT COUNT(*) AS n FROM post_highlights WHERE user_id = $1`,
    [userId],
  );
  if (Number(count[0]?.n ?? 0) >= MAX_HIGHLIGHTS_PER_USER) {
    return { ok: false, error: "limit" };
  }

  const postIds = await ownedPostIds(
    userId,
    Array.isArray(input.post_ids) ? input.post_ids.map(String) : [],
  );
  if (postIds.length === 0) return { ok: false, error: "no_posts" };
  const cover =
    typeof input.cover_post_id === "string" &&
    postIds.includes(input.cover_post_id)
      ? input.cover_post_id
      : postIds[0];

  const created = await db.query<{ highlight_id: string }>(
    `INSERT INTO post_highlights (user_id, title, cover_post_id, cover_image_url, sort_index)
		 VALUES ($1, $2, $3, $4,
			COALESCE((SELECT MAX(sort_index) + 1 FROM post_highlights WHERE user_id = $1), 0))
		 RETURNING highlight_id`,
    [userId, title, cover, normalizeCoverImage(input.cover_image_url) ?? null],
  );
  const highlightId = created[0].highlight_id;
  await replaceHighlightItems(highlightId, postIds);
  return { ok: true, highlight_id: highlightId };
}

/**
 * Membership rewrite as one statement pair: delete what's no longer a member,
 * then upsert the given order. `sort_index` comes from the array position, so
 * reordering is the same call as adding — the client always sends the list it
 * wants to end up with, which is the only shape a drag-to-reorder UI can
 * honestly produce.
 */
async function replaceHighlightItems(
  highlightId: string,
  postIds: string[],
): Promise<void> {
  await db.query(
    `DELETE FROM post_highlight_items
		 WHERE highlight_id = $1 AND NOT (post_id = ANY($2::uuid[]))`,
    [highlightId, postIds],
  );
  if (postIds.length === 0) return;
  await db.query(
    `INSERT INTO post_highlight_items (highlight_id, post_id, sort_index)
		 SELECT $1, v.post_id, v.ord
		 FROM UNNEST($2::uuid[]) WITH ORDINALITY AS v(post_id, ord)
		 ON CONFLICT (highlight_id, post_id) DO UPDATE SET sort_index = EXCLUDED.sort_index`,
    [highlightId, postIds],
  );
}

export async function updateHighlight(
  userId: string,
  highlightId: string,
  input: {
    title?: unknown;
    post_ids?: unknown;
    cover_post_id?: unknown;
    cover_image_url?: unknown;
    sort_index?: unknown;
  },
): Promise<HighlightWriteResult> {
  const owned = await db.query<{ highlight_id: string }>(
    `SELECT highlight_id FROM post_highlights WHERE highlight_id = $1 AND user_id = $2`,
    [highlightId, userId],
  );
  if (owned.length === 0) return { ok: false, error: "not_found" };

  let title: string | null = null;
  if (input.title !== undefined) {
    title = normalizeHighlightTitle(input.title);
    if (!title) return { ok: false, error: "invalid_title" };
  }

  let postIds: string[] | null = null;
  if (input.post_ids !== undefined) {
    postIds = await ownedPostIds(
      userId,
      Array.isArray(input.post_ids) ? input.post_ids.map(String) : [],
    );
    // An empty highlight is a circle that opens onto nothing, so emptying one
    // is a delete in disguise — say so instead of leaving the shell behind.
    if (postIds.length === 0) return { ok: false, error: "no_posts" };
    await replaceHighlightItems(highlightId, postIds);
  }

  const cover =
    typeof input.cover_post_id === "string" && isUuid(input.cover_post_id)
      ? input.cover_post_id
      : null;
  const sortIndex =
    typeof input.sort_index === "number" && Number.isFinite(input.sort_index)
      ? Math.max(0, Math.trunc(input.sort_index))
      : null;

  // Three states, not two: absent leaves the uploaded cover alone, a path
  // replaces it, and the empty string drops it so the member photo shows again.
  const coverImage = normalizeCoverImage(input.cover_image_url);

  await db.query(
    `UPDATE post_highlights SET
			title = COALESCE($3, title),
			-- Only ever a member post: a cover pointing at something that isn't
			-- in the highlight would render a photo the highlight doesn't hold.
			cover_post_id = CASE
				WHEN $4::uuid IS NULL THEN cover_post_id
				WHEN EXISTS (SELECT 1 FROM post_highlight_items i
					WHERE i.highlight_id = $1 AND i.post_id = $4::uuid) THEN $4::uuid
				ELSE cover_post_id END,
			cover_image_url = CASE WHEN $6::boolean THEN $7::text ELSE cover_image_url END,
			sort_index = COALESCE($5, sort_index),
			updated_at = NOW()
		 WHERE highlight_id = $1 AND user_id = $2`,
    [
      highlightId,
      userId,
      title,
      cover,
      sortIndex,
      coverImage !== undefined,
      coverImage ?? null,
    ],
  );
  return { ok: true, highlight_id: highlightId };
}

/** Hard delete — the posts themselves are untouched, only the grouping goes. */
export async function deleteHighlight(
  userId: string,
  highlightId: string,
): Promise<boolean> {
  const rows = await db.query<{ highlight_id: string }>(
    `DELETE FROM post_highlights WHERE highlight_id = $1 AND user_id = $2
		 RETURNING highlight_id`,
    [highlightId, userId],
  );
  return rows.length > 0;
}
