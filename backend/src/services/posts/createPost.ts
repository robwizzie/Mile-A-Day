// Creating a post, including the one-post-per-buddy-walk guard.

import { PostgresService } from "../DbService.js";
import {
  type PostStatsSnapshot,
  type PostRow,
  MAX_POST_COAUTHORS,
} from "./postTypes.js";
import { CREATED_POST_SELECT } from "./postSql.js";
import { attachMultiCoauthors } from "./coauthors.js";

const db = PostgresService.getInstance();

export interface CreatePostInput {
  userId: string;
  mediaUrl: string;
  /**
   * FRONT & BACK: the swapped composition of the same two frames. Validated
   * by the controller exactly like `mediaUrl` (own upload, on disk) — it is a
   * media url visible to the whole circle, so the same ownership test applies.
   */
  dualMediaUrl?: string | null;
  /** Which corner the inset was baked into: 'tr' | 'tl' | 'bl' | 'br'. */
  dualInsetCorner?: string | null;
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
  // The ONE competition the poster put on this photo via the sticker tray.
  // Validated in the INSERT itself against the author's accepted membership,
  // so a client claiming a competition it isn't in stores NULL rather than a
  // name it could then get a chip for.
  competitionId?: string | null;
  // The author shared this inside their 10-minute fresh window (client-owned:
  // the window anchors to when the app SAW the finished workout). Drives the
  // FRESH chip for every viewer. Ignored for auto posts; legacy clients that
  // omit it get a server-side derivation in the feed query instead.
  postedLive?: boolean;
}

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
/**
 * The live feed post for the buddy walk this workout belongs to, if somebody
 * has already shared it.
 *
 * Session resolution is deliberately NOT "trust `buddy_session_id` from the
 * client". The posts that create duplicates are the ones made through doors
 * that never set it, and every shipped build predates the field — so a guard
 * that only reads the client's value would miss precisely the cases it exists
 * for. The client's value is used when present (it is the cheapest exact
 * answer) and the workout is used otherwise.
 *
 * Nor can the workout be matched on `buddy_session_participants.workout_id`
 * alone: `reconcileBuddySessions` stamps that a minute or two AFTER the walk,
 * i.e. after whoever posts on finishing has already posted, so it is null at
 * exactly the moment this guard runs. The time-overlap arm is what covers that
 * window — the same shape `reconcileBuddySessions` itself matches with.
 *
 * Posts by the CALLER are excluded: replacing your own auto card with your own
 * photo is the upsert path above, not a duplicate.
 */
/**
 * SQL CTE: the buddy walk a (user, workout, declared session) belongs to.
 *
 * Three arms, in order of trust: the session the client declared, the
 * participant row already stamped with this workout, and the time overlap
 * between the walk and the workout. The workout join is a LEFT JOIN so a post
 * that carries NO workout id (the recap opens before HealthKit has published
 * the walk, and used to post unlinked) still resolves through the declared
 * session — which is exactly the post that slipped past this guard and made a
 * second card. `$1` = user, `$2` = workout id or NULL, `$3` = session or NULL.
 */
const WALK_SESSION_CTE = `
		SELECT bsp.session_id AS id
		  FROM buddy_session_participants bsp
		  JOIN buddy_sessions s ON s.id = bsp.session_id
		  LEFT JOIN workouts w
		    ON w.workout_id = $2::varchar AND w.user_id = $1::varchar
		 WHERE bsp.user_id = $1::varchar
		   AND bsp.status IN ('active', 'finished')
		   AND s.started_at IS NOT NULL
		   AND (
		         bsp.session_id = $3::text
		      OR bsp.workout_id = $2::varchar
		      OR (
		           -- The walk's window overlaps the workout's window.
		           w.workout_id IS NOT NULL
		           AND s.started_at <= w.device_end_date
		           AND COALESCE(s.ended_at, s.started_at + INTERVAL '6 hours')
		               >= (w.device_end_date
		                   - (COALESCE(w.total_duration, 0) || ' seconds')::interval)
		         )
		       )
		 ORDER BY (bsp.session_id = $3::text) DESC,
		          (bsp.workout_id = $2::varchar) DESC,
		          s.started_at DESC
		 LIMIT 1`;

/**
 * The buddy walk this workout is a leg of, resolved from the WORKOUT (or the
 * client's declared session), for anything that must stamp it — most of all
 * the auto route card, which the client never sends a session for. An auto
 * card that doesn't know its walk is a solo card: the guard below can't find
 * it, so the next person's photo opens a second card beside it (the exact
 * two-cards-for-one-walk outcome the guard exists to prevent), and its crew's
 * routes never draw because it credits nobody.
 */
export async function buddySessionIdForWorkout(
  userId: string,
  workoutId: string | null,
  declaredSessionId: string | null,
): Promise<string | null> {
  if (!workoutId && !declaredSessionId) return null;
  const rows = await db.query<{ id: string }>(
    `WITH session AS (${WALK_SESSION_CTE}) SELECT id FROM session`,
    [userId, workoutId, declaredSessionId],
  );
  return rows[0]?.id ?? null;
}

async function buddyWalkPostForWorkout(
  userId: string,
  workoutId: string | null,
  declaredSessionId: string | null,
): Promise<{
  post_id: string;
  user_id: string;
  buddy_session_id: string;
  is_auto: boolean;
} | null> {
  const rows = await db.query<{
    post_id: string;
    user_id: string;
    buddy_session_id: string;
    is_auto: boolean;
  }>(
    `WITH session AS (${WALK_SESSION_CTE})
		SELECT p.post_id, p.user_id, session.id AS buddy_session_id, p.is_auto
		  FROM session
		  JOIN posts p
		    ON p.deleted_at IS NULL
		   AND p.share_to_feed
		   -- Excluded by WORKOUT, not by author. It used to be
		   -- p.user_id <> $1, which let the walk's own author post a SECOND
		   -- card from another leg of it: a mile walked in two goes gave them
		   -- an un-posted workout, the feed FAB offered it, and one walk got
		   -- two cards — the exact outcome this rule exists to prevent, just
		   -- reached from the inside. The only post that must be invisible
		   -- here is the one for THIS workout, because replacing that one is
		   -- the upsert path (ON CONFLICT on workout_id), not a second card.
		   AND ($2::varchar IS NULL OR p.workout_id IS DISTINCT FROM $2::varchar)
		   AND (
		         p.buddy_session_id = session.id
		      OR EXISTS (
		           SELECT 1 FROM post_coauthors pc
		            WHERE pc.post_id = p.post_id
		              AND pc.buddy_session_id = session.id
		         )
		       )
		 ORDER BY p.created_at ASC
		 LIMIT 1`,
    [userId, workoutId, declaredSessionId],
  );
  return rows[0] ?? null;
}

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

  // The walk this post is a leg of, resolved from the workout when the client
  // didn't say (older builds, and every auto card). Stamped on the post so
  // the next person's guard finds it, and — for an auto card — used to credit
  // the crew so their routes draw on it.
  const resolvedSessionId = input.shareToFeed
    ? await buddySessionIdForWorkout(
        input.userId,
        input.workoutId ?? null,
        input.buddySessionId ?? null,
      )
    : null;
  const autoCrewIds: string[] = [];
  if (isAutoValue && resolvedSessionId) {
    const crew = await db.query<{ user_id: string }>(
      `SELECT bsp.user_id FROM buddy_session_participants bsp
			  WHERE bsp.session_id = $1 AND bsp.user_id <> $2
			    AND bsp.status IN ('active', 'finished')
			  ORDER BY bsp.joined_at ASC NULLS LAST`,
      [resolvedSessionId, input.userId],
    );
    autoCrewIds.push(...crew.map((r) => r.user_id));
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

  // ── One post per BUDDY WALK, enforced where it can actually be enforced ──
  //
  // Everyone on a buddy walk records their OWN HKWorkout, so the guard above
  // — keyed on (workout_id, user_id) — can never see that the walk it belongs
  // to has already been shared by somebody else. Until now the invariant was
  // upheld only by the recap's UI reading `recap.post`, which means any OTHER
  // door into the composer (the post-run photo prompt, the feed FAB, the snap
  // gallery) produced a second card for the same walk: two posts, the crew
  // split across them, one map with everyone's route and one with a single
  // line, and a crew-photo nudge asking someone who had already posted.
  //
  // Resolving the session from the WORKOUT rather than trusting the client is
  // the whole point: the doors that cause this are exactly the ones that send
  // no `buddy_session_id`, and every shipped build predates the field.
  //
  // Runs on a DECLARED session even when the post carries no workout id: the
  // recap opens the instant a walk ends, before HealthKit has published it,
  // and a post made in that gap used to skip this guard entirely — the second
  // card, red (no workout type), routeless, and never restated.
  if (input.shareToFeed && (input.workoutId || input.buddySessionId)) {
    const existingWalkPost = await buddyWalkPostForWorkout(
      input.userId,
      input.workoutId ?? null,
      input.buddySessionId ?? null,
    );
    if (existingWalkPost && existingWalkPost.is_auto && !isAutoValue) {
      // The walk's only card is a generated route card — the first finisher
      // skipped their photo prompt while everyone else was still out. A real
      // photo of the walk outranks it, the same rule that lets your own photo
      // replace your own auto card: retire it and let this post be the walk's.
      // (Its author is credited on the new card; their photo can join it.)
      await db.query(
        `UPDATE posts SET deleted_at = NOW()
				  WHERE post_id = $1 AND is_auto AND deleted_at IS NULL`,
        [existingWalkPost.post_id],
      );
    } else if (existingWalkPost) {
      const err: any = new Error("buddy_walk_already_posted");
      // The client is meant to add a crew photo to THIS post instead.
      err.postId = existingWalkPost.post_id;
      err.buddySessionId = existingWalkPost.buddy_session_id;
      // Whose card it is decides what the app can offer. Someone ELSE's and
      // this user has a `post_coauthors` row on it, so their photo can join
      // it as a slide. Their OWN and they have no such row — the author is
      // credited by identity, never by a coauthor row — so the only honest
      // line is that this walk is already shared.
      err.mine = existingWalkPost.user_id === input.userId;
      throw err;
    }
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
				coauthor_workout_id, posted_fresh, buddy_session_id,
				competition_id, dual_media_url, dual_inset_corner
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
				$13,
				-- The stickered competition, RESOLVED here rather than taken on
				-- the client's word: it survives only if the author is an
				-- accepted member. A claim to a competition they aren't in
				-- yields NULL, so the worst a bad client can do is post without
				-- a chip. Fails closed, and costs no extra round trip.
				(
					SELECT c.id FROM competitions c
					JOIN competition_users cu ON cu.competition_id = c.id
					WHERE c.id = $14::varchar
						AND cu.user_id = $1
						AND cu.invite_status = 'accepted'
				),
				$15, $16
			)
				ON CONFLICT ${conflictTarget}
				DO UPDATE SET
					media_url = EXCLUDED.media_url,
					-- Wholesale, NOT COALESCE: the two urls are one photo, so a
					-- re-post that replaces the picture with a single must drop
					-- the old swapped frame with it, or the card would offer a
					-- flip to somebody's previous shot.
					dual_media_url = EXCLUDED.dual_media_url,
					-- Wholesale for the same reason: the corner describes THAT
					-- pair's inset, and keeping an old one would point the tap
					-- target at a place the new picture has nothing in.
					dual_inset_corner = EXCLUDED.dual_inset_corner,
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
					-- inherits the session link rather than losing it. COALESCE
					-- because an auto card resolves its own session now, and a
					-- shipped build's photo replacing it sends none.
					buddy_session_id = COALESCE(EXCLUDED.buddy_session_id, posts.buddy_session_id),
					-- Same reasoning as the coauthor columns: the guard only ever
					-- overwrites an AUTO card, which never carries a competition
					-- (nothing stickers one on the user's behalf), so EXCLUDED
					-- wholesale is safe. It has to be wholesale rather than
					-- COALESCE, or a re-post with the sticker turned OFF would
					-- keep the chip the poster just removed.
					competition_id = EXCLUDED.competition_id${flagUpdates}
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
      // when nothing reached the feed. Auto cards carry it too now — an auto
      // card that doesn't know its walk is a second card waiting to happen.
      resolvedSessionId,
      // Never trusted as sent — the INSERT resolves it against the author's
      // accepted membership and stores NULL if they aren't in it.
      input.competitionId ?? null,
      input.dualMediaUrl ?? null,
      input.dualInsetCorner ?? null,
    ],
  );
  if (rows[0]) {
    const crewToAttach = isAutoValue ? autoCrewIds : multiCoauthorIds;
    if (crewToAttach.length > 0) {
      await attachMultiCoauthors(
        rows[0].post_id,
        input.userId,
        crewToAttach,
        coauthorId,
        resolvedSessionId,
        // Nobody is "tagged" by a generated card; the push is for a person's
        // photo, and the crew nudge already covers the card itself.
        !isAutoValue,
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
