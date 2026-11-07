/**
 * Buddy live route privacy check.
 *
 * This is the one place a walker's position leaves their phone during a
 * workout. Every failure here is invisible in use (a friend simply sees a line
 * they shouldn't), so each door is pinned against a real migrated database:
 *
 *   1. Off by default: nothing is stored or served without an opt-in.
 *   2. Reciprocal: you see other people's lines only while sharing yours.
 *   3. Vetoes: maps off, private visibility, Stealth and indoor all refuse,
 *      including a setting flipped mid-walk.
 *   4. Blocks hide a line in both directions, even on the same walk.
 *   5. Input limits: bad points, oversize posts and the per-walker cap.
 *   6. Walk-only: a friend who isn't on the walk gets nothing, even one who can
 *      see that the walker is out right now.
 *   7. Deletion: off, leaving, finishing and the walk closing all remove it,
 *      and the stale sweep catches a phone that vanished.
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/buddy-live-route-check.mjs
 */
import { PostgresService } from "../dist/services/DbService.js";
import {
  appendLiveRoutePoints,
  clearLiveRoutes,
  getLiveRoutes,
  MAX_POINTS_PER_POST,
  MAX_POINTS_PER_WALKER,
  MAX_POINTS_SERVED,
  setLiveRouteSharing,
  sweepStaleLiveRoutes,
} from "../dist/services/buddyLiveRouteService.js";
import {
  createSession,
  finishParticipation,
  joinSession,
  leaveSession,
  startSession,
} from "../dist/services/buddySessionService.js";
import { closeWindow, openWindow } from "../dist/services/stealthService.js";

const db = PostgresService.getInstance();

const HOST = "buddy-route-host";
const PAL = "buddy-route-pal";
const THIRD = "buddy-route-third";
const OUTSIDER = "buddy-route-outsider"; // a friend who isn't on the walk
const ALL = [HOST, PAL, THIRD, OUTSIDER];
const POINT = [40.78123456, -73.96654321];

let failures = 0;
function check(label, actual, expected) {
  const ok = actual === expected;
  if (!ok) failures++;
  console.log(
    `${ok ? "ok  " : "FAIL"}  ${label} → ${actual} (expected ${expected})`,
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

async function storedRows(sessionId) {
  const rows = await db.query(
    `SELECT user_id FROM buddy_live_routes WHERE session_id = $1`,
    [sessionId],
  );
  return rows.length;
}

async function seed() {
  for (const id of ALL) {
    await db.query(
      `INSERT INTO users (user_id, apple_sub, email, username, first_name, last_name)
       VALUES ($1, $2, $3, $4, $5, 'Route')
       ON CONFLICT (user_id) DO NOTHING`,
      [id, `sub-${id}`, `${id}@example.com`, id, id],
    );
  }
  for (const a of ALL) {
    for (const b of ALL) {
      if (a === b) continue;
      await db.query(
        `INSERT INTO friendships (user_id, friend_id, status)
         VALUES ($1, $2, 'accepted')
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
  await db.query(
    `DELETE FROM in_app_notifications WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(`DELETE FROM stealth_windows WHERE user_id = ANY($1::text[])`, [
    ALL,
  ]);
  await db.query(
    `DELETE FROM user_blocks WHERE blocker_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(
    `DELETE FROM notification_settings WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(
    `DELETE FROM buddy_session_participants WHERE user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(
    `DELETE FROM buddy_sessions WHERE host_user_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(`DELETE FROM friendships WHERE user_id = ANY($1::text[])`, [
    ALL,
  ]);
  await db.query(`DELETE FROM users WHERE user_id = ANY($1::text[])`, [ALL]);
}

async function setSetting(userId, column, value) {
  await db.query(
    `INSERT INTO notification_settings (user_id, ${column}) VALUES ($1, $2)
     ON CONFLICT (user_id) DO UPDATE SET ${column} = EXCLUDED.${column}`,
    [userId, value],
  );
}

/** A running walk with HOST and PAL (and optionally THIRD) both active. */
async function runningWalk({ third = false } = {}) {
  const created = await createSession(HOST, {
    mode: "together",
    activityType: "walking",
    inviteUserIds: [],
  });
  await joinSession(PAL, { sessionId: created.id, locationType: "outdoor" });
  if (third) {
    await joinSession(THIRD, { sessionId: created.id, locationType: "outdoor" });
  }
  await startSession(created.id, HOST);
  await db.query(
    `UPDATE buddy_sessions SET started_at = NOW() - INTERVAL '5 minutes'
      WHERE id = $1`,
    [created.id],
  );
  await db.query(
    `UPDATE buddy_session_participants SET status = 'active'
      WHERE session_id = $1`,
    [created.id],
  );
  return created.id;
}

async function testOptInAndReciprocity() {
  const id = await runningWalk();

  check(
    "a post with no opt-in stores nothing",
    (await appendLiveRoutePoints(id, HOST, [POINT])).accepted,
    0,
  );
  check("nothing is stored without an opt-in", await storedRows(id), 0);

  await setLiveRouteSharing(id, HOST, true);
  await appendLiveRoutePoints(id, HOST, [POINT]);

  const notSharing = await getLiveRoutes(id, PAL);
  check("a viewer who isn't sharing is told so", notSharing.sharing, false);
  check("a viewer who isn't sharing sees no lines", notSharing.routes.length, 0);

  await setLiveRouteSharing(id, PAL, true);
  const sharing = await getLiveRoutes(id, PAL);
  check("once both share, the line is served", sharing.routes.length, 1);
  check("it's the other walker's line", sharing.routes[0].user_id, HOST);
  check(
    "coordinates are rounded to about a metre",
    sharing.routes[0].points[0][0],
    40.78123,
  );
  check(
    "you are never served your own line",
    (await getLiveRoutes(id, HOST)).routes.length,
    0,
  );

  await setLiveRouteSharing(id, HOST, false);
  check("turning it off deletes the line", await storedRows(id), 1);
  check(
    "and friends stop seeing it",
    (await getLiveRoutes(id, PAL)).routes.length,
    0,
  );
  await clearLiveRoutes(id);
}

async function testVetoes() {
  const id = await runningWalk();

  await setSetting(HOST, "share_route_maps", false);
  check(
    "maps off refuses the opt-in",
    await errorCode(() => setLiveRouteSharing(id, HOST, true)),
    "route_sharing_unavailable",
  );
  await setSetting(HOST, "share_route_maps", true);

  await setSetting(HOST, "workout_visibility", "private");
  check(
    "private visibility refuses the opt-in",
    await errorCode(() => setLiveRouteSharing(id, HOST, true)),
    "route_sharing_unavailable",
  );
  await setSetting(HOST, "workout_visibility", "friends");

  await openWindow(HOST);
  check(
    "Stealth refuses the opt-in",
    await errorCode(() => setLiveRouteSharing(id, HOST, true)),
    "route_sharing_unavailable",
  );
  await closeWindow(HOST);

  // Flipped MID-walk: the next post removes what was already sent, and a read
  // before that post must not serve it either.
  await setLiveRouteSharing(id, HOST, true);
  await setLiveRouteSharing(id, PAL, true);
  await appendLiveRoutePoints(id, HOST, [POINT]);
  await setSetting(HOST, "share_route_maps", false);
  check(
    "a line stops being served the moment maps go off",
    (await getLiveRoutes(id, PAL)).routes.length,
    0,
  );
  check(
    "the next post says sharing ended",
    (await appendLiveRoutePoints(id, HOST, [POINT])).sharing,
    false,
  );
  const rows = await db.query(
    `SELECT 1 FROM buddy_live_routes WHERE session_id = $1 AND user_id = $2`,
    [id, HOST],
  );
  check("and removes what was already sent", rows.length, 0);
  await setSetting(HOST, "share_route_maps", true);
  await clearLiveRoutes(id);

  await openWindow(HOST);
  await setLiveRouteSharing(id, PAL, true);
  check(
    "Stealth started mid-walk ends sharing on the next post",
    (await appendLiveRoutePoints(id, HOST, [POINT])).sharing,
    false,
  );
  await closeWindow(HOST);
  await clearLiveRoutes(id);

  const indoor = await createSession(HOST, {
    mode: "together",
    activityType: "walking",
    inviteUserIds: [],
  });
  await joinSession(PAL, {
    sessionId: indoor.id,
    locationType: "indoor",
  });
  check(
    "an indoor walker can't opt in",
    await errorCode(() => setLiveRouteSharing(indoor.id, PAL, true)),
    "route_sharing_unavailable",
  );
}

async function testBlocks() {
  const id = await runningWalk();
  await setLiveRouteSharing(id, HOST, true);
  await setLiveRouteSharing(id, PAL, true);
  await appendLiveRoutePoints(id, HOST, [POINT]);
  await appendLiveRoutePoints(id, PAL, [POINT]);
  await db.query(
    `INSERT INTO user_blocks (blocker_id, blocked_id) VALUES ($1, $2)`,
    [HOST, PAL],
  );
  check(
    "the blocked person can't see the blocker's line",
    (await getLiveRoutes(id, PAL)).routes.length,
    0,
  );
  check(
    "and the blocker can't see theirs",
    (await getLiveRoutes(id, HOST)).routes.length,
    0,
  );
  await db.query(`DELETE FROM user_blocks WHERE blocker_id = $1`, [HOST]);
  await clearLiveRoutes(id);
}

async function testLimits() {
  const id = await runningWalk();
  await setLiveRouteSharing(id, HOST, true);
  await setLiveRouteSharing(id, PAL, true);

  check(
    "an empty post is refused",
    await errorCode(() => appendLiveRoutePoints(id, HOST, [])),
    "invalid_points",
  );
  check(
    "an impossible coordinate is refused",
    await errorCode(() => appendLiveRoutePoints(id, HOST, [[91, 0]])),
    "invalid_points",
  );
  check(
    "a non-number is refused",
    await errorCode(() => appendLiveRoutePoints(id, HOST, [["1", "2"]])),
    "invalid_points",
  );
  check(
    "an oversize post is refused",
    await errorCode(() =>
      appendLiveRoutePoints(
        id,
        HOST,
        Array(MAX_POINTS_PER_POST + 1).fill(POINT),
      ),
    ),
    "too_many_points",
  );

  await db.query(
    `UPDATE buddy_live_routes
        SET points = (SELECT jsonb_agg(jsonb_build_array(40 + g * 0.0001, -73))
                        FROM generate_series(1, $3::integer) g),
            point_count = $3::integer
      WHERE session_id = $1 AND user_id = $2`,
    [id, HOST, MAX_POINTS_PER_WALKER],
  );
  check(
    "a full line stops accepting points",
    (await appendLiveRoutePoints(id, HOST, [POINT])).accepted,
    0,
  );
  const served = (await getLiveRoutes(id, PAL)).routes[0].points;
  check("what's served is thinned", served.length, MAX_POINTS_SERVED);
  check(
    "and still reaches the newest point",
    served[served.length - 1][0],
    Math.round((40 + MAX_POINTS_PER_WALKER * 0.0001) * 1e5) / 1e5,
  );
  await clearLiveRoutes(id);
}

async function testWalkOnly() {
  const id = await runningWalk();
  await setLiveRouteSharing(id, HOST, true);
  await setLiveRouteSharing(id, PAL, true);
  await appendLiveRoutePoints(id, HOST, [POINT]);

  const outside = await getLiveRoutes(id, OUTSIDER);
  check("a friend not on the walk isn't sharing", outside.sharing, false);
  check("a friend not on the walk sees no route", outside.routes.length, 0);
  check(
    "they can't opt themselves in from outside",
    await errorCode(() => setLiveRouteSharing(id, OUTSIDER, true)),
    "not_active",
  );
  // Even a row put there by hand must not open the door: serving also requires
  // being on the walk, so stale or forged consent can't reach a route.
  await db.query(
    `INSERT INTO buddy_live_routes (session_id, user_id) VALUES ($1, $2)`,
    [id, OUTSIDER],
  );
  check(
    "a forged row still serves nothing",
    (await getLiveRoutes(id, OUTSIDER)).routes.length,
    0,
  );
  await clearLiveRoutes(id);

  // "Out now" must carry no coordinates, so a route can't leak that way.
  const liveColumns = await db.query(
    `SELECT column_name FROM information_schema.columns
      WHERE table_name = 'live_tracking_sessions'
        AND column_name ~* '(lat|lng|lon|coord|route|location)'`,
  );
  check("the Out now table has no location columns", liveColumns.length, 0);
}

async function testDeletion() {
  const left = await runningWalk({ third: true });
  await setLiveRouteSharing(left, HOST, true);
  await setLiveRouteSharing(left, PAL, true);
  await setLiveRouteSharing(left, THIRD, true);
  check("three walkers sharing", await storedRows(left), 3);
  await leaveSession(left, THIRD);
  check("leaving removes your line", await storedRows(left), 2);
  await finishParticipation(left, PAL);
  check("finishing removes your line", await storedRows(left), 1);
  await finishParticipation(left, HOST);
  check("the walk closing removes every line", await storedRows(left), 0);

  const stale = await runningWalk();
  await setLiveRouteSharing(stale, HOST, true);
  await db.query(
    `UPDATE buddy_live_routes SET updated_at = NOW() - INTERVAL '13 hours'
      WHERE session_id = $1`,
    [stale],
  );
  await sweepStaleLiveRoutes();
  check("the sweep clears a vanished phone's line", await storedRows(stale), 0);
}

async function main() {
  await cleanup();
  await seed();
  await testOptInAndReciprocity();
  await testVetoes();
  await testBlocks();
  await testLimits();
  await testWalkOnly();
  await testDeletion();
  await cleanup();
  console.log(
    failures === 0
      ? "buddy-live-route-check: all assertions passed"
      : `buddy-live-route-check: ${failures} FAILED`,
  );
  process.exit(failures === 0 ? 0 : 1);
}

main().catch(async (err) => {
  console.error(err);
  await cleanup().catch(() => {});
  process.exit(1);
});
