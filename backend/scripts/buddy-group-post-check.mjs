/**
 * Buddy group post check — one walk, one post, everyone on it.
 *
 * A buddy walk used to produce one post PER PERSON. "Has this walk been
 * shared?" was answered from a list in the poster's own UserDefaults, which by
 * construction cannot see what a friend did on their phone, so every
 * participant's recap lit its Post CTA, everyone posted, and one hour of
 * walking filled the feed with N cards that each credited the others and each
 * carried a fraction of the pictures.
 *
 * The fix is server-side truth (`buddySessionPost`) plus a place for everyone
 * else's photo to go (`addCrewPhoto`, `coauthors[].media_url`) and everyone
 * else's route to be drawn from (`coauthors[].route`). Every one of those can
 * fail SILENTLY — a missing route reads as "they walked indoors", a leaked one
 * reads as nothing at all until the person who opted out notices their map on
 * a friend's feed — so none of it is safe to verify by reading the SQL.
 *
 * Covers, against a real migrated database:
 *   1. buddySessionPost answers for EVERY participant, not just the author,
 *      and reports whether the caller's own photo is on it yet
 *   2. addCrewPhoto accepts an accepted participant, and refuses a stranger,
 *      a declined participant, and a deleted post
 *   3. re-adding REPLACES a participant's slide rather than adding a second
 *   4. the feed payload carries each participant's photo AND route
 *   5. a participant who turned "Share route maps" off is withheld — while the
 *      author's own route on the same card is not
 *   6. the poster's per-post "no map" choice suppresses the WHOLE crew's routes
 *   7. lockUnearnedPhotos blanks the crew's photos for a viewer who hasn't run,
 *      keeps their own, and leaves the card unlocked once they have
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/buddy-group-post-check.mjs
 */
import { PostgresService } from "../dist/services/DbService.js";
import {
  addCrewPhoto,
  buddySessionPost,
  getUnifiedFeed,
  lockUnearnedPhotos,
  sweepCrewPhotoNudges,
} from "../dist/services/postService.js";
import {
  joinSession,
  leaveSession,
} from "../dist/services/buddySessionService.js";

const db = PostgresService.getInstance();

const AUTHOR = "grp-author";
const PAL = "grp-pal"; // credited, shares routes
const SHY = "grp-shy"; // credited, route maps OFF
const OUT = "grp-out"; // friend of author, never on the walk
const ALL = [AUTHOR, PAL, SHY, OUT];

let failures = 0;
function check(label, actual, expected) {
  const ok = actual === expected;
  if (!ok) failures++;
  console.log(
    `${ok ? "ok  " : "FAIL"}  ${label} → ${actual} (expected ${expected})`,
  );
}

async function seed() {
  for (const id of ALL) {
    await db.query(
      `INSERT INTO users (user_id, apple_sub, email, username, first_name, last_name)
       VALUES ($1, $2, $3, $4, $5, 'Walker')
       ON CONFLICT (user_id) DO NOTHING`,
      [id, `sub-${id}`, `${id}@example.com`, id, id],
    );
  }
  // Everyone is an accepted friend of everyone — the point of this check is
  // the buddy-post rules, so nothing must fail for an unrelated circle reason.
  for (const a of ALL) {
    for (const b of ALL) {
      if (a === b) continue;
      await db.query(
        `INSERT INTO friendships (user_id, friend_id, status) VALUES ($1, $2, 'accepted')
         ON CONFLICT (user_id, friend_id) DO NOTHING`,
        [a, b],
      );
    }
  }
  // SHY opted out of publishing GPS traces. The author and PAL have no
  // settings row at all, which is the DEFAULT case and must read as consent
  // (COALESCE(..., true)) — a missing row silently withholding every route is
  // exactly the kind of failure this file exists to catch.
  await db.query(
    `INSERT INTO notification_settings (user_id, share_route_maps)
     VALUES ($1, FALSE)
     ON CONFLICT (user_id) DO UPDATE SET share_route_maps = FALSE`,
    [SHY],
  );
}

async function cleanup() {
  // FIRST, and not optional: `joinSession` notifies the host, and `sendPush`
  // writes an in-app row even when it has no device to deliver to. Leaving
  // those behind makes the NEXT run fail on the users FK rather than on
  // anything it was testing — which is how a check starts looking flaky.
  await db.query(
    `DELETE FROM in_app_notifications WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(`DELETE FROM workout_routes WHERE workout_id LIKE 'grp-w-%'`);
  await db.query(`DELETE FROM post_coauthors WHERE user_id = ANY($1::text[])`, [
    ALL,
  ]);
  await db.query(`DELETE FROM posts WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM workouts WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(
    `DELETE FROM buddy_session_participants WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(
    `DELETE FROM buddy_sessions WHERE host_user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(
    `DELETE FROM notification_settings WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(
    `DELETE FROM friendships WHERE user_id = ANY($1::text[]) OR friend_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(`DELETE FROM users WHERE user_id = ANY($1::text[])`, [ALL]);
}

/** One walk, one workout per person, one GPS trace per workout. */
async function seedWalk() {
  const rows = await db.query(
    `INSERT INTO buddy_sessions
       (join_code, host_user_id, mode, activity_type, status, origin,
        local_date, started_at, ended_at)
     VALUES ('grpwlk', $1, 'together', 'walking', 'completed', 'invite',
             CURRENT_DATE, NOW() - INTERVAL '1 hour', NOW() - INTERVAL '20 minutes')
     RETURNING id`,
    [AUTHOR],
  );
  const sessionId = rows[0].id;

  for (const id of [AUTHOR, PAL, SHY]) {
    const workoutId = `grp-w-${id}`;
    await db.query(
      `INSERT INTO workouts
         (workout_id, user_id, workout_type, distance, total_duration,
          device_end_date, date, local_date, timezone_offset, calories, steps,
          feed_role)
       VALUES ($1, $2, 'walking', 1.4, 2400, NOW() - INTERVAL '20 minutes',
               CURRENT_DATE, CURRENT_DATE, 0, 120, 3000, 'daily_mile')
       ON CONFLICT (workout_id) DO NOTHING`,
      [workoutId, id],
    );
    await db.query(
      `INSERT INTO workout_routes (workout_id, route, point_count)
       VALUES ($1, $2::jsonb, 3)
       ON CONFLICT (workout_id) DO UPDATE SET route = EXCLUDED.route`,
      [
        workoutId,
        JSON.stringify([
          [40.1, -74.1],
          [40.2, -74.2],
          [40.3, -74.3],
        ]),
      ],
    );
    // The reconciler stamps workout_id on the participant row once that
    // person's HKWorkout syncs. Crew routes resolve THROUGH this rather than
    // through a column frozen at post time, which is the only reason a friend
    // who finishes after the post still gets a line on the map.
    await db.query(
      `INSERT INTO buddy_session_participants
         (session_id, user_id, status, workout_id, final_distance_miles, duration_seconds)
       VALUES ($1, $2, 'finished', $3, 1.4, 2400)`,
      [sessionId, id, workoutId],
    );
  }
  return sessionId;
}

/** The post exactly as the recap wizard writes it: crew rows + session link. */
async function seedGroupPost(sessionId, { includeRoute = true } = {}) {
  const rows = await db.query(
    `INSERT INTO posts (user_id, media_url, caption, workout_id, local_date,
                        share_to_feed, is_auto, include_route, buddy_session_id,
                        coauthor_user_id, coauthor_status)
     VALUES ($1, '/uploads/posts/grp-author-1.jpg', 'us, out there',
             'grp-w-grp-author', CURRENT_DATE, TRUE, FALSE, $2, $3, $4, 'accepted')
     RETURNING post_id`,
    [AUTHOR, includeRoute, sessionId, PAL],
  );
  const postId = rows[0].post_id;
  for (const id of [PAL, SHY]) {
    await db.query(
      `INSERT INTO post_coauthors (post_id, user_id, status, buddy_session_id)
       VALUES ($1, $2, 'accepted', $3)`,
      [postId, id, sessionId],
    );
  }
  return postId;
}

/** The whole feed card for `postId` as `viewer` sees it. */
async function crewCard(viewerId, postId) {
  const feed = await getUnifiedFeed(viewerId, 20, null);
  return feed.find((e) => e.kind === "post" && e.id === postId) ?? null;
}

/** The crew entry for `userId` on the first post of `viewer`'s unified feed. */
async function crewEntry(viewerId, postId, userId) {
  const feed = await getUnifiedFeed(viewerId, 20, null);
  // The unified feed projects a post's id as `id` (the entry id), not
  // `post_id` — that column carries the linked WORKOUT on these rows.
  const entry = feed.find((e) => e.kind === "post" && e.id === postId);
  return (entry?.coauthors ?? []).find((c) => c.user_id === userId) ?? null;
}

async function main() {
  await cleanup();
  await seed();
  const sessionId = await seedWalk();
  const postId = await seedGroupPost(sessionId);

  // ── 1. Server truth: every participant is told the walk is already up ──
  //
  // This is the assertion that stops the duplicate. PAL's phone has no local
  // record of the author's post, so if this comes back null PAL's recap lights
  // its CTA and the walk gets posted twice.
  const forAuthor = await buddySessionPost(sessionId, AUTHOR);
  check("author sees the walk's post", forAuthor?.post_id, postId);
  check("...and is credited on it", forAuthor?.am_i_credited, true);

  const forPal = await buddySessionPost(sessionId, PAL);
  check("a PARTICIPANT sees the same post", forPal?.post_id, postId);
  check("...is credited", forPal?.am_i_credited, true);
  check("...and has no photo on it yet", forPal?.my_photo_added, false);

  check(
    "an unknown session has no post",
    await buddySessionPost("deadbeef", AUTHOR),
    null,
  );

  // ── 2/3. Adding a slide ──
  check(
    "a credited participant may add their photo",
    await addCrewPhoto(postId, PAL, "/uploads/posts/grp-pal-1.jpg"),
    true,
  );
  check(
    "...which the session lookup now reports",
    (await buddySessionPost(sessionId, PAL))?.my_photo_added,
    true,
  );
  check(
    "someone who wasn't on the walk may not",
    await addCrewPhoto(postId, OUT, "/uploads/posts/grp-out-1.jpg"),
    false,
  );

  // Re-adding is an EDIT of your own slide. If this appended instead, a
  // participant who retook their photo would put two of themselves on the card.
  await addCrewPhoto(postId, PAL, "/uploads/posts/grp-pal-2.jpg");
  const palRows = await db.query(
    `SELECT media_url FROM post_coauthors WHERE post_id = $1 AND user_id = $2`,
    [postId, PAL],
  );
  check("re-adding replaces, never appends", palRows.length, 1);
  check(
    "...with the new photo",
    palRows[0]?.media_url,
    "/uploads/posts/grp-pal-2.jpg",
  );

  // A participant who removed themselves is no longer on the post and must
  // lose the ability to put pictures on it.
  await db.query(
    `UPDATE post_coauthors SET status = 'declined' WHERE post_id = $1 AND user_id = $2`,
    [postId, SHY],
  );
  check(
    "a participant who left may not add one",
    await addCrewPhoto(postId, SHY, "/uploads/posts/grp-shy-1.jpg"),
    false,
  );
  await db.query(
    `UPDATE post_coauthors SET status = 'accepted' WHERE post_id = $1 AND user_id = $2`,
    [postId, SHY],
  );

  // ── 4/5. The payload: everyone's photo, and only the routes they consented to ──
  const palEntry = await crewEntry(OUT, postId, PAL);
  check(
    "the feed carries a crew member's photo",
    palEntry?.media_url,
    "/uploads/posts/grp-pal-2.jpg",
  );
  check(
    "...and their route",
    Array.isArray(palEntry?.route) ? palEntry.route.length : null,
    3,
  );

  const shyEntry = await crewEntry(OUT, postId, SHY);
  check(
    "a crew member who shares no maps is withheld",
    shyEntry?.route ?? null,
    null,
  );
  check("...but is still credited on the post", shyEntry?.user_id, SHY);
  // The author's own route rides a different code path; a bug that withheld
  // the whole card's maps would otherwise pass every assertion above.
  const feedForOut = await getUnifiedFeed(OUT, 20, null);
  const card = feedForOut.find((e) => e.kind === "post" && e.id === postId);
  check(
    "the author's own route survives one member's opt-out",
    Array.isArray(card?.route) ? card.route.length : null,
    3,
  );
  // SHY always sees their own trace — same "you can always see your own" rule
  // the author's route obeys.
  check(
    "...and the opted-out member still sees their own",
    Array.isArray((await crewEntry(SHY, postId, SHY))?.route)
      ? "drawn"
      : "none",
    "drawn",
  );

  // ── 6. "No map on this one" covers the whole card, not just the poster ──
  await db.query(`UPDATE posts SET include_route = FALSE WHERE post_id = $1`, [
    postId,
  ]);
  check(
    "the poster's no-map choice withholds the crew's routes too",
    (await crewEntry(OUT, postId, PAL))?.route ?? null,
    null,
  );
  await db.query(`UPDATE posts SET include_route = TRUE WHERE post_id = $1`, [
    postId,
  ]);

  // ── 7. The earn-to-view gate covers the crew, not just the author ──
  //
  // Gating only `posts.media_url` would hand a viewer who hasn't run the crew's
  // three unearned photos on the very card the gate exists for.
  const gated = lockUnearnedPhotos(
    [
      {
        user_id: AUTHOR,
        local_date: new Date().toISOString().slice(0, 10),
        is_auto: false,
        media_url: "/uploads/posts/grp-author-1.jpg",
        coauthors: [
          { user_id: PAL, media_url: "/uploads/posts/grp-pal-2.jpg" },
          { user_id: OUT, media_url: "/uploads/posts/grp-out-1.jpg" },
        ],
      },
    ],
    OUT,
    { completed: false, localDate: new Date().toISOString().slice(0, 10) },
  );
  check("the author's photo is withheld", gated[0].media_url, "");
  check(
    "a crew member's photo is withheld too",
    gated[0].coauthors[0].media_url,
    "",
  );
  check(
    "...but the viewer's OWN slide survives",
    gated[0].coauthors[1].media_url,
    "/uploads/posts/grp-out-1.jpg",
  );
  check("and the card reads as locked", gated[0].photo_locked, true);

  const earned = lockUnearnedPhotos(
    [
      {
        user_id: AUTHOR,
        local_date: new Date().toISOString().slice(0, 10),
        is_auto: false,
        media_url: "/uploads/posts/grp-author-1.jpg",
        coauthors: [
          { user_id: PAL, media_url: "/uploads/posts/grp-pal-2.jpg" },
        ],
      },
    ],
    OUT,
    { completed: true, localDate: new Date().toISOString().slice(0, 10) },
  );
  check(
    "a viewer who ran today sees the crew's photos",
    earned[0].coauthors[0].media_url,
    "/uploads/posts/grp-pal-2.jpg",
  );

  // ── 8. The walk's combined figures ride the card ──
  //
  // "3.2 mi between us" is the number the recap headlines at hero size and the
  // post never showed, so a card about doing it together led with one person's
  // distance. Derived, so it must count the SAME membership every other buddy
  // surface counts and must prefer a reconciled figure over a live one.
  const grouped = await crewCard(OUT, postId);
  check(
    "the card carries the walk's crew size",
    grouped?.buddy_group?.crew_size,
    3,
  );
  check(
    "...and the combined distance",
    grouped?.buddy_group?.distance_miles,
    4.2,
  );
  // A solo post has no walk behind it and must not sprout a group line.
  const soloRows = await db.query(
    `INSERT INTO posts (user_id, media_url, local_date, share_to_feed, is_auto)
     VALUES ($1, '/uploads/posts/grp-author-solo.jpg', CURRENT_DATE, TRUE, FALSE)
     RETURNING post_id`,
    [AUTHOR],
  );
  check(
    "an ordinary post has no group line",
    (await crewCard(OUT, soloRows[0].post_id))?.buddy_group ?? null,
    null,
  );

  // ── 9. The hour-later nudge ──
  //
  // Fires roughly an hour after the walk, which is LONG after the ten-minute
  // camera window shut — so it is a camera-roll ask by construction, and the
  // one thing that must never happen is it firing twice.
  await db.query(
    `UPDATE buddy_sessions SET ended_at = NOW() - INTERVAL '2 hours'
      WHERE id = $1`,
    [sessionId],
  );
  // PAL already added a photo; SHY has not. Only SHY should be nudged.
  const firstSweep = await sweepCrewPhotoNudges();
  const claims = await db.query(
    `SELECT user_id FROM post_coauthors
      WHERE post_id = $1 AND photo_nudge_sent_at IS NOT NULL
      ORDER BY user_id`,
    [postId],
  );
  check(
    "only the participant with no photo is claimed",
    claims.map((r) => r.user_id).join(","),
    SHY,
  );
  // The push itself is suppressed (no device declares buddy_group_post_v1 in
  // this seed), which is exactly the gating being asserted — the CLAIM is what
  // proves the sweep selected correctly.
  check("...and no push reaches a legacy build", firstSweep, 0);
  // Re-running must find nothing. A cron on a 5-minute cadence that re-selects
  // the same row would send this every five minutes for six hours.
  await sweepCrewPhotoNudges();
  const claimsAfter = await db.query(
    `SELECT COUNT(*)::int AS n FROM post_coauthors
      WHERE post_id = $1 AND photo_nudge_sent_at IS NOT NULL`,
    [postId],
  );
  check("the nudge claim is once-only", claimsAfter[0].n, 1);

  // ── 10. Leave and rejoin mid-walk keeps your miles ──
  //
  // Stepping out of the group must never cost the distance already banked: the
  // participant row is the only record of it, and a rejoin that reset it would
  // silently take miles off someone who walked them.
  await db.query(
    `UPDATE buddy_sessions SET status = 'active', ended_at = NULL,
            started_at = NOW() - INTERVAL '30 minutes'
      WHERE id = $1`,
    [sessionId],
  );
  // BOTH still out. If PAL were the only active walker, their leaving would
  // (correctly) finalize the whole session and there would be nothing left to
  // rejoin — which is a different behaviour from the one under test here.
  await db.query(
    `UPDATE buddy_session_participants
        SET status = 'active', distance_miles = 0.73, duration_seconds = 900
      WHERE session_id = $1 AND user_id = ANY($2::text[])`,
    [sessionId, [PAL, AUTHOR]],
  );
  await leaveSession(sessionId, PAL);
  const afterLeave = await db.query(
    `SELECT status, distance_miles FROM buddy_session_participants
      WHERE session_id = $1 AND user_id = $2`,
    [sessionId, PAL],
  );
  check("leaving frees the slot", afterLeave[0]?.status, "left");
  check(
    "...without touching the miles already walked",
    Number(afterLeave[0]?.distance_miles),
    0.73,
  );
  await joinSession(PAL, { sessionId });
  const afterRejoin = await db.query(
    `SELECT status, distance_miles FROM buddy_session_participants
      WHERE session_id = $1 AND user_id = $2`,
    [sessionId, PAL],
  );
  // 'active', not 'joined': a running session has no lobby left to wait in,
  // and a 'joined' row is invisible to the roster, worth zero to the pooled
  // total, and unable to report a metre (backend.md).
  check(
    "rejoining a running walk lands active",
    afterRejoin[0]?.status,
    "active",
  );
  check(
    "...and picks up exactly where they left off",
    Number(afterRejoin[0]?.distance_miles),
    0.73,
  );

  if (!process.env.KEEP_SEED) await cleanup();

  console.log(
    failures === 0
      ? "buddy-group-post-check: all assertions passed"
      : `buddy-group-post-check: ${failures} FAILED`,
  );
  process.exit(failures === 0 ? 0 : 1);
}

main().catch(async (err) => {
  console.error(err);
  await cleanup().catch(() => {});
  process.exit(1);
});
