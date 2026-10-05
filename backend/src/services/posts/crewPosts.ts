// Buddy-walk (crew) posts: session photos/post lookups, crew slides/captions
// and the crew-photo nudge sweep.

import { PostgresService } from "../DbService.js";
import { userSupports, CLIENT_FEATURES } from "../clientFeatures.js";
import { sendPush } from "../pushNotificationService.js";
import { stripMediaQuery } from "../mediaSigningService.js";
// One-way: workoutService does not import postService, so this introduces no
// cycle. Used by the crew-photo nudge to check the recipient's local day still
// allows a photo before inviting them to add one.
import { getDailyGoalStatus } from "../workoutService.js";
import { getPostWindowStatus } from "./postWindow.js";
import { DIRECT_POST_ACCESS_SQL } from "./postAccess.js";

const db = PostgresService.getInstance();

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
  /** A crew member's own slide on the shared post, not the lead photo. */
  is_crew: boolean;
  /** Set by lockUnearnedPhotos when today's photo is withheld. */
  photo_locked?: boolean;
}

/**
 * Photos from the given buddy sessions that `viewerId` may see: at most
 * `perSession` POSTS each (oldest first — the first photo posted is the one
 * everyone recognises as "the" picture from that walk), and with each post
 * every crew member's own slide (post_coauthors.media_url), so a four-person
 * walk's history carries all four pictures, not just the poster's.
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
					 is_auto, is_crew
		FROM (
			SELECT r.buddy_session_id, r.post_id, r.user_id, r.media_url, r.caption,
						 r.local_date, r.is_auto, FALSE AS is_crew, r.rn, 0 AS slot,
						 NULL::timestamptz AS slide_at
			FROM ranked r
			WHERE r.rn <= $3
			UNION ALL
			-- The crew's own slides ride with their post: same access guard (the
			-- post is what was authorized), one row per credited person who
			-- added a picture.
			SELECT r.buddy_session_id, r.post_id, pcc.user_id, pcc.media_url,
						 NULL::text AS caption, r.local_date, FALSE AS is_auto,
						 TRUE AS is_crew, r.rn, 1 AS slot, pcc.created_at AS slide_at
			FROM ranked r
			JOIN post_coauthors pcc ON pcc.post_id = r.post_id
			WHERE r.rn <= $3
				AND pcc.status = 'accepted'
				AND pcc.media_url IS NOT NULL AND pcc.media_url <> ''
		) all_photos
		ORDER BY buddy_session_id, rn, slot, slide_at NULLS FIRST`,
    [viewerId, ids, Math.min(Math.max(perSession, 1), 10)],
  );
}

/**
 * The shared post standing for each of the given buddy sessions, for the
 * viewer who may SEE it — the batched, visibility-gated sibling of
 * `buddySessionPost` (which answers "is this walk posted" to any participant
 * with no content). The history screen opens this post as the walk itself:
 * it carries everyone's photo and everyone's route, so a walk with a post
 * needs no second read for either. Earliest post per session, same tie-break
 * as the photo loader.
 */
export async function buddySessionPostIds(
  viewerId: string,
  sessionIds: string[],
): Promise<Map<string, string>> {
  const ids = sessionIds.filter((id) => /^[0-9a-f]{1,32}$/i.test(id));
  if (ids.length === 0) return new Map();
  const rows = await db.query<{ buddy_session_id: string; post_id: string }>(
    `WITH linked AS (
			SELECT DISTINCT COALESCE(p.buddy_session_id, pcb.buddy_session_id) AS buddy_session_id,
						 p.post_id, p.created_at
			FROM posts p
			LEFT JOIN post_coauthors pcb
				ON pcb.post_id = p.post_id AND pcb.buddy_session_id = ANY($2::text[])
			WHERE (p.buddy_session_id = ANY($2::text[]) OR pcb.buddy_session_id = ANY($2::text[]))
				AND ${DIRECT_POST_ACCESS_SQL}
		)
		SELECT DISTINCT ON (buddy_session_id) buddy_session_id, post_id
		FROM linked
		ORDER BY buddy_session_id, created_at ASC`,
    [viewerId, ids],
  );
  return new Map(rows.map((r) => [r.buddy_session_id, r.post_id]));
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
  /** Crew members with a photo on the card (the author's counts unless it's
   *  an auto card) and how many were on the walk — "2 of 4 photos added". */
  photo_count: number;
  crew_size: number;
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
					)) AS am_i_credited,
					-- The card's photo tally: the author's own picture (an auto card
					-- is a rendered route, not a photo) plus every crew slide.
					((CASE WHEN COALESCE(p.is_auto, false) THEN 0 ELSE 1 END) + (
						SELECT COUNT(*)::int FROM post_coauthors pcp
						WHERE pcp.post_id = p.post_id AND pcp.status = 'accepted'
							AND pcp.media_url IS NOT NULL AND pcp.media_url <> ''
					)) AS photo_count,
					(SELECT COUNT(*)::int FROM buddy_session_participants bsp
					  WHERE bsp.session_id = $1 AND bsp.status IN ('active', 'finished')) AS crew_size
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
  caption: string | null = null,
  /**
   * FRONT & BACK twin of this slide, already validated by the controller.
   * Written UNCONDITIONALLY (not COALESCEd) for the same reason the author's
   * is: re-adding replaces the slide, and a single shot replacing a dual must
   * take the swapped frame with it rather than leave a flip to the old photo.
   */
  dualMediaUrl: string | null = null,
  /** Which corner this slide's inset was baked into; same wholesale rule. */
  dualInsetCorner: string | null = null,
): Promise<boolean> {
  const rows = await db.query<{ post_id: string }>(
    `UPDATE post_coauthors
				SET media_url = $3, photo_added_at = NOW(), caption = $4,
					dual_media_url = $5, dual_inset_corner = $6
			WHERE post_id = $1 AND user_id = $2 AND status = 'accepted'
				AND EXISTS (
					SELECT 1 FROM posts p
					WHERE p.post_id = $1 AND p.deleted_at IS NULL AND p.share_to_feed
				)
			RETURNING post_id`,
    [
      postId,
      userId,
      stripMediaQuery(mediaUrl),
      caption,
      dualMediaUrl ? stripMediaQuery(dualMediaUrl) : null,
      dualInsetCorner,
    ],
  );
  return rows.length > 0;
}

/**
 * Edit the caption on YOUR OWN slide of a shared post, without re-sending the
 * photo.
 *
 * The author has had this since captions existed (`updatePost`); a credited
 * participant had no equivalent, so their only way to put words under their
 * own picture was to have typed them in the composer at the moment they added
 * it — and everyone who added a photo before per-slide captions shipped, or
 * who simply didn't write one, was left with a slide that could never carry
 * their voice. The card then falls back to nothing under their photo, which
 * reads as the app having lost what they wrote.
 *
 * Deliberately NOT behind the posting window. That gate exists because a
 * PHOTO is reaching the feed; the picture here is already on the card and is
 * not touched. Charging words the camera's ten minutes would mean a caption
 * can only ever be written in the same ten minutes as the walk, which is the
 * thing being fixed. Same membership rule as `addCrewPhoto`, and it only
 * matches a row that HAS a slide — there is nothing to caption otherwise.
 */
export async function setCrewCaption(
  postId: string,
  userId: string,
  caption: string | null,
): Promise<boolean> {
  const rows = await db.query<{ post_id: string }>(
    `UPDATE post_coauthors
				SET caption = $3
			WHERE post_id = $1 AND user_id = $2 AND status = 'accepted'
				AND media_url IS NOT NULL
				AND EXISTS (
					SELECT 1 FROM posts p
					WHERE p.post_id = $1 AND p.deleted_at IS NULL AND p.share_to_feed
				)
			RETURNING post_id`,
    [postId, userId, caption],
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
        -- ...and not to somebody who ALREADY shared this walk themselves.
        -- Before the create-time guard existed, a second card for the same
        -- walk was reachable through any composer door that didn't know about
        -- buddy sessions, and this sweep then pushed "1 photo so far" at the
        -- person who had just posted the other one. The guard stops new
        -- duplicates; this stops the nudge nagging about the ones already out
        -- there, and covers the case where their own card is the auto route
        -- card rather than a photo.
        AND NOT EXISTS (
          SELECT 1
            FROM buddy_session_participants own
            JOIN posts mine
              ON mine.user_id = pca.user_id
             AND mine.deleted_at IS NULL
             AND mine.share_to_feed
             AND mine.workout_id = own.workout_id
           WHERE own.session_id = pca.buddy_session_id
             AND own.user_id = pca.user_id
             AND own.workout_id IS NOT NULL
        )
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
