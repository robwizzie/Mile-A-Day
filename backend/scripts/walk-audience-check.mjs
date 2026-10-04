/**
 * Walk audience — the photo prompt's "who sees this walk" choice.
 *
 * Two additive server pieces back it, both NULL/absent for every shipped
 * client, so nothing about an existing install moves:
 *
 *   A. posts.on_profile — the AUTHOR's per-post grid choice.
 *        - FALSE keeps a post off the author's Posts grid (auto card OR photo)
 *          while it still reaches friends' feeds exactly as before;
 *        - TRUE puts a photo-less auto card on the grid even when the account's
 *          `auto_posts_on_profile` (photo-first grid) would hide it;
 *        - NULL follows the account rules (the control).
 *
 *   B. workout_feed_hides — "Off the feed" for ONE walk.
 *        - the raw workout card leaves friends' unified feed, the legacy feed
 *          and direct card access; the owner still sees it;
 *        - the row can be written BEFORE the workout has synced (the prompt
 *          opens the moment the walk ends), and clearing it restores the card;
 *        - a sibling walk the user didn't hide is untouched.
 *
 * Usage (same env as ci-smoke):  DATABASE_URL=... node scripts/walk-audience-check.mjs
 */
import fs from "node:fs";
import path from "node:path";
import express from "express";
import { PostgresService } from "../dist/services/DbService.js";
import { authenticateToken } from "../dist/middleware/auth.js";
import postsRoutes from "../dist/routes/postsRoutes.js";
import workoutRoutes from "../dist/routes/workoutRoutes.js";
import { generateAccessToken } from "../dist/services/tokenService.js";
import {
  getUnifiedFeed,
  getUserPosts,
  visibleWorkoutAuthor,
} from "../dist/services/postService.js";
import { getFriendsWorkoutFeed } from "../dist/services/friendshipService.js";

const db = PostgresService.getInstance();

const AUTHOR = "wac-author";
const FRIEND = "wac-friend";
const ALL = [AUTHOR, FRIEND];
const TODAY = new Date().toISOString().slice(0, 10);

// One workout per post: one-post-per-workout is a server rule.
const W_AUTO_OFF = "wac-w-auto-off"; // auto card, on_profile false
const W_AUTO_ON = "wac-w-auto-on"; // auto card, on_profile true (grid photo-first ON)
const W_AUTO_NULL = "wac-w-auto-null"; // auto card, no choice (control)
const W_PHOTO_OFF = "wac-w-photo-off"; // photo post, on_profile false
const W_HIDE = "wac-w-hide"; // raw card, kept off the feed
const W_SHOW = "wac-w-show"; // raw card, sibling the user didn't hide
const W_UNSYNCED = "wac-w-not-synced-yet";
const WORKOUTS = [
  W_AUTO_OFF,
  W_AUTO_ON,
  W_AUTO_NULL,
  W_PHOTO_OFF,
  W_HIDE,
  W_SHOW,
];

let failures = 0;
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (!ok) failures++;
  console.log(
    `${ok ? "ok  " : "FAIL"}  ${label} → ${JSON.stringify(actual)}${ok ? "" : ` (expected ${JSON.stringify(expected)})`}`,
  );
}

const MEDIA_DIR = path.join(process.cwd(), "uploads", "posts");
const made = [];
function mediaFor(userId) {
  fs.mkdirSync(MEDIA_DIR, { recursive: true });
  const name = `${userId}-wac-${Date.now()}-${made.length}.jpg`;
  fs.writeFileSync(path.join(MEDIA_DIR, name), "x");
  made.push(name);
  return `/uploads/posts/${name}`;
}

async function cleanup() {
  // Post creation fires notifications fire-and-forget; let them land before
  // deleting the users their inbox rows point at.
  await new Promise((r) => setTimeout(r, 800));
  await db.query(
    `DELETE FROM in_app_notifications WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(
    `DELETE FROM pending_friend_notifications WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(`DELETE FROM posts WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(
    `DELETE FROM workout_feed_hides WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(`DELETE FROM workouts WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM friendships WHERE user_id = ANY($1::text[])`, [
    ALL,
  ]);
  await db.query(
    `DELETE FROM notification_settings WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(`DELETE FROM users WHERE user_id = ANY($1::text[])`, [ALL]);
  for (const name of made.splice(0)) {
    try {
      fs.unlinkSync(path.join(MEDIA_DIR, name));
    } catch {
      /* gone */
    }
  }
}

async function seed() {
  await cleanup();
  for (const id of ALL) {
    await db.query(
      `INSERT INTO users (user_id, apple_sub, email, username, first_name, goal_miles, terms_accepted_at)
       VALUES ($1, $2, $3, $4, $4, 1, NOW())`,
      [id, `sub-${id}`, `${id}@example.com`, id],
    );
  }
  // The AUTHOR curates a photo-first grid: photo-less route cards stay off it
  // unless a per-post choice says otherwise. That's the setting the TRUE case
  // has to beat, and the NULL control has to obey.
  await db.query(
    `INSERT INTO notification_settings (user_id, auto_posts_on_profile, route_privacy_meters)
     VALUES ($1, false, 0)`,
    [AUTHOR],
  );
  for (const [a, b] of [
    [AUTHOR, FRIEND],
    [FRIEND, AUTHOR],
  ]) {
    await db.query(
      `INSERT INTO friendships (user_id, friend_id, status) VALUES ($1, $2, 'accepted')`,
      [a, b],
    );
  }
  // Aged past the 10-minute camera hold on BOTH anchors (device_end_date and
  // created_at), or the feed's hold suppresses every friend-side card anyway
  // and the hide assertions pass vacuously.
  for (const [i, id] of WORKOUTS.entries()) {
    await db.query(
      `INSERT INTO workouts (workout_id, user_id, workout_type, distance, total_duration,
          calories, date, local_date, device_end_date, created_at, source, feed_role, timezone_offset)
       VALUES ($1, $2, 'walking', 1.1, 1500, 0, $3::date, $3::date,
               NOW() - ($4 || ' minutes')::interval, NOW() - ($4 || ' minutes')::interval,
               'healthkit', 'extra', 0)`,
      [id, AUTHOR, TODAY, String(30 + i * 5)],
    );
  }
}

const app = express();
app.use(express.json({ limit: "2mb" }));
app.use(authenticateToken);
app.use("/posts", postsRoutes);
app.use("/workouts", workoutRoutes);
const server = await new Promise((resolve) => {
  const s = app.listen(0, "127.0.0.1", () => resolve(s));
});
const base = `http://127.0.0.1:${server.address().port}`;

async function call(method, p, userId, body) {
  const token = await generateAccessToken(userId);
  const res = await fetch(base + p, {
    method,
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${token}`,
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  let json = null;
  try {
    json = await res.json();
  } catch {}
  return { status: res.status, json };
}

const stats = {
  distance: 1.1,
  pace: "22:43",
  duration: 1500,
  streak: 1,
  date: TODAY,
};

async function autoPost(workoutId, onProfile) {
  const body = {
    workout_id: workoutId,
    share_to_feed: true,
    share_to_story: false,
    stats_snapshot: stats,
    is_auto: true,
  };
  if (onProfile !== undefined) body.on_profile = onProfile;
  return call("POST", "/posts", AUTHOR, body);
}

const feedHasPost = (feed, postId) =>
  feed.some((e) => e.kind === "post" && e.id === postId);
const feedHasWorkout = (feed, workoutId) =>
  feed.some(
    (e) =>
      e.kind === "workout" &&
      (e.workout_id === workoutId || e.id === workoutId),
  );

try {
  await seed();

  // ── A. posts.on_profile
  const off = await autoPost(W_AUTO_OFF, false);
  check("auto card with on_profile:false is accepted", off.status, 201);
  const on = await autoPost(W_AUTO_ON, true);
  check("auto card with on_profile:true is accepted", on.status, 201);
  const ctl = await autoPost(W_AUTO_NULL, undefined);
  check("auto card with no choice is accepted", ctl.status, 201);
  const photo = await call("POST", "/posts", AUTHOR, {
    media_url: mediaFor(AUTHOR),
    workout_id: W_PHOTO_OFF,
    share_to_feed: true,
    share_to_story: false,
    stats_snapshot: stats,
    is_auto: false,
    photo_source: "library",
    on_profile: false,
  });
  check("photo post with on_profile:false is accepted", photo.status, 201);

  const stored = await db.query(
    `SELECT workout_id, on_profile FROM posts WHERE user_id = $1 ORDER BY workout_id`,
    [AUTHOR],
  );
  check(
    "on_profile is stored as sent, NULL when absent",
    stored.map((r) => [r.workout_id, r.on_profile]),
    [
      [W_AUTO_NULL, null],
      [W_AUTO_OFF, false],
      [W_AUTO_ON, true],
      [W_PHOTO_OFF, false],
    ],
  );

  for (const viewer of [AUTHOR, FRIEND]) {
    const grid = await getUserPosts(viewer, AUTHOR, 50);
    const ids = new Set(grid.map((p) => p.post_id));
    const who = viewer === AUTHOR ? "own" : "friend's view of";
    check(
      `${who} grid: on_profile:false auto card is off it`,
      ids.has(off.json?.post_id),
      false,
    );
    check(
      `${who} grid: on_profile:false PHOTO post is off it`,
      ids.has(photo.json?.post_id),
      false,
    );
    check(
      `${who} grid: on_profile:true beats the photo-first setting`,
      ids.has(on.json?.post_id),
      true,
    );
    check(
      `${who} grid: no choice still follows photo-first (control)`,
      ids.has(ctl.json?.post_id),
      false,
    );
  }

  // Grid-ONLY: the friend's feed carries all four posts regardless.
  let friendFeed = await getUnifiedFeed(FRIEND, 50);
  check(
    "friend's feed still carries every post (on_profile never touches reach)",
    [off, on, ctl, photo].map((r) => feedHasPost(friendFeed, r.json?.post_id)),
    [true, true, true, true],
  );

  // A photo replacing a hidden auto card in place takes the NEW choice — an
  // inherited FALSE would hide the photo the user just shared.
  const replace = await call("POST", "/posts", AUTHOR, {
    media_url: mediaFor(AUTHOR),
    workout_id: W_AUTO_OFF,
    share_to_feed: true,
    share_to_story: false,
    stats_snapshot: stats,
    is_auto: false,
    photo_source: "library",
  });
  check("a photo replaces the hidden auto card", replace.status, 201);
  const [replaced] = await db.query(
    `SELECT on_profile, is_auto FROM posts
      WHERE user_id = $1 AND workout_id = $2 AND deleted_at IS NULL`,
    [AUTHOR, W_AUTO_OFF],
  );
  check(
    "…and does not inherit its on_profile:false",
    [replaced?.is_auto, replaced?.on_profile],
    [false, null],
  );
  const gridAfter = new Set(
    (await getUserPosts(FRIEND, AUTHOR, 50)).map((p) => p.post_id),
  );
  check(
    "…so the photo is on the grid",
    gridAfter.has(replace.json?.post_id),
    true,
  );

  // ── B. workout_feed_hides
  friendFeed = await getUnifiedFeed(FRIEND, 50);
  check(
    "before hiding, the friend sees both raw cards (seed is past the hold)",
    [feedHasWorkout(friendFeed, W_HIDE), feedHasWorkout(friendFeed, W_SHOW)],
    [true, true],
  );

  let r = await call(
    "PUT",
    `/workouts/${AUTHOR}/workout/${W_HIDE}/feed-hidden`,
    AUTHOR,
    {
      hidden: true,
    },
  );
  check(
    "owner can keep one walk off the feed",
    [r.status, r.json?.hidden],
    [200, true],
  );
  r = await call(
    "PUT",
    `/workouts/${AUTHOR}/workout/${W_HIDE}/feed-hidden`,
    AUTHOR,
    {
      hidden: true,
    },
  );
  check("…idempotently", r.status, 200);

  friendFeed = await getUnifiedFeed(FRIEND, 50);
  check(
    "friend's unified feed: the hidden walk is gone",
    feedHasWorkout(friendFeed, W_HIDE),
    false,
  );
  check("…its sibling is untouched", feedHasWorkout(friendFeed, W_SHOW), true);
  const ownFeed = await getUnifiedFeed(AUTHOR, 50);
  check(
    "owner's own feed still shows it",
    feedHasWorkout(ownFeed, W_HIDE),
    true,
  );

  const legacy = await getFriendsWorkoutFeed(FRIEND);
  check(
    "legacy feed honours it too",
    [
      legacy.some((w) => w.workout_id === W_HIDE),
      legacy.some((w) => w.workout_id === W_SHOW),
    ],
    [false, true],
  );
  check(
    "direct card access: friend can't reach it",
    await visibleWorkoutAuthor(FRIEND, W_HIDE),
    null,
  );
  check("…the owner can", await visibleWorkoutAuthor(AUTHOR, W_HIDE), AUTHOR);
  check(
    "…and the sibling stays reachable",
    await visibleWorkoutAuthor(FRIEND, W_SHOW),
    AUTHOR,
  );

  // Before sync: the prompt usually opens before the phone has uploaded.
  r = await call(
    "PUT",
    `/workouts/${AUTHOR}/workout/${W_UNSYNCED}/feed-hidden`,
    AUTHOR,
    {
      hidden: true,
    },
  );
  check("a walk that hasn't synced yet can be hidden", r.status, 200);

  // Self-only, validated.
  r = await call(
    "PUT",
    `/workouts/${AUTHOR}/workout/${W_SHOW}/feed-hidden`,
    FRIEND,
    {
      hidden: true,
    },
  );
  check("nobody else can hide your walk", r.status, 403);
  r = await call(
    "PUT",
    `/workouts/${AUTHOR}/workout/${W_SHOW}/feed-hidden`,
    AUTHOR,
    {
      hidden: "yes",
    },
  );
  check("hidden must be a boolean", r.status, 400);

  // Reversible.
  r = await call(
    "PUT",
    `/workouts/${AUTHOR}/workout/${W_HIDE}/feed-hidden`,
    AUTHOR,
    {
      hidden: false,
    },
  );
  check("un-hiding answers false", [r.status, r.json?.hidden], [200, false]);
  friendFeed = await getUnifiedFeed(FRIEND, 50);
  check(
    "…and the card is back in the friend's feed",
    feedHasWorkout(friendFeed, W_HIDE),
    true,
  );
} catch (e) {
  failures++;
  console.error("FAIL  threw:", e);
} finally {
  await cleanup();
  server.close();
}

if (failures) {
  console.error(`\n${failures} walk-audience check(s) FAILED`);
  process.exit(1);
}
console.log("\nwalk-audience checks passed");
process.exit(0);
