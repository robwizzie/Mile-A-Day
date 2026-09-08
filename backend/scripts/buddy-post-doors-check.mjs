/**
 * Buddy Walks — the post that stands for the walk, through every door.
 *
 * One four-person walk produced THREE cards in production, and each one was
 * a different silent failure:
 *
 *   1. The first finisher skipped the photo prompt. Their AUTO route card
 *      never carried the walk (auto posts stored no `buddy_session_id`), so
 *      the one-post-per-walk guard could not see it, and the next person's
 *      photo opened a second card beside it.
 *   2. Someone posted from the recap seconds after finishing, before
 *      HealthKit had published the walk — so the post had NO workout id, and
 *      the guard (keyed on the workout) skipped entirely: a third card, red
 *      (no workout type), routeless, never restated.
 *   3. Before that they were refused with `post_window_closed`: the window
 *      was measured from their own synced workout — which hadn't synced.
 *
 * And the routes: a participant links to their workout only when the workout
 * syncs AFTER their Finish tap, or when the whole session closes; the common
 * order (save → sync → Finish) left routes off the card until the slowest
 * walker was done.
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/buddy-post-doors-check.mjs
 */
import fs from "node:fs";
import path from "node:path";
import { PostgresService } from "../dist/services/DbService.js";
import {
  createSession,
  finishParticipation,
  joinSession,
  reconcileBuddySessions,
  startSession,
} from "../dist/services/buddySessionService.js";
import {
  addCrewPhoto,
  createPost,
  getFeedEntryForPost,
  getPostWindowStatus,
} from "../dist/services/postService.js";

const db = PostgresService.getInstance();

const HOST = "buddy-doors-host";
const EARLY = "buddy-doors-early"; // finishes first, skips the prompt → auto card
const LATE = "buddy-doors-late"; // posts from the recap with no workout id
const ALL = [HOST, EARLY, LATE];
const TODAY = new Date().toISOString().slice(0, 10);

let failures = 0;
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (!ok) failures++;
  console.log(
    `${ok ? "ok  " : "FAIL"}  ${label} → ${JSON.stringify(actual)} (expected ${JSON.stringify(expected)})`,
  );
}
async function errorCode(fn) {
  try {
    await fn();
    return null;
  } catch (error) {
    return error?.message ?? String(error);
  }
}

const MEDIA_DIR = path.join(process.cwd(), "uploads", "posts");
const made = [];
function mediaFor(userId) {
  fs.mkdirSync(MEDIA_DIR, { recursive: true });
  const name = `${userId}-doors-${Date.now()}-${made.length}.jpg`;
  fs.writeFileSync(path.join(MEDIA_DIR, name), "x");
  made.push(name);
  return `/uploads/posts/${name}`;
}

async function seed() {
  await cleanup();
  for (const id of ALL) {
    await db.query(
      `INSERT INTO users (user_id, apple_sub, email, username, first_name, last_name, goal_miles, terms_accepted_at)
       VALUES ($1, $2, $3, $4, $5, 'Doors', 1, NOW())
       ON CONFLICT (user_id) DO NOTHING`,
      [id, `sub-${id}`, `${id}@example.com`, id, id],
    );
  }
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
  await db.query(
    `UPDATE users SET buddy_enrolled_at = NOW() WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
}

async function cleanup() {
  // Pushes are fire-and-forget (`void sendPush(...)`) and each writes an
  // inbox row that holds a FK on users. Let the ones this run kicked off
  // land, then clear them — deleting users under a push still in flight
  // 23503s the teardown after every assertion has passed (it did, in CI).
  await new Promise((resolve) => setTimeout(resolve, 1500));
  await db.query(`DELETE FROM in_app_notifications WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(
    `DELETE FROM post_coauthors WHERE user_id = ANY($1::text[])
        OR post_id IN (SELECT post_id FROM posts WHERE user_id = ANY($1::text[]))`,
    [ALL],
  );
  await db.query(`DELETE FROM posts WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM workouts WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM buddy_session_participants WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM buddy_sessions WHERE host_user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM friendships WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM users WHERE user_id = ANY($1::text[])`, [ALL]);
  for (const name of made.splice(0)) {
    try { fs.unlinkSync(path.join(MEDIA_DIR, name)); } catch { /* gone */ }
  }
}

/** A counted workout inside the walk's window, with a route. */
async function syncedWalk(userId, workoutId, miles, minutesAgoEnd) {
  await db.query(
    `INSERT INTO workouts (workout_id, user_id, workout_type, distance, total_duration,
        calories, date, local_date, device_end_date, source, feed_role, timezone_offset)
     VALUES ($1, $2, 'walking', $3, 1800, 0, $4::date, $4::date,
             NOW() - ($5 || ' minutes')::interval, 'healthkit', 'daily_mile', 0)`,
    [workoutId, userId, miles, TODAY, String(minutesAgoEnd)],
  );
  await db.query(
    `INSERT INTO workout_routes (workout_id, route, point_count) VALUES ($1, $2::jsonb, 3)`,
    [workoutId, JSON.stringify([[39.85, -75.05], [39.851, -75.051], [39.852, -75.052]])],
  );
}

async function main() {
  await seed();

  // ── The walk: host + two friends, started forty minutes ago ────────────
  const created = await createSession(HOST, {
    mode: "together",
    activityType: "walking",
    inviteUserIds: [EARLY, LATE],
  });
  await joinSession(EARLY, { sessionId: created.id });
  await joinSession(LATE, { sessionId: created.id });
  await startSession(created.id, HOST);
  await db.query(
    `UPDATE buddy_sessions SET started_at = NOW() - INTERVAL '40 minutes' WHERE id = $1`,
    [created.id],
  );
  await db.query(
    `UPDATE buddy_session_participants SET distance_miles = 1.2, duration_seconds = 1500
      WHERE session_id = $1`,
    [created.id],
  );

  // ── 3. The window: a finisher whose walk hasn't synced ─────────────────
  await finishParticipation(created.id, LATE);
  const windowBeforeSync = await getPostWindowStatus(LATE, TODAY);
  check(
    "a finished walker has the day's photo window before their workout syncs",
    windowBeforeSync.photoOpen,
    true,
  );
  check(
    "...and the camera is OPEN while the walk is still live (the crew's still out)",
    windowBeforeSync.cameraOpen,
    true,
  );

  // ── 2. The recap post with NO workout id, then the guard ───────────────
  const latePost = await createPost({
    userId: LATE,
    mediaUrl: mediaFor(LATE),
    caption: "we did it",
    workoutId: null,
    statsSnapshot: { distance: 1.2 },
    localDate: TODAY,
    shareToFeed: true,
    shareToStory: false,
    isAuto: false,
    includeRoute: true,
    coauthorUserIds: [HOST, EARLY],
    buddySessionId: created.id,
  });
  check("a recap post made before the workout landed is created unlinked", latePost.workout_id ?? null, null);
  const sessionOf = async (postId) =>
    (await db.query(`SELECT buddy_session_id FROM posts WHERE post_id = $1`, [postId]))[0]
      ?.buddy_session_id ?? null;
  check("...but stamped with the walk", await sessionOf(latePost.post_id), created.id);

  // ── 4. Routes resolve before anyone is linked ──────────────────────────
  await syncedWalk(EARLY, "buddy-doors-early-w1", 1.3, 12);
  await reconcileBuddySessions(EARLY, ["buddy-doors-early-w1"]);
  let [earlyRow] = await db.query(
    `SELECT workout_id FROM buddy_session_participants WHERE session_id = $1 AND user_id = $2`,
    [created.id, EARLY],
  );
  check("a workout synced before Finish is not linked yet (the old order)", earlyRow.workout_id, null);
  const entry = await getFeedEntryForPost(HOST, latePost.post_id);
  const earlyOnCard = (entry?.coauthors ?? []).find((c) => c.user_id === EARLY);
  check(
    "...yet their route already draws on the walk's card (read-time overlap)",
    Array.isArray(earlyOnCard?.route) && earlyOnCard.route.length > 0,
    true,
  );

  await finishParticipation(created.id, EARLY);
  [earlyRow] = await db.query(
    `SELECT workout_id FROM buddy_session_participants WHERE session_id = $1 AND user_id = $2`,
    [created.id, EARLY],
  );
  check("...and Finish links it on the spot", earlyRow.workout_id, "buddy-doors-early-w1");

  // ── 2b. The unlinked post gets its workout once the walk syncs ─────────
  await syncedWalk(LATE, "buddy-doors-late-w1", 1.2, 8);
  await reconcileBuddySessions(LATE, ["buddy-doors-late-w1"]);
  const [latePostRow] = await db.query(`SELECT workout_id FROM posts WHERE post_id = $1`, [latePost.post_id]);
  check(
    "the recap post inherits the workout when it links (colour, route, restatement)",
    latePostRow.workout_id,
    "buddy-doors-late-w1",
  );

  // ── 1. The auto card of a buddy workout, and what replaces what ────────
  await db.query(`UPDATE posts SET deleted_at = NOW() WHERE post_id = $1`, [latePost.post_id]);

  const autoPost = await createPost({
    userId: EARLY,
    mediaUrl: mediaFor(EARLY),
    caption: null,
    workoutId: "buddy-doors-early-w1",
    statsSnapshot: { distance: 1.3 },
    localDate: TODAY,
    shareToFeed: true,
    shareToStory: false,
    isAuto: true,
    includeRoute: true,
  });
  check("an auto card resolves the walk it belongs to on its own", await sessionOf(autoPost.post_id), created.id);
  const autoEntry = await getFeedEntryForPost(HOST, autoPost.post_id);
  check(
    "...and credits the crew, so their routes draw on it",
    (autoEntry?.coauthors ?? []).map((c) => c.user_id).sort(),
    [HOST, LATE].sort(),
  );

  await syncedWalk(HOST, "buddy-doors-host-w1", 1.5, 3);
  check(
    "a second auto card for the same walk is refused",
    await errorCode(() =>
      createPost({
        userId: HOST,
        mediaUrl: mediaFor(HOST),
        caption: null,
        workoutId: "buddy-doors-host-w1",
        statsSnapshot: { distance: 1.5 },
        localDate: TODAY,
        shareToFeed: true,
        shareToStory: false,
        isAuto: true,
        includeRoute: true,
      }),
    ),
    "buddy_walk_already_posted",
  );

  const hostPost = await createPost({
    userId: HOST,
    mediaUrl: mediaFor(HOST),
    caption: "crew",
    workoutId: "buddy-doors-host-w1",
    statsSnapshot: { distance: 1.5 },
    localDate: TODAY,
    shareToFeed: true,
    shareToStory: false,
    isAuto: false,
    includeRoute: true,
    coauthorUserIds: [EARLY, LATE],
    buddySessionId: created.id,
  });
  const [autoAfter] = await db.query(`SELECT deleted_at FROM posts WHERE post_id = $1`, [autoPost.post_id]);
  check("a real photo of the walk retires the auto card", autoAfter.deleted_at !== null, true);
  check("...and is the walk's post", await sessionOf(hostPost.post_id), created.id);

  check(
    "a recap post with no workout id can no longer open a second card",
    await errorCode(() =>
      createPost({
        userId: LATE,
        mediaUrl: mediaFor(LATE),
        caption: "again",
        workoutId: null,
        statsSnapshot: { distance: 1.2 },
        localDate: TODAY,
        shareToFeed: true,
        shareToStory: false,
        isAuto: false,
        includeRoute: true,
        coauthorUserIds: [HOST, EARLY],
        buddySessionId: created.id,
      }),
    ),
    "buddy_walk_already_posted",
  );

  // ── Captions ride each slide ───────────────────────────────────────────
  const ok = await addCrewPhoto(hostPost.post_id, EARLY, mediaFor(EARLY), "my leg of it");
  check("a crew photo can carry its own caption", ok, true);
  const withCaption = await getFeedEntryForPost(LATE, hostPost.post_id);
  check(
    "...served under that person's slide",
    (withCaption?.coauthors ?? []).find((c) => c.user_id === EARLY)?.caption ?? null,
    "my leg of it",
  );

  // ── The window after the walk closes: ten minutes from the LAST finish ─
  await finishParticipation(created.id, HOST);
  const [sess] = await db.query(`SELECT status FROM buddy_sessions WHERE id = $1`, [created.id]);
  check("the walk closed on the last finish", sess.status, "completed");
  const windowAfter = await getPostWindowStatus(EARLY, TODAY);
  check(
    "the early finisher's camera is still open ten minutes after the LAST finish",
    windowAfter.cameraOpen,
    true,
  );

  await cleanup();
  console.log(
    failures === 0
      ? "buddy-post-doors-check: all assertions passed"
      : `buddy-post-doors-check: ${failures} FAILED`,
  );
  process.exit(failures === 0 ? 0 : 1);
}

main().catch(async (err) => {
  console.error(err);
  await cleanup().catch(() => {});
  process.exit(1);
});
