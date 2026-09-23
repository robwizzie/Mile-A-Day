// Shared SQL fragments and projections for post-shaped reads (circle/blocks,
// collab + crew guards, POST_SELECT, comment matching). Bottom of the posts/
// import graph: it imports nothing from its siblings.

import { OWNER_NOT_PRIVATE_SQL } from "../visibilityService.js";
import { postHypedByViewerMatchSql, postHypeMatchSql } from "../hypeService.js";

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

/**
 * Keyset-pagination cursor as URL-safe ISO-8601 UTC with microseconds
 * ("2026-07-04T12:34:56.123456Z"). The raw `::text` of a timestamptz renders
 * as "2026-07-04 12:34:56.123456+00" — and a literal '+' in a query string is
 * decoded as a SPACE by Express's query parser, which made the returned
 * cursor fail its `::timestamptz` cast on the next page ("the feed stops
 * loading"). Microsecond precision is kept so same-millisecond rows at page
 * boundaries are neither skipped nor repeated.
 */
export const URL_SAFE_CURSOR = (col: string) =>
  `to_char((${col}) AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US') || 'Z'`;

/**
 * Share of a workout's elapsed time its moving clock must account for before
 * that clock is allowed to divide a displayed pace.
 *
 * The tracker records `moving_seconds` so a wait at a light doesn't drag a
 * pace down, and every client prefers it whenever it is present. But the
 * moving clock can only report what it WITNESSED, and a witness gap — thin
 * GPS, a locked phone whose fixes arrive in batches, or a build carrying the
 * old per-segment cap — leaves a real workout with a moving time covering a
 * fraction of itself. Dividing the whole distance by that fraction prints a
 * pace nobody walked: a 34:18 walk of 1.03 mi arrived with 8.7 minutes of
 * moving time, and every surface read "8:25 /mi" directly above splits that
 * said 33:05.
 *
 * Withholding it HERE rather than in the app is deliberate: the figure is
 * additive and nullable by contract ("null on old rows/Watch syncs — clients
 * fall back to total_duration"), so every shipped build is fixed by the
 * deploy, including the ones that will never be updated. Falling back to
 * elapsed can only ever report a pace SLOWER than the truth, which is the
 * safe direction for a number people compare to each other.
 *
 * Mirrored in the app by `DisplayPace.minimumMovingCoverage` (Utils/) and by
 * the Live Activity's own copy; the three must move together.
 */
const MIN_MOVING_COVERAGE = 0.5;

/**
 * `w`'s moving time when it may be believed, NULL otherwise — drop-in for a
 * bare `<alias>.moving_seconds` anywhere a pace divides by it.
 */
export const displayMovingSecondsSql = (w: string) => `(CASE
		WHEN ${w}.moving_seconds > 0
			AND ${w}.total_duration > 0
			AND ${w}.moving_seconds <= ${w}.total_duration
			AND ${w}.moving_seconds >= ${w}.total_duration * ${MIN_MOVING_COVERAGE}
		THEN ${w}.moving_seconds
	END)`;

// Base post columns shared by every post-shaped read (viewer-independent).
// The AUTHOR's route is not here because this fragment has no viewer
// placeholder; it rides POST_SELECT (AUTHOR_ROUTE_SQL, `$1` = viewer) so every
// post-shaped read that already ships the CREW's routes (COAUTHOR_COLUMNS →
// CREW_ROUTE_SQL) ships the author's too. It used to be feed-only, and the
// profile grid's detail drew a buddy post with everyone's line except the
// poster's own. Stealth Mode needs no predicate on either path: a workout
// recorded in stealth has NO workout_routes row at all (enforced at write —
// workoutService's conditional route insert + stealthService), so both
// resolve to NULL by construction.
const POST_COLUMNS = `
	p.post_id,
	p.user_id,
	u.username,
	u.first_name,
	u.last_name,
	u.profile_image_url,
	p.media_url,
	-- FRONT & BACK: the swapped composition of the same two frames. Additive
	-- and NULL on every ordinary post; a client that doesn't know it simply
	-- shows media_url, which already has the inset baked in and is a complete
	-- picture on its own.
	p.dual_media_url,
	-- Which corner that inset was BAKED into ('tr'/'tl'/'bl'/'br'). The card
	-- lays an invisible swap target over a region of a photograph it did not
	-- draw, so it has to be told where the poster left it. NULL = the
	-- original top-trailing, which is every post made before it could move.
	p.dual_inset_corner,
	p.caption,
	p.workout_id,
	-- The ONE competition the poster stickered, or NULL. Additive and inert for
	-- shipped clients. The chip a viewer can tap is drawn by matching this id
	-- against the competitions array below, which already carries viewer_in --
	-- so membership is decided server-side and a non-member gets no chip
	-- without this read costing an extra subquery to find that out.
	p.competition_id,
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
				SUM(COALESCE(${displayMovingSecondsSql("m")}, m.total_duration))::double precision AS moving_duration
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
export const collabActiveSql = (a: string) => `(${a}.coauthor_status = 'accepted'
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
export const COLLAB_REACH_SQL = collabReachSql("p");
export const COLLAB_ACTIVE = collabActiveSql("p");

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
export const coauthorOnProfileSql = (a: string, coauthorParam: string) => `COALESCE(
	${a}.coauthor_on_profile,
	(SELECT ns.tagged_posts_on_profile FROM notification_settings ns
		WHERE ns.user_id = ${coauthorParam}),
	TRUE
)`;

/**
 * SQL: the same question for a CREW member — does this buddy walk belong on
 * their Posts grid?
 *
 * The scalar above lives on the POST, so it can record exactly one person's
 * answer. A buddy walk credits up to eight, and four of five people on a walk
 * were therefore unable to say yes at all: the write matched no row and the
 * grid never looked at them. `post_coauthors.on_profile` is their copy of the
 * switch, resolved in the same order — per-post override, then their own
 * `tagged_posts_on_profile`, then TRUE.
 *
 * Requires the `pca` row in scope.
 */
export const coauthorOnProfileMultiSql = (coauthorParam: string) => `COALESCE(
	pca.on_profile,
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
export const MULTI_COLLAB_ACTIVE = `(pca.status = 'accepted'
	AND NOT EXISTS (
		SELECT 1 FROM user_blocks mcb
		WHERE (mcb.blocker_id = p.user_id AND mcb.blocked_id = pca.user_id)
			OR (mcb.blocker_id = pca.user_id AND mcb.blocked_id = p.user_id)
	))`;

// Is the viewer themselves credited on this post? Un-answered invites count —
// that's how a pending invite reaches the person who has to answer it.
export const VIEWER_IS_MULTI_COAUTHOR = `EXISTS (
	SELECT 1 FROM post_coauthors pca
	WHERE pca.post_id = p.post_id AND pca.user_id = $1
		AND pca.status <> 'declined'
)`;

// A live multi-collab reaches every participant's friend circle, exactly as a
// live legacy collab reaches the coauthor's — and stops at the same place, a
// participant whose own visibility is 'private' (collabReachSql's rule).
export const FRIEND_OF_MULTI_COAUTHOR = `EXISTS (
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
export const BLOCKED_VS_MULTI_COAUTHOR = `EXISTS (
	SELECT 1 FROM post_coauthors pca
	JOIN user_blocks b
		ON (b.blocker_id = $1 AND b.blocked_id = pca.user_id)
		OR (b.blocker_id = pca.user_id AND b.blocked_id = $1)
	WHERE pca.post_id = p.post_id AND ${MULTI_COLLAB_ACTIVE}
)`;

/**
 * SQL: is this post a BUDDY WALK the viewer was actually on?
 *
 * A buddy walk is ONE post for N people, so for everyone except whoever
 * pressed Post it arrives as somebody else's card with their name on it —
 * structurally a "tag". It is not one. A tag is a thing another person did
 * that happens to mention you; this is the walk YOU took, and it is the only
 * record of it, because the one-post-per-walk rule deliberately stops you
 * having a card of your own (`buddyWalkPostForWorkout`).
 *
 * That distinction is why this fragment exists rather than another COALESCE
 * inside the collab gates. Those gates answer "may this tag travel", and the
 * switches behind them — `tagged_posts_on_profile`, `coauthor_on_feed` — were
 * offered to users as control over OTHER people's posts about them. Letting
 * either answer for a buddy walk means a user who quieted tags stops seeing
 * their own walks, which is what happened: the walk showed under Tagged and
 * nowhere else.
 *
 * So: accepted participation in a walk that has a session, and nothing about
 * reach. The post still has to clear `POST_FEED_GATES` at the call site —
 * a block, a deletion or an un-shared post hides it exactly as before. This
 * can only ever ADD the viewer's own walk back to their own feed.
 *
 * `$1` must be the viewer. Requires `p` and, inside MULTI_COLLAB_ACTIVE, the
 * `pca` row it is joined against.
 */
export const VIEWER_WAS_ON_THIS_WALK = `(p.buddy_session_id IS NOT NULL AND EXISTS (
	SELECT 1 FROM post_coauthors pca
	WHERE pca.post_id = p.post_id AND pca.user_id = $1
		AND ${MULTI_COLLAB_ACTIVE}
))`;

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
 *  - No `is_auto` gate (same reason as AUTHOR_ROUTE_SQL): the Flyover needs
 *    the lines even when the card's media is already a rendered route.
 *
 * Falls back to `post_coauthors.workout_id` when the post carries one (the
 * legacy accept path stamps it), so this is not buddy-only.
 *
 * A crew member's Stealth Mode walk has no workout_routes row (enforced at
 * write), so it resolves to NULL here with no predicate — do not add one.
 */
/**
 * SQL: WHICH workout is this crew member's leg of the walk.
 *
 * Three fallbacks, in the order they become true, because the link is stamped
 * LATE: post_coauthors.workout_id if the poster knew it, else the participant
 * row the reconciler fills in a minute or two after the walk, else the
 * person's own counted workout that overlaps the session.
 *
 * Its own fragment because the route is no longer the only thing that needs
 * it — the crew's distances and splits resolve the same leg, and must resolve
 * it the SAME way or one card reports two different walks for one person.
 * Deliberately carries NO consent gate: that belongs to the route (a trace is
 * where you were), not to how far someone went on a walk they are credited on.
 */
const CREW_WORKOUT_ID_SQL = `COALESCE(
			pca.workout_id,
			(SELECT bsp.workout_id FROM buddy_session_participants bsp
			  WHERE bsp.session_id = pca.buddy_session_id
				AND bsp.user_id = pca.user_id),
			-- Not linked yet. The link is stamped by reconcileBuddySessions
			-- only when the workout syncs AFTER the Finish tap, and by
			-- linkSyncedWorkouts at finish/close — but the common order is
			-- HealthKit save → observer sync → THEN the buddy finish, so a
			-- walk could sit unlinked until the whole session closed, with the
			-- route on the server the entire time. Resolve it the way the link
			-- itself does: their counted workout that overlaps the walk.
			(SELECT w.workout_id
			   FROM buddy_sessions bs
			   JOIN workouts w
			     ON w.user_id = pca.user_id
			    AND w.deleted_at IS NULL AND w.exclusion_reason IS NULL
			    AND w.device_end_date >= bs.started_at
			    AND (w.device_end_date
			         - (COALESCE(w.total_duration, 0) || ' seconds')::interval)
			        <= COALESCE(bs.ended_at, bs.started_at + INTERVAL '6 hours')
			           + INTERVAL '10 minutes'
			  WHERE bs.id = pca.buddy_session_id AND bs.started_at IS NOT NULL
			  ORDER BY w.device_end_date DESC
			  LIMIT 1)
		)`;

const crewRouteSelect = (expr: string) => `(
	SELECT ${expr} FROM workout_routes wr
	WHERE p.include_route
		AND (
			COALESCE(
				pca.include_route,
				(SELECT ns.share_route_maps FROM notification_settings ns
				  WHERE ns.user_id = pca.user_id),
				true
			)
			OR pca.user_id = $1
		)
		AND wr.workout_id = ${CREW_WORKOUT_ID_SQL}
)`;
const CREW_ROUTE_SQL = crewRouteSelect("wr.route");
// The first fix's instant as epoch seconds: a plain number survives every
// client's date decoder, where a timestamptz string with fractional seconds
// has already broken a payload once.
export const ROUTE_STARTED_AT_EXPR =
  "EXTRACT(EPOCH FROM wr.started_at)::double precision";

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

/** SQL: a column off the crew member's own leg of the walk. */
const crewWorkoutSelect = (expr: string) => `(
	SELECT ${expr} FROM workouts w
	WHERE w.workout_id = ${CREW_WORKOUT_ID_SQL}
)`;

/**
 * SQL: how far this crew member went.
 *
 * The participant row FIRST, because that is the figure BUDDY_GROUP_JSON sums
 * into "3.2 mi between us" — a per-person number read from anywhere else
 * wouldn't add up to the total sitting right above it on the same card.
 */
const CREW_DISTANCE_SQL = `COALESCE(
	(SELECT COALESCE(bsp.final_distance_miles, bsp.distance_miles)
	   FROM buddy_session_participants bsp
	  WHERE bsp.session_id = pca.buddy_session_id
		AND bsp.user_id = pca.user_id),
	${crewWorkoutSelect("w.distance")}
)`;

/** SQL: this crew member's per-mile splits, shaped like the author's. */
const CREW_SPLITS_SQL = `(
	SELECT jsonb_agg(jsonb_build_object(
		'split_number', s.split_number,
		'split_duration', s.split_duration,
		'split_distance', s.split_distance,
		'split_pace', s.split_pace
	) ORDER BY s.split_number)
	FROM (
		SELECT ws.* FROM workout_splits ws
		WHERE ws.workout_id = ${CREW_WORKOUT_ID_SQL}
		ORDER BY ws.split_number
		LIMIT 30
	) s
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
		-- Their slide's FRONT & BACK twin, same contract as the author's.
		'dual_media_url', pca.dual_media_url,
		'dual_inset_corner', pca.dual_inset_corner,
		-- Their own words under their own slide (additive; NULL until set).
		'caption', pca.caption,
		'route', ${CREW_ROUTE_SQL},
		-- The replay clock, same gates as the route it describes.
		'route_times', ${crewRouteSelect("wr.times")},
		'route_started_at', ${crewRouteSelect(ROUTE_STARTED_AT_EXPR)},
		-- A participant's own curation, readable only BY that participant.
		-- Returning it to the whole crew would publish "bob kept this out of
		-- his friends' feeds" to bob's friends, which is the opposite of what
		-- he asked for.
		'on_feed', CASE WHEN pca.user_id = $1
			THEN COALESCE(pca.on_feed, TRUE) END,
		'on_profile', CASE WHEN pca.user_id = $1
			THEN ${coauthorOnProfileMultiSql("$1")} END,
		'include_route', CASE WHEN pca.user_id = $1
			THEN pca.include_route END,
		-- HOW FAR this person went and HOW LONG it took them. A card whose
		-- whole subject is that several people went out together showed one
		-- combined number and one person's stat strip, so "how did we each
		-- do" — the question the card exists to answer — could not be
		-- answered from it at all.
		--
		-- Distance prefers the participant row, which is what BUDDY_GROUP_JSON
		-- SUMS: read from the workout instead and the parts would not add up
		-- to the total printed two lines above them. Falls back to the
		-- workout for a non-buddy collab, which has no participant row.
		'distance_miles', ${CREW_DISTANCE_SQL},
		'duration_seconds', ${crewWorkoutSelect("w.total_duration")},
		'moving_seconds', ${crewWorkoutSelect(displayMovingSecondsSql("w"))},
		-- Their own per-mile splits. NO share_route_maps gate, exactly like
		-- the author's own splits: these are pace and time, not location.
		'splits', ${CREW_SPLITS_SQL}
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
export const AUTHOR_VISIBLE_TO_VIEWER = `(
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
export const POST_FEED_GATES = `(
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
export const CURSOR_BEFORE = (col: string) =>
  `($2::timestamptz IS NULL OR ${col} < $2::timestamptz)`;
export const COAUTHOR_COLUMNS = `
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
	-- Falls back to the crew row so the control has a state to draw for the
	-- four people on a five-person walk who are not the legacy scalar. Sending
	-- NULL there is what made the client hide the option entirely (it branches
	-- on nil to mean "this server doesn't offer it"), so the switch was
	-- missing on exactly the posts it was built for.
	COALESCE(
		CASE WHEN p.coauthor_user_id = $1
			THEN ${coauthorOnProfileSql("p", "$1")} END,
		(SELECT ${coauthorOnProfileMultiSql("$1")} FROM post_coauthors pca
			WHERE pca.post_id = p.post_id AND pca.user_id = $1
				AND pca.status = 'accepted')
	) AS coauthor_on_profile,
	-- Same rule, same reason: the coauthor's reach switch is theirs to read.
	CASE WHEN p.coauthor_user_id = $1
		THEN COALESCE(p.coauthor_on_feed, TRUE) END AS coauthor_on_feed`;

/**
 * The AUTHOR's own simplified route, gated exactly like the unified feed's
 * post arm: the per-post `include_route` choice and the author's global
 * share_route_maps consent — owner exempt. `$1` must be the viewer. NULL
 * when withheld or absent, which shipped clients already render as the
 * routeless card.
 *
 * Auto posts (the route card published for someone who skips the photo
 * prompt) ship their route too. They were excluded because the card's media
 * already IS a rendered route — but the route is what the Flyover flies, so
 * the exclusion meant the feed's most common card could never fly, and a
 * user whose history is mostly auto posts got no Flyover anywhere on the
 * feed after a full backfill. The client keeps the duplicate SLIDE hidden
 * on auto posts (PostCardView.routeSlideCoordinates); it is the chip that
 * needs the coordinates.
 */
const authorRouteSelect = (expr: string) => `(
	SELECT ${expr} FROM workout_routes wr
	WHERE p.include_route
		AND (
			COALESCE(
				(SELECT ns.share_route_maps FROM notification_settings ns
				  WHERE ns.user_id = p.user_id),
				true
			)
			OR p.user_id = $1
		)
		AND wr.workout_id = p.workout_id
)`;
const AUTHOR_ROUTE_SQL = authorRouteSelect("wr.route");
// The author's replay clock, under exactly the route's gates (it describes
// the route, so it is withheld with it).
const AUTHOR_ROUTE_TIMING_SQL = `
	${authorRouteSelect("wr.times")} AS route_times,
	${authorRouteSelect(ROUTE_STARTED_AT_EXPR)} AS route_started_at`;

/**
 * SQL: the competitions `userExpr` was in on `dateExpr` — the card's
 * "COMPETING" flair, so friends can see who is mid-competition without
 * opening the Compete tab.
 *
 * Accepted membership only, the competition's own date window against the
 * POST's day (an old post from a comp's third day says so; a post from after
 * it ended says nothing), bounded to the three ending soonest. Names are
 * user-typed and shown to anyone who can already see the post — the same
 * circle that can be invited to it. `$1` = viewer, for `viewer_in`.
 */
export const competitionsJson = (
  userExpr: string,
  dateExpr: string,
  // The competition this post STICKERED, when the caller has one to name.
  // It only reorders the LIMIT 3 below so the stickered comp is never the one
  // cut: the client draws its tappable chip by matching competition_id against
  // this array, and a poster in four competitions who picked the one ending
  // last would otherwise sticker a card whose chip could not resolve. NULL
  // (the default, and every non-post caller) leaves the ordering exactly as it
  // was -- the term is then NULL for every row and end_date decides.
  pinnedExpr: string = "NULL",
) => `(
	SELECT jsonb_agg(jsonb_build_object(
		'id', pc.id,
		'name', pc.competition_name,
		'type', pc.type,
		'ended', COALESCE(pc.ended, false),
		'team_name', (
			SELECT t->>'name'
			FROM jsonb_array_elements(COALESCE(pc.teams->'teams', '[]'::jsonb)) t
			WHERE pc.team_id IS NOT NULL AND t->>'id' = pc.team_id
			LIMIT 1
		),
		'viewer_in', EXISTS (
			SELECT 1 FROM competition_users vcu
			WHERE vcu.competition_id = pc.id
				AND vcu.user_id = $1
				AND vcu.invite_status = 'accepted'
		)
	) ORDER BY pc.end_date, pc.id)
	FROM (
		SELECT c.id, c.competition_name, c.type, c.ended, c.teams, c.end_date,
			cu.team_id
		FROM competition_users cu
		JOIN competitions c ON c.id = cu.competition_id
		WHERE cu.user_id = ${userExpr}
			AND cu.invite_status = 'accepted'
			AND c.start_date IS NOT NULL
			AND c.start_date <= ${dateExpr}
			AND COALESCE(c.end_date, ${dateExpr}) >= ${dateExpr}
		ORDER BY (c.id = ${pinnedExpr}) DESC NULLS LAST, c.end_date, c.id
		LIMIT 3
	) pc
)`;

/**
 * The comments that belong to ONE post's thread, as a predicate on a
 * `post_comments` alias.
 *
 * Three ways a comment lands on a post, and all three are the same
 * conversation:
 *   - it was left on the post;
 *   - it was left on the raw workout card the post later stood in for (the
 *     thread follows the run when the author promotes it into a post);
 *   - it was left on ANY leg of the buddy walk this post is the card for.
 *
 * That last arm is the one a buddy walk needs. One walk is ONE post carrying
 * N people's workouts, but each of those workouts can still have its own feed
 * card and its own comments — so a crew of three could hold three separate
 * threads about a walk that has a single card. The walk's post is where they
 * converge.
 *
 * Keyed on `posts.buddy_session_id`, which is the column that answers "is this
 * walk already posted" for every participant (`post_coauthors` has no row for
 * the author). Guarded on IS NOT NULL so the whole legacy corpus — every
 * non-buddy post there has ever been — never pays for the probe.
 *
 * Used by BOTH the thread (`listComments`) and every `comment_count`: a count
 * that disagrees with the thread under it reads as comments going missing.
 */
export function postCommentMatchSql(
  comments: string,
  postAlias: string,
  workoutExpr: string = `${postAlias}.workout_id`,
): string {
  return `(
		${comments}.post_id = ${postAlias}.post_id
		OR (${workoutExpr} IS NOT NULL AND ${comments}.workout_id = ${workoutExpr})
		OR (${postAlias}.buddy_session_id IS NOT NULL AND EXISTS (
			SELECT 1 FROM buddy_session_participants bspc
			WHERE bspc.session_id = ${postAlias}.buddy_session_id
				AND bspc.workout_id = ${comments}.workout_id
		))
	)`;
}

/**
 * SQL: the last two comments on a card, for the feed's inline preview.
 *
 * Instagram's rule, and the reason for it: a comment nobody sees until they
 * tap through is a conversation happening in a room off the side of the feed.
 * Two, oldest-first, under the caption — enough to show that people are
 * talking without turning a card into a thread.
 *
 * Blocks are filtered HERE and not by the count beside it, deliberately: the
 * count is "how big is this conversation" (the same number for everyone,
 * matching what the thread shows), while the preview is text this viewer is
 * about to read.
 *
 * `matchSql` is `postCommentMatchSql` or a raw-workout predicate, so a buddy
 * walk's preview covers the same three arms its thread does.
 *
 * The block test is spelled out against user_blocks rather than borrowing the
 * `blocked` CTE: this rides POST_SELECT, and several of its call sites (the
 * profile grid, memories, pinned posts) have no CIRCLE_CTE above them. `$1` is
 * the viewer everywhere POST_SELECT is used — the same invariant is_self and
 * the author's route already depend on.
 */
export function commentPreviewSql(matchSql: string): string {
  return `(
		SELECT jsonb_agg(jsonb_build_object(
			'comment_id', recent.comment_id,
			'user_id', recent.user_id,
			'username', recent.username,
			'content', recent.content
		) ORDER BY recent.created_at ASC)
		FROM (
			SELECT cp.comment_id, cp.user_id, cu2.username, cp.content, cp.created_at
			FROM post_comments cp
			JOIN users cu2 ON cu2.user_id = cp.user_id
			WHERE cp.deleted_at IS NULL
				AND ${matchSql}
				AND NOT EXISTS (
					SELECT 1 FROM user_blocks ub
					WHERE (ub.blocker_id = $1 AND ub.blocked_id = cp.user_id)
						OR (ub.blocker_id = cp.user_id AND ub.blocked_id = $1)
				)
			ORDER BY cp.created_at DESC
			LIMIT 2
		) recent
	)`;
}

// SELECT list shared by feed + story-detail reads so both shapes match PostRow.
// `$1` must be the viewer id (drives is_self / is_hyped / the author's route).
// is_hyped is exact-card state so a different same-day mile doesn't disable
// the button; hype_count still uses the broader run tally for social proof.
export const POST_SELECT = `${POST_COLUMNS},
	${AUTHOR_ROUTE_SQL} AS route,
	${AUTHOR_ROUTE_TIMING_SQL},
	${competitionsJson("p.user_id", "p.local_date", "p.competition_id")} AS competitions,
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
			AND ${postCommentMatchSql("pc", "p")}
	) AS comment_count,
	${commentPreviewSql(postCommentMatchSql("cp", "p"))} AS comment_preview,
	${COAUTHOR_COLUMNS}`;

// Shape the freshly inserted/updated row like a PostRow (is_self=true). `$1`
// is the author here, so AUTHOR_ROUTE_SQL's owner exemption holds.
export const CREATED_POST_SELECT = `
	SELECT ${POST_COLUMNS},
		${AUTHOR_ROUTE_SQL} AS route,
		${AUTHOR_ROUTE_TIMING_SQL},
		${competitionsJson("p.user_id", "p.local_date", "p.competition_id")} AS competitions,
		true AS is_self, false AS is_hyped, 0 AS hype_count, 0 AS comment_count,
		${COAUTHOR_COLUMNS}`;
