/**
 * Walked straight roads are served as walked ground (migration 0098).
 *
 * The app cuts a route's line at any step over 500 m that is more than a
 * quarter of the route (iOS `RouteGaps`), meant for the drive between two
 * halves of a paused walk. A stored route is simplified, so a straight road is
 * ONE such step and an out-and-back down one was drawn as just its turns.
 * `servedRouteFrom` now fills walked long steps with points when the route's
 * length matches the recorded distance. This pins, through the real reads:
 *   1. A real out-and-back (Oct 13 2026, 11 stored points, two ~730 m
 *      straights): the owner gets a route the app draws WHOLE, clock still
 *      1:1, every stored point kept in order. A friend still gets nothing
 *      (the privacy trim already removed it; this change must not alter that).
 *   2. A paused walk with a 1.6 km jump and a 20-minute pause (a jump the
 *      clock alone can't tell from walking): owner gets the stored route
 *      byte-for-byte, and the app still cuts the jump for owner AND friend.
 *   3. A longer out-and-back whose ends survive the trim: a friend's detail
 *      and feed copies are drawn whole too.
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/route-walked-steps-check.mjs
 */
import { PostgresService } from "../dist/services/DbService.js";
import { getUnifiedFeed } from "../dist/services/postService.js";
import { getWorkoutRouteDetail } from "../dist/services/workoutService.js";

const db = PostgresService.getInstance();

const OWNER = "rws-owner";
const FRIEND = "rws-friend";
const ALL = [OWNER, FRIEND];

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

// The shipped app's rule, line for line (iOS `RouteGaps.breakIndices`).
function haversine(a, b) {
  const r = 6371000;
  const rad = Math.PI / 180;
  const dLat = (b[0] - a[0]) * rad;
  const dLon = (b[1] - a[1]) * rad;
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(a[0] * rad) * Math.cos(b[0] * rad) * Math.sin(dLon / 2) ** 2;
  return 2 * r * Math.asin(Math.min(1, Math.sqrt(h)));
}
function appBreaks(points, times) {
  if (!points || points.length < 2) return [];
  const clock = times && times.length === points.length ? times : null;
  const steps = [];
  for (let i = 0; i < points.length - 1; i++)
    steps.push(haversine(points[i], points[i + 1]));
  const total = steps.reduce((s, m) => s + m, 0);
  const out = [];
  steps.forEach((m, i) => {
    if (m > 3000) return out.push(i);
    if (m > 500 && total > 0 && m / total > 0.25) return out.push(i);
    if (!clock) return;
    const dt = clock[i + 1] - clock[i];
    if (dt > 0 && m / dt > 12) out.push(i);
  });
  return out;
}

// The served route's stored points form a contiguous, in-order run of the
// stored route (a friend's slice is one), with nothing dropped between.
function keepsStoredPoints(served, stored) {
  const key = (p) => `${p[0]},${p[1]}`;
  const idx = served.map((p) => stored.map(key).indexOf(key(p))).filter((i) => i >= 0);
  return idx.length >= 2 && idx.every((v, n) => n === 0 || v === idx[n - 1] + 1);
}

// 1. Mad Dave's Oct 13 walk, exactly as stored.
const STRAIGHT = {
  id: "rws-w-straight",
  miles: 1.084119524967113,
  points: [
    [34.44005, -77.5218, 5.5], [34.43647, -77.52823, 2.4],
    [34.43627, -77.52841, 1.9], [34.43578, -77.52801, 4.7],
    [34.43572, -77.52788, 2.6], [34.43578, -77.52774, 2.1],
    [34.43977, -77.52103, 1.5], [34.43992, -77.52107, 1.9],
    [34.44027, -77.52138, 1.9], [34.44015, -77.52161, 2.5],
    [34.43997, -77.52156, 5.3],
  ],
  times: [0, 487, 505, 547, 556, 565, 1044, 1056, 1086, 1104, 1173],
};

// 2. ~800 m wiggling north, a 1.6 km jump east during a 20-minute pause,
// ~800 m more. Recorded distance = the walking only.
function pausedWalk() {
  const points = [];
  const times = [];
  let lat = 40.7;
  let lng = -74.0;
  let t = 0;
  for (let leg = 0; leg < 2; leg++) {
    for (let k = 0; k < 40; k++) {
      lat += 0.00018;
      lng += k % 2 ? 0.00004 : -0.00004;
      points.push([Math.round(lat * 1e5) / 1e5, Math.round(lng * 1e5) / 1e5]);
      times.push(t);
      t += 15;
    }
    lng += 1600 / 84300;
    t += 1200;
  }
  let walked = 0;
  for (let i = 1; i < points.length; i++)
    if (i !== 40) walked += haversine(points[i - 1], points[i]);
  return { id: "rws-w-gap", miles: walked / 1609.344, points, times };
}
const GAP = pausedWalk();

// 3. Wiggle 400 m, a 900 m straight, wiggle, the straight back, wiggle: ends
// long enough that a friend's hide-start-&-end trim leaves both straights.
function outAndBack() {
  const points = [];
  const times = [];
  let lat = 40.6;
  let lng = -74.1;
  let t = 0;
  const push = () => {
    points.push([Math.round(lat * 1e5) / 1e5, Math.round(lng * 1e5) / 1e5]);
    times.push(Math.round(t * 10) / 10);
  };
  const wiggle = () => {
    for (let k = 0; k < 20; k++) {
      lat += 0.00018;
      lng += k % 2 ? 0.00004 : -0.00004;
      t += 15;
      push();
    }
  };
  const straight = (dir) => {
    lng += (dir * 900) / 84300;
    t += 650;
    push();
  };
  push();
  wiggle(); straight(1); wiggle(); straight(-1); wiggle();
  let m = 0;
  for (let i = 1; i < points.length; i++) m += haversine(points[i - 1], points[i]);
  return { id: "rws-w-outback", miles: m / 1609.344, points, times };
}
const OUTBACK = outAndBack();

async function cleanup() {
  await db.query(`DELETE FROM workouts WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(
    `DELETE FROM friendships WHERE user_id = ANY($1::text[]) OR friend_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(`DELETE FROM users WHERE user_id = ANY($1::text[])`, [ALL]);
}

async function insertWalk(w, daysAgo) {
  await db.query(
    `INSERT INTO workouts
       (workout_id, user_id, workout_type, distance, total_duration,
        device_end_date, date, local_date, timezone_offset, calories, steps,
        feed_role, created_at)
     VALUES ($1, $2, 'walking', $3, 1500,
             NOW() - ($4 || ' days')::interval - INTERVAL '2 hours',
             (NOW() - ($4 || ' days')::interval)::date,
             (NOW() - ($4 || ' days')::interval)::date, 0, 90, 2200,
             'daily_mile', NOW() - ($4 || ' days')::interval - INTERVAL '2 hours')`,
    [w.id, OWNER, w.miles, String(daysAgo)],
  );
  await db.query(
    `INSERT INTO workout_routes (workout_id, route, point_count, times, started_at)
     VALUES ($1, $2::jsonb, $3, $4::jsonb, NOW() - INTERVAL '3 hours')`,
    [w.id, JSON.stringify(w.points), w.points.length, JSON.stringify(w.times)],
  );
}

async function main() {
  await cleanup();
  for (const id of ALL) {
    await db.query(
      `INSERT INTO users (user_id, apple_sub, email, username, first_name, last_name)
       VALUES ($1::varchar, $2, $3, $1::varchar, $1::varchar, 'Walker')`,
      [id, `sub-${id}`, `${id}@example.com`],
    );
  }
  await db.query(
    `INSERT INTO friendships (user_id, friend_id, status)
     VALUES ($1, $2, 'accepted'), ($2, $1, 'accepted')`,
    [OWNER, FRIEND],
  );
  await insertWalk(STRAIGHT, 0);
  await insertWalk(GAP, 1);
  await insertWalk(OUTBACK, 2);

  check("fixture: the stored straight walk IS cut by the app",
    appBreaks(STRAIGHT.points, STRAIGHT.times), [0, 5]);
  check("fixture: the stored paused walk IS cut by the app",
    appBreaks(GAP.points, GAP.times), [39]);
  check("fixture: the stored out-and-back IS cut by the app",
    appBreaks(OUTBACK.points, OUTBACK.times).length, 2);

  // The friend's copy of the real walk is null BEFORE and after: the trim
  // works in whole stored points, and each end is one 700 m step. Pinned so
  // this change is seen not to touch the privacy outcome.
  check("straight, friend detail: still trimmed to nothing",
    await getWorkoutRouteDetail(OWNER, STRAIGHT.id, FRIEND), null);

  for (const [who, viewer, walk] of [
    ["owner", OWNER, STRAIGHT],
    ["friend", FRIEND, OUTBACK],
  ]) {
    const d = await getWorkoutRouteDetail(OWNER, walk.id, viewer);
    check(`straight, ${who} detail: served`, Array.isArray(d?.route), true);
    check(`straight, ${who} detail: app draws it whole`,
      appBreaks(d?.route, d?.route_times), []);
    check(`straight, ${who} detail: clock 1:1`,
      d?.route_times?.length === d?.route?.length && d.route.length > 2, true);
    check(`straight, ${who} detail: stored points kept in order`,
      keepsStoredPoints(d?.route ?? [], walk.points), true);
    check(`straight, ${who} detail: clock never runs backwards`,
      (d?.route_times ?? []).every((t, i, a) => i === 0 || t >= a[i - 1]), true);

    const g = await getWorkoutRouteDetail(OWNER, GAP.id, viewer);
    check(`paused, ${who} detail: app still cuts the jump`,
      appBreaks(g?.route, g?.route_times).length, 1);
    if (who === "owner") {
      check("paused, owner detail: stored route byte-for-byte",
        g?.route, GAP.points);
      check("paused, owner detail: stored clock byte-for-byte",
        g?.route_times, GAP.times);
    }
  }

  const feed = await getUnifiedFeed(FRIEND, 50, null);
  const entry = feed.find((r) => r.workout_id === OUTBACK.id);
  check("straight, friend feed: served", Array.isArray(entry?.route), true);
  check("straight, friend feed: app draws it whole",
    appBreaks(entry?.route, entry?.route_times), []);
  const own = (await getUnifiedFeed(OWNER, 50, null)).find(
    (r) => r.workout_id === STRAIGHT.id);
  check("straight, owner feed: every stored point, plus the fill",
    keepsStoredPoints(own?.route ?? [], STRAIGHT.points) &&
      own.route.length > STRAIGHT.points.length, true);

  await cleanup();
  if (failures) {
    console.error(`\nroute-walked-steps-check: ${failures} failure(s), ${passes} passed`);
    process.exit(1);
  }
  console.log(`\nroute-walked-steps-check: all ${passes} assertions passed`);
  process.exit(0);
}

main().catch(async (err) => {
  console.error(err);
  await cleanup().catch(() => {});
  process.exit(1);
});
