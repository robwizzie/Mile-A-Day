/**
 * Live auto cards — an auto post is DATA, never a picture.
 *
 * The app used to bake the walk's route/stats card into a JPEG on the phone,
 * upload it and post it as `media_url`. Current builds post the auto card
 * with NO image and draw it live from the workout, its route and the stats
 * snapshot. What must hold, through the real controller:
 *
 *   1. an auto post with no media_url is accepted and stored as '';
 *   2. a deliberate (non-auto) post with no media_url is still a 400;
 *   3. a viewer whose build draws live cards (`live_auto_card_v1`) sees
 *      `is_auto: true` — with the route AND the splits the live card draws;
 *   4. a viewer on an OLDER build sees the same row as an ordinary post
 *      (`is_auto: false`), which is the shape its existing code draws as the
 *      live route slide; the earn-to-view lock never fires on a missing photo;
 *   5. a BAKED auto card (real media) is served exactly as before to both;
 *   6. a real photo still replaces the live card in place (one card per walk).
 *
 * Usage (same env as ci-smoke):  DATABASE_URL=... node scripts/live-auto-card-check.mjs
 */
import fs from "node:fs";
import path from "node:path";
import express from "express";
import { PostgresService } from "../dist/services/DbService.js";
import { authenticateToken } from "../dist/middleware/auth.js";
import postsRoutes from "../dist/routes/postsRoutes.js";
import { generateAccessToken } from "../dist/services/tokenService.js";
import {
  getFeedEntryForPost,
  getUserPosts,
  lockUnearnedPhotos,
} from "../dist/services/postService.js";

const db = PostgresService.getInstance();

const AUTHOR = "lac-author";
const NEWV = "lac-new-viewer"; // declares live_auto_card_v1
const OLDV = "lac-old-viewer"; // a shipped build: no features
const ALL = [AUTHOR, NEWV, OLDV];
const TODAY = new Date().toISOString().slice(0, 10);
const WORKOUT = "lac-w-today";
const BAKED_WORKOUT = "lac-w-baked";

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
  const name = `${userId}-lac-${Date.now()}-${made.length}.jpg`;
  fs.writeFileSync(path.join(MEDIA_DIR, name), "x");
  made.push(name);
  return `/uploads/posts/${name}`;
}

async function cleanup() {
  await new Promise((r) => setTimeout(r, 800));
  await db.query(
    `DELETE FROM in_app_notifications WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(`DELETE FROM posts WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM workout_splits WHERE workout_id LIKE 'lac-w-%'`);
  await db.query(`DELETE FROM workout_routes WHERE workout_id LIKE 'lac-w-%'`);
  await db.query(`DELETE FROM workouts WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM device_tokens WHERE user_id = ANY($1::text[])`, [
    ALL,
  ]);
  await db.query(`DELETE FROM friendships WHERE user_id = ANY($1::text[])`, [
    ALL,
  ]);
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
  for (const v of [NEWV, OLDV]) {
    for (const [a, b] of [
      [AUTHOR, v],
      [v, AUTHOR],
    ]) {
      await db.query(
        `INSERT INTO friendships (user_id, friend_id, status) VALUES ($1, $2, 'accepted')`,
        [a, b],
      );
    }
  }
  await db.query(
    `INSERT INTO device_tokens (user_id, device_token, environment, client_features)
     VALUES ($1, 'lac-tok-author', 'sandbox', ARRAY['live_auto_card_v1']),
            ($2, 'lac-tok-new', 'sandbox', ARRAY['live_auto_card_v1']),
            ($3, 'lac-tok-old', 'sandbox', ARRAY[]::text[])`,
    [AUTHOR, NEWV, OLDV],
  );
  for (const [id, minutes] of [
    [WORKOUT, 30],
    [BAKED_WORKOUT, 90],
  ]) {
    await db.query(
      `INSERT INTO workouts (workout_id, user_id, workout_type, distance, total_duration,
          calories, date, local_date, device_end_date, source, feed_role, timezone_offset)
       VALUES ($1, $2, 'walking', 1.2, 1500, 0, $3::date, $3::date,
               NOW() - ($4 || ' minutes')::interval, 'healthkit', 'extra', 0)`,
      [id, AUTHOR, TODAY, String(minutes)],
    );
    await db.query(
      `INSERT INTO workout_routes (workout_id, route, point_count) VALUES ($1, $2::jsonb, 3)`,
      [
        id,
        JSON.stringify([
          [39.85, -75.05],
          [39.851, -75.051],
          [39.852, -75.052],
        ]),
      ],
    );
    await db.query(
      `INSERT INTO workout_splits (workout_id, split_number, split_duration, split_distance, split_pace)
       VALUES ($1, 1, 1200, 1.0, 1200)`,
      [id],
    );
  }
}

const app = express();
app.use(express.json({ limit: "2mb" }));
app.use(authenticateToken);
app.use("/posts", postsRoutes);
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
  distance: 1.2,
  pace: "20:50",
  duration: 1500,
  streak: 1,
  date: TODAY,
};

try {
  await seed();

  // ── 1. The live card: no image at all.
  let r = await call("POST", "/posts", AUTHOR, {
    workout_id: WORKOUT,
    share_to_feed: true,
    share_to_story: false,
    stats_snapshot: stats,
    is_auto: true,
  });
  check("an auto post with no media is accepted", r.status, 201);
  const liveId = r.json?.post_id;
  const stored = (
    await db.query(`SELECT media_url, is_auto FROM posts WHERE post_id = $1`, [
      liveId,
    ])
  )[0];
  check(
    "…and stored as '' — nothing uploaded, nothing hosted",
    [stored?.media_url, stored?.is_auto],
    ["", true],
  );
  check(
    "…the author's own build is told it's an auto card",
    r.json?.is_auto,
    true,
  );

  // ── 2. Only AUTO cards may omit the picture.
  r = await call("POST", "/posts", AUTHOR, {
    workout_id: BAKED_WORKOUT,
    share_to_feed: true,
    share_to_story: false,
    stats_snapshot: stats,
    is_auto: false,
  });
  check("a deliberate post with no media is still refused", r.status, 400);

  // ── 3. A live-card build: flagged auto, with everything it draws.
  const forNew = await getFeedEntryForPost(NEWV, liveId);
  check("live-card viewer sees is_auto", forNew?.is_auto, true);
  check(
    "…with the route to draw",
    Array.isArray(forNew?.route) ? forNew.route.length : null,
    3,
  );
  check(
    "…and the splits for the pace wave",
    Array.isArray(forNew?.splits) ? forNew.splits.length : null,
    1,
  );

  // ── 4. An older build: the same row, served as an ordinary post.
  const forOld = await getFeedEntryForPost(OLDV, liveId);
  check("older viewer sees it as an ordinary post", forOld?.is_auto, false);
  check(
    "…with the route its live slide draws",
    Array.isArray(forOld?.route) ? forOld.route.length : null,
    3,
  );
  const [locked] = lockUnearnedPhotos([{ ...forOld, local_date: TODAY }], OLDV, { completed: false, localDate: TODAY });
  check(
    "…and no earn-to-view lock over a photo that doesn't exist",
    locked?.photo_locked ?? false,
    false,
  );
  const gridOld = (await getUserPosts(OLDV, AUTHOR, 20)).find(
    (p) => p.post_id === liveId,
  );
  const gridNew = (await getUserPosts(NEWV, AUTHOR, 20)).find(
    (p) => p.post_id === liveId,
  );
  check(
    "grid reads follow the same rule",
    [gridNew?.is_auto, gridOld?.is_auto],
    [true, false],
  );

  // ── 5. A BAKED auto card is untouched for everyone.
  const baked = mediaFor(AUTHOR);
  r = await call("POST", "/posts", AUTHOR, {
    media_url: baked,
    workout_id: BAKED_WORKOUT,
    share_to_feed: true,
    share_to_story: false,
    stats_snapshot: stats,
    is_auto: true,
  });
  check("an old build's baked auto card still posts", r.status, 201);
  const bakedId = r.json?.post_id;
  check(
    "…and reads as auto for both builds",
    [
      (await getFeedEntryForPost(NEWV, bakedId))?.is_auto,
      (await getFeedEntryForPost(OLDV, bakedId))?.is_auto,
    ],
    [true, true],
  );

  // ── 6. A real photo still replaces the live card, in place.
  r = await call("POST", "/posts", AUTHOR, {
    media_url: mediaFor(AUTHOR),
    workout_id: WORKOUT,
    share_to_feed: true,
    share_to_story: false,
    stats_snapshot: stats,
    is_auto: false,
    caption: "the real one",
  });
  check("a photo replaces the live card", r.status, 201);
  const rows = await db.query(
    `SELECT post_id, is_auto, media_url <> '' AS has_media FROM posts
      WHERE workout_id = $1 AND deleted_at IS NULL AND share_to_feed`,
    [WORKOUT],
  );
  check(
    "…leaving ONE card for the walk, now a photo",
    rows.map((x) => [x.post_id === liveId, x.is_auto, x.has_media]),
    [[true, false, true]],
  );
} finally {
  await cleanup();
  server.close();
}

if (failures) {
  console.error(`\nlive-auto-card-check: ${failures} failure(s)`);
  process.exit(1);
}
console.log("\nlive-auto-card-check: all passed");
process.exit(0);
