/**
 * Route privacy — "hide start & end".
 *
 * Every read that serves a stored route to someone other than its OWNER goes
 * through `servedRouteFrom` → `mad_route_view_bounds` (migration 0085), which trims
 * a jittered stretch off each end (the owner's route_privacy_meters, NULL =
 * 201 m), slices + re-bases the replay clock in lockstep, and serves NO route
 * at all when what's left would be a sliver. A read that forgets it leaks a
 * front door and nothing errors, so this pins, per surface:
 *   1. The owner gets the stored route byte-for-byte (route_trimmed false).
 *   2. A friend gets a contiguous inner slice on every surface (feed post arm,
 *      feed WORKOUT arm, single post, legacy feed, profile grid, the workout
 *      route detail) — identical across surfaces and across repeated reads —
 *      whose first/last points sit at least the minimum cut from the true
 *      start/end (straight line AND along the path), never more than the
 *      maximum jittered cut + one segment; altitude kept; times sliced 1:1,
 *      re-based to 0, started_at shifted by exactly the seconds cut.
 *   3. The setting applies at READ: Off → full route; 1 mile on a 1-mile walk
 *      → null; back to default → trimmed again, same cut as before.
 *   4. A short walk → NO route for a friend (route/times/started_at null).
 *   5. A crew line is trimmed by its OWNER's setting, not the poster's; the
 *      crew member themselves gets their own line in full.
 *   6. share_route_maps off and a stealth (route-less) walk stay null.
 *   7. Preferences: default served as 201, accepts an offered value, null
 *      returns to the default.
 * Sections 1–2 read on the COMPUTED path (privacy_bounds NULL, as for every
 * route stored before the feature); 2b fills the cache through the boot
 * backfill and asserts byte-identical reads, and 3–6 then run on the cache.
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/route-privacy-check.mjs
 */
import { PostgresService } from "../dist/services/DbService.js";
import {
  getUnifiedFeed,
  getFeed,
  getFeedEntryForPost,
  getUserPosts,
} from "../dist/services/postService.js";
import { getWorkoutRouteDetail } from "../dist/services/workoutService.js";
import {
  getNotificationPreferences,
  updateNotificationPreferences,
} from "../dist/services/notificationSettingsService.js";

import pg from "pg";
import {
  runRoutePrivacyBoundsBackfill,
  ROUTE_PRIVACY_BOUNDS_BACKFILL,
} from "../dist/db/backfillRoutePrivacyBounds.js";

const db = PostgresService.getInstance();

const OWNER = "rpc-owner"; // default setting (NULL ⇒ 201 m)
const FRIEND = "rpc-friend"; // the viewer
const CREW = "rpc-crew"; // credited on OWNER's buddy post, setting 402 m
const SHORTY = "rpc-short"; // a 400 m walk
const MAPSOFF = "rpc-mapsoff"; // share_route_maps = false
const ALL = [OWNER, FRIEND, CREW, SHORTY, MAPSOFF];

let failures = 0;
let passes = 0;
function check(label, actual, expected) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  const ok = a === e;
  if (ok) passes++;
  else failures++;
  console.log(
    `${ok ? "ok  " : "FAIL"}  ${label} → ${a.slice(0, 160)}${ok ? "" : ` (expected ${e.slice(0, 160)})`}`,
  );
}

// Same equirectangular metres the SQL (and the Swift mirror) use.
function geo(a, b) {
  const r = 0.017453292519943295;
  const k = Math.cos((a[0] + b[0]) * 0.5 * r);
  return (
    6371008.8 *
    Math.sqrt(((b[0] - a[0]) * r) ** 2 + ((b[1] - a[1]) * r * k) ** 2)
  );
}
function cumulative(pts) {
  const out = [0];
  for (let i = 1; i < pts.length; i++)
    out.push(out[i - 1] + geo(pts[i - 1], pts[i]));
  return out;
}

/** A walk heading north from a "front door", `n` points `stepM` apart. */
function makeRoute(n, stepM, lat0, lng0) {
  const dLat = stepM / 111195;
  const points = [];
  const times = [];
  for (let i = 0; i < n; i++) {
    const lat = Math.round((lat0 + i * dLat) * 100000) / 100000;
    const lng = Math.round((lng0 + (i % 2) * 0.00001) * 100000) / 100000;
    points.push([lat, lng, Math.round((12 + i * 0.1) * 10) / 10]);
    times.push(i * 4);
  }
  return { points, times };
}

const STARTED_AT = "2026-09-20T12:00:00Z";
const STARTED_EPOCH = Date.parse(STARTED_AT) / 1000;
const ROUTES = {
  [`rpc-w-post-${OWNER}`]: makeRoute(300, 6, 40.7, -74.0),
  [`rpc-w-raw-${OWNER}`]: makeRoute(300, 6, 40.75, -74.0),
  [`rpc-w-post-${CREW}`]: makeRoute(300, 9, 40.8, -73.9),
  [`rpc-w-post-${SHORTY}`]: makeRoute(80, 5, 40.6, -74.1),
  [`rpc-w-post-${MAPSOFF}`]: makeRoute(300, 6, 40.65, -74.1),
};

async function cleanup() {
  await db.query(
    `DELETE FROM in_app_notifications WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(`DELETE FROM post_coauthors WHERE user_id = ANY($1::text[])`, [
    ALL,
  ]);
  await db.query(`DELETE FROM posts WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM workouts WHERE user_id = ANY($1::text[])`, [ALL]);
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

async function insertWorkout(id, user, daysAgo, { stealth = false } = {}) {
  await db.query(
    `INSERT INTO workouts
       (workout_id, user_id, workout_type, distance, total_duration,
        device_end_date, date, local_date, timezone_offset, calories, steps,
        feed_role, created_at, stealth)
     VALUES ($1, $2, 'walking', 1.1, 1500,
             NOW() - ($3 || ' days')::interval - INTERVAL '2 hours',
             (NOW() - ($3 || ' days')::interval)::date,
             (NOW() - ($3 || ' days')::interval)::date, 0, 90, 2200,
             'daily_mile', NOW() - ($3 || ' days')::interval - INTERVAL '2 hours', $4)`,
    [id, user, String(daysAgo), stealth],
  );
  const r = ROUTES[id];
  if (r) {
    await db.query(
      `INSERT INTO workout_routes (workout_id, route, point_count, times, started_at)
       VALUES ($1, $2::jsonb, $3, $4::jsonb, $5::timestamptz)`,
      [
        id,
        JSON.stringify(r.points),
        r.points.length,
        JSON.stringify(r.times),
        STARTED_AT,
      ],
    );
  }
}

async function insertPost(user, workoutId, daysAgo) {
  return (
    await db.query(
      `INSERT INTO posts (user_id, media_url, caption, workout_id, local_date,
                          share_to_feed, is_auto, include_route, created_at)
       VALUES ($1, '/uploads/posts/' || $1 || '-1.jpg', 'walk', $2,
               (NOW() - ($3 || ' days')::interval)::date, TRUE, FALSE, TRUE,
               NOW() - ($3 || ' days')::interval - INTERVAL '1 hour')
       RETURNING post_id`,
      [user, workoutId, String(daysAgo)],
    )
  )[0].post_id;
}

async function seed() {
  for (const id of ALL) {
    await db.query(
      `INSERT INTO users (user_id, apple_sub, email, username, first_name, last_name)
       VALUES ($1::varchar, $2, $3, $1::varchar, $1::varchar, 'Walker')`,
      [id, `sub-${id}`, `${id}@example.com`],
    );
  }
  const befriend = async (a, b) =>
    db.query(
      `INSERT INTO friendships (user_id, friend_id, status)
       VALUES ($1, $2, 'accepted'), ($2, $1, 'accepted')`,
      [a, b],
    );
  for (const u of [OWNER, CREW, SHORTY, MAPSOFF]) await befriend(FRIEND, u);
  await befriend(OWNER, CREW);
  await db.query(
    `INSERT INTO notification_settings (user_id, route_privacy_meters) VALUES ($1, 402)`,
    [CREW],
  );
  await db.query(
    `INSERT INTO notification_settings (user_id, share_route_maps) VALUES ($1, FALSE)`,
    [MAPSOFF],
  );

  const posts = {};
  // OWNER: yesterday a photo post (post arm), today a bare walk (workout arm).
  await insertWorkout(`rpc-w-post-${OWNER}`, OWNER, 1);
  await insertWorkout(`rpc-w-raw-${OWNER}`, OWNER, 0);
  posts.owner = await insertPost(OWNER, `rpc-w-post-${OWNER}`, 1);
  // CREW's leg of the walk, credited on OWNER's post.
  await insertWorkout(`rpc-w-post-${CREW}`, CREW, 1);
  await db.query(
    `INSERT INTO post_coauthors (post_id, user_id, status, workout_id)
     VALUES ($1, $2, 'accepted', $3)`,
    [posts.owner, CREW, `rpc-w-post-${CREW}`],
  );
  await insertWorkout(`rpc-w-post-${SHORTY}`, SHORTY, 1);
  posts.short = await insertPost(SHORTY, `rpc-w-post-${SHORTY}`, 1);
  await insertWorkout(`rpc-w-post-${MAPSOFF}`, MAPSOFF, 1);
  posts.mapsoff = await insertPost(MAPSOFF, `rpc-w-post-${MAPSOFF}`, 1);
  // A stealth walk: no route row exists by the write-time invariant.
  await insertWorkout(`rpc-w-stealth-${MAPSOFF}`, MAPSOFF, 2, {
    stealth: true,
  });
  return posts;
}

/** Every post/entry surface's route triple for one post, as `viewer`. */
async function postSurfaces(viewer, author, postId) {
  const feed = await getUnifiedFeed(viewer, 100, null);
  const entry = feed.find((r) => r.kind === "post" && r.id === String(postId));
  const single = await getFeedEntryForPost(viewer, String(postId));
  const legacy = (await getFeed(viewer, 100, null)).find(
    (r) => String(r.post_id) === String(postId),
  );
  const grid = (await getUserPosts(viewer, author, 50, null)).find(
    (r) => String(r.post_id) === String(postId),
  );
  return {
    "feed post arm": entry,
    "single post": single,
    "legacy feed": legacy,
    "profile grid": grid,
  };
}

const triple = (row) =>
  row
    ? {
        route: row.route ?? null,
        route_times: row.route_times ?? null,
        route_started_at: row.route_started_at ?? null,
        route_trimmed: row.route_trimmed ?? null,
      }
    : undefined;

/**
 * Assert `served` is a correctly trimmed view of `stored` for a setting of
 * `settingM`. Returns the slice offset (or -1).
 */
function assertTrimmed(label, served, stored, settingM) {
  const pts = served?.route;
  if (!Array.isArray(pts) || pts.length < 2) {
    check(`${label}: a trimmed route is served`, Array.isArray(pts), true);
    return -1;
  }
  const key = JSON.stringify(pts[0]);
  const offset = stored.points.findIndex((p) => JSON.stringify(p) === key);
  check(
    `${label}: contiguous inner slice of the stored route`,
    offset > 0 &&
      JSON.stringify(stored.points.slice(offset, offset + pts.length)) ===
        JSON.stringify(pts),
    true,
  );
  const end = offset + pts.length - 1;
  check(
    `${label}: shorter at BOTH ends`,
    offset > 0 && end < stored.points.length - 1,
    true,
  );
  const cum = cumulative(stored.points);
  const total = cum[cum.length - 1];
  const first = stored.points[0];
  const last = stored.points[stored.points.length - 1];
  const step = Math.max(...cum.slice(1).map((c, i) => c - cum[i]));
  const minCut = settingM * 0.9;
  const maxCut = settingM * 1.3 + step + 0.01;
  check(
    `${label}: first kept point ≥ min cut from the true start (line + path)`,
    geo(first, pts[0]) >= minCut && cum[offset] >= minCut,
    true,
  );
  check(
    `${label}: last kept point ≥ min cut from the true end (line + path)`,
    geo(last, pts[pts.length - 1]) >= minCut && total - cum[end] >= minCut,
    true,
  );
  check(
    `${label}: cuts within the jitter band (≤ 1.3× + one segment)`,
    cum[offset] <= maxCut && total - cum[end] <= maxCut,
    true,
  );
  check(
    `${label}: altitude kept`,
    pts.every((p) => p.length === 3),
    true,
  );
  const times = served.route_times;
  check(
    `${label}: times count matches points`,
    Array.isArray(times) && times.length === pts.length,
    true,
  );
  check(
    `${label}: times re-based to 0 and sliced in lockstep`,
    Array.isArray(times) &&
      times.every(
        (t, k) =>
          Math.abs(t - (stored.times[offset + k] - stored.times[offset])) <
          1e-9,
      ),
    true,
  );
  check(
    `${label}: started_at shifted by the seconds cut`,
    served.route_started_at,
    STARTED_EPOCH + stored.times[offset],
  );
  check(`${label}: route_trimmed`, served.route_trimmed, true);
  return offset;
}

async function main() {
  await cleanup();
  const posts = await seed();
  const ownerRoute = ROUTES[`rpc-w-post-${OWNER}`];

  // ── 1. The owner gets the stored route, untouched ────────────────────────
  for (const [name, row] of Object.entries(
    await postSurfaces(OWNER, OWNER, posts.owner),
  )) {
    check(`owner ${name}: full stored route`, triple(row), {
      route: ownerRoute.points,
      route_times: ownerRoute.times,
      route_started_at: STARTED_EPOCH,
      route_trimmed: false,
    });
  }
  const ownDetail = await getWorkoutRouteDetail(
    OWNER,
    `rpc-w-post-${OWNER}`,
    OWNER,
  );
  check("owner detail: full route", ownDetail?.route, ownerRoute.points);
  check("owner detail: not trimmed", ownDetail?.route_trimmed, false);

  // ── 2. A friend gets the trimmed slice everywhere, identically ───────────
  const friendRows = await postSurfaces(FRIEND, OWNER, posts.owner);
  let reference = null;
  for (const [name, row] of Object.entries(friendRows)) {
    assertTrimmed(`friend ${name}`, triple(row), ownerRoute, 201);
    if (reference === null) reference = JSON.stringify(triple(row));
    else
      check(
        `friend ${name} == feed post arm`,
        JSON.stringify(triple(row)) === reference,
        true,
      );
  }
  const detail = await getWorkoutRouteDetail(
    OWNER,
    `rpc-w-post-${OWNER}`,
    FRIEND,
  );
  assertTrimmed("friend workout route detail", detail, ownerRoute, 201);
  check(
    "friend detail == feed post arm",
    JSON.stringify(triple(detail)) === reference,
    true,
  );
  // Repeated reads can't be averaged: the cut is a function of the workout.
  const again = triple(
    (await postSurfaces(FRIEND, OWNER, posts.owner))["feed post arm"],
  );
  check(
    "deterministic across reads",
    JSON.stringify(again) === reference,
    true,
  );

  const feed = await getUnifiedFeed(FRIEND, 100, null);
  const rawEntry = feed.find(
    (r) => r.kind === "workout" && r.workout_id === `rpc-w-raw-${OWNER}`,
  );
  const rawStored = ROUTES[`rpc-w-raw-${OWNER}`];
  const rawOffset = assertTrimmed(
    "friend feed WORKOUT arm",
    triple(rawEntry),
    rawStored,
    201,
  );
  const postOffset = JSON.parse(reference).route
    ? ownerRoute.points.findIndex(
        (p) =>
          JSON.stringify(p) === JSON.stringify(JSON.parse(reference).route[0]),
      )
    : -1;
  check(
    "two walks of the same shape are cut differently (per-workout jitter)",
    rawOffset !== postOffset ||
      triple(rawEntry).route.length !== JSON.parse(reference).route.length,
    true,
  );

  // ── 2b. The write-time cache answers exactly what the computation does ──
  // Seeds go in by SQL, so everything above ran on the computed path (NULL
  // privacy_bounds). Fill the cache the way the boot backfill does and read
  // again: byte-identical. Every section below then runs on the CACHED path.
  const crewBefore = JSON.stringify(
    ((await postSurfaces(FRIEND, OWNER, posts.owner))["feed post arm"]?.coauthors ?? [])
      .find((c) => c.user_id === CREW));
  await db.query(`DELETE FROM maintenance_runs WHERE name = $1`, [ROUTE_PRIVACY_BOUNDS_BACKFILL]);
  const bf = new pg.Client({ connectionString: process.env.DATABASE_URL });
  await bf.connect();
  const filled = await runRoutePrivacyBoundsBackfill(bf);
  await bf.end();
  check("backfill filled the seeded routes", filled.routes >= Object.keys(ROUTES).length, true);
  const cached = await db.query(
    `SELECT workout_id, privacy_bounds FROM workout_routes WHERE workout_id LIKE 'rpc-w-%' ORDER BY workout_id`);
  check("every seeded route now carries its cache", cached.every((r) => r.privacy_bounds !== null), true);
  check("the cache lists every offered setting",
    Object.keys(cached[0]?.privacy_bounds ?? {}).sort(), ["1609", "201", "402", "805"]);
  check("a short walk's cache is a sliver for every setting",
    Object.values(cached.find((r) => r.workout_id === `rpc-w-post-${SHORTY}`)?.privacy_bounds ?? { x: 1 })
      .every((v) => v === null), true);
  check("cached read == computed read (author line)",
    JSON.stringify(triple((await postSurfaces(FRIEND, OWNER, posts.owner))["feed post arm"])) === reference,
    true);
  check("cached read == computed read (crew line)",
    JSON.stringify(((await postSurfaces(FRIEND, OWNER, posts.owner))["feed post arm"]?.coauthors ?? [])
      .find((c) => c.user_id === CREW)) === crewBefore, true);
  check("cached read == computed read (detail)",
    JSON.stringify(triple(await getWorkoutRouteDetail(OWNER, `rpc-w-post-${OWNER}`, FRIEND))) === reference,
    true);

  // ── 3. The setting applies at READ ──────────────────────────────────────
  await updateNotificationPreferences(OWNER, { route_privacy_meters: 0 });
  const off = triple(
    (await postSurfaces(FRIEND, OWNER, posts.owner))["feed post arm"],
  );
  check("setting Off: friend gets the full route", off, {
    route: ownerRoute.points,
    route_times: ownerRoute.times,
    route_started_at: STARTED_EPOCH,
    route_trimmed: false,
  });
  check(
    "setting Off: detail full too",
    (await getWorkoutRouteDetail(OWNER, `rpc-w-post-${OWNER}`, FRIEND))?.route,
    ownerRoute.points,
  );
  await updateNotificationPreferences(OWNER, { route_privacy_meters: 1609 });
  const mile = triple(
    (await postSurfaces(FRIEND, OWNER, posts.owner))["feed post arm"],
  );
  check("setting 1 mi on a ~1.8 km walk: no route at all", mile, {
    route: null,
    route_times: null,
    route_started_at: null,
    route_trimmed: null,
  });
  check(
    "setting 1 mi: detail serves no route",
    await getWorkoutRouteDetail(OWNER, `rpc-w-post-${OWNER}`, FRIEND),
    null,
  );
  await updateNotificationPreferences(OWNER, { route_privacy_meters: null });
  const back = triple(
    (await postSurfaces(FRIEND, OWNER, posts.owner))["feed post arm"],
  );
  check(
    "back to the default: the same cut as before",
    JSON.stringify(back) === reference,
    true,
  );

  // ── 4. A short walk: nothing for a friend, everything for the owner ──────
  const shortFriend = triple(
    (await postSurfaces(FRIEND, SHORTY, posts.short))["feed post arm"],
  );
  check("short walk: friend gets no route", shortFriend, {
    route: null,
    route_times: null,
    route_started_at: null,
    route_trimmed: null,
  });
  check(
    "short walk: detail none for a friend",
    await getWorkoutRouteDetail(SHORTY, `rpc-w-post-${SHORTY}`, FRIEND),
    null,
  );
  check(
    "short walk: owner keeps the whole line",
    triple((await postSurfaces(SHORTY, SHORTY, posts.short))["profile grid"])
      ?.route,
    ROUTES[`rpc-w-post-${SHORTY}`].points,
  );

  // ── 5. Crew lines: each by its OWNER's setting ───────────────────────────
  const crewStored = ROUTES[`rpc-w-post-${CREW}`];
  const friendEntry = (await postSurfaces(FRIEND, OWNER, posts.owner))[
    "feed post arm"
  ];
  const crewLine = (friendEntry?.coauthors ?? []).find(
    (c) => c.user_id === CREW,
  );
  check("crew line present for a friend", !!crewLine, true);
  const crewOffset = assertTrimmed(
    "crew line (friend view, 402 m)",
    crewLine,
    crewStored,
    402,
  );
  check(
    "crew line uses THEIR setting (cut beyond the poster's max 1.3×201)",
    crewOffset > 0 && cumulative(crewStored.points)[crewOffset] >= 402 * 0.9,
    true,
  );
  const crewSelf = (await postSurfaces(CREW, OWNER, posts.owner))[
    "feed post arm"
  ];
  const crewOwn = (crewSelf?.coauthors ?? []).find((c) => c.user_id === CREW);
  check(
    "crew member sees their own line in full",
    crewOwn?.route,
    crewStored.points,
  );
  check("crew member's own line: not trimmed", crewOwn?.route_trimmed, false);
  assertTrimmed(
    "crew member sees the POSTER's line trimmed",
    triple(crewSelf),
    ownerRoute,
    201,
  );

  // ── 6. Maps-off and stealth stay null ────────────────────────────────────
  check(
    "maps-off: friend gets no route",
    triple(
      (await postSurfaces(FRIEND, MAPSOFF, posts.mapsoff))["feed post arm"],
    )?.route,
    null,
  );
  check(
    "maps-off: detail none",
    await getWorkoutRouteDetail(MAPSOFF, `rpc-w-post-${MAPSOFF}`, FRIEND),
    null,
  );
  check(
    "stealth walk: detail none",
    await getWorkoutRouteDetail(MAPSOFF, `rpc-w-stealth-${MAPSOFF}`, FRIEND),
    null,
  );

  // ── 7. Preferences ───────────────────────────────────────────────────────
  check(
    "prefs: default served as 201",
    (await getNotificationPreferences(FRIEND)).route_privacy_meters,
    201,
  );
  check(
    "prefs: crew's 402",
    (await getNotificationPreferences(CREW)).route_privacy_meters,
    402,
  );
  check(
    "prefs: write 805",
    (await updateNotificationPreferences(FRIEND, { route_privacy_meters: 805 }))
      .route_privacy_meters,
    805,
  );
  check(
    "prefs: off-catalogue value ignored",
    (await updateNotificationPreferences(FRIEND, { route_privacy_meters: 333 }))
      .route_privacy_meters,
    805,
  );
  check(
    "prefs: null returns to the default",
    (
      await updateNotificationPreferences(FRIEND, {
        route_privacy_meters: null,
      })
    ).route_privacy_meters,
    201,
  );
  const stored = await db.query(
    `SELECT route_privacy_meters FROM notification_settings WHERE user_id = $1`,
    [FRIEND],
  );
  check(
    "prefs: null is stored as NULL (follows future defaults)",
    stored[0]?.route_privacy_meters,
    null,
  );

  await cleanup();
  if (failures) {
    console.error(
      `\nroute-privacy-check: ${failures} failure(s), ${passes} passed`,
    );
    process.exit(1);
  }
  console.log(`\nroute-privacy-check: all ${passes} assertions passed`);
  process.exit(0);
}

main().catch(async (err) => {
  console.error(err);
  await cleanup().catch(() => {});
  process.exit(1);
});
