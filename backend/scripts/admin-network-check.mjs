/**
 * Admin Network tab check: the friend graph, its friend groups, and the
 * where-people-walk grid.
 *
 * Both panels break silently. A friendship counted twice (acceptance writes a
 * row in each direction), a pending request drawn as an edge, a group split
 * that depends on Map iteration order, or a map that places someone by the
 * front door their walks start from instead of where they walk — every one of
 * those renders a plausible picture that is wrong.
 *
 * Method: snapshot, seed a known world, snapshot again, assert DELTAS and
 * membership only (CI runs this after other seeded checks, so global totals
 * already carry their rows). The community detector is also pinned as a pure
 * function against graphs whose answer is not in doubt.
 *
 * Usage (same env as ci-smoke):
 *   DATABASE_URL=... node scripts/admin-network-check.mjs
 */

import { PostgresService } from "../dist/services/DbService.js";
import {
  getFriendNetwork,
  getUserLocations,
  resetNetworkCaches,
  detectCommunities,
  connectedComponents,
  LOCATION_CELL_DEGREES,
} from "../dist/services/adminNetworkService.js";

const db = PostgresService.getInstance();

const A = ["net-a1", "net-a2", "net-a3", "net-a4"]; // a 4-clique
const B = ["net-b1", "net-b2", "net-b3"]; // a triangle, bridged to a1
const C = ["net-c1", "net-c2"]; // an island of two
const ISO = "net-iso"; // no friends at all
const PEND = "net-pend"; // only a PENDING request
const ALL = [...A, ...B, ...C, ISO, PEND];

let failures = 0;
function check(label, actual, expected) {
  const ok = actual === expected;
  if (!ok) failures++;
  console.log(
    `${ok ? "ok  " : "FAIL"}  ${label} → ${actual}${ok ? "" : ` (expected ${expected})`}`,
  );
}
function truthy(label, value) {
  const ok = Boolean(value);
  if (!ok) failures++;
  console.log(`${ok ? "ok  " : "FAIL"}  ${label}`);
}

// ─── Pure: the community detector ───────────────────────────────────

function clique(ids) {
  const out = [];
  for (let i = 0; i < ids.length; i++)
    for (let j = i + 1; j < ids.length; j++) out.push([ids[i], ids[j]]);
  return out;
}

{
  // Two 5-cliques joined by one edge: two groups of five, not one of ten.
  const edges = [...clique([0, 1, 2, 3, 4]), ...clique([5, 6, 7, 8, 9]), [4, 5]];
  const g = detectCommunities(10, edges);
  check("two bridged cliques → two groups", new Set(g).size, 2);
  check("left clique is one group", new Set(g.slice(0, 5)).size, 1);
  check("right clique is one group", new Set(g.slice(5)).size, 1);
  truthy("the bridge does not merge them", g[0] !== g[9]);
}
{
  // The same two small circles beside a big UNRELATED network. Scored against
  // the whole graph's size they merge (one bridge outweighs a 13×7 degree
  // product once there are ~50 edges anywhere); a group must not change
  // because strangers elsewhere made friends.
  const strangers = clique(Array.from({ length: 40 }, (_, i) => 7 + i)); // 780 edges
  const g = detectCommunities(47, [...clique([0, 1, 2, 3]), ...clique([4, 5, 6]), [3, 4], ...strangers]);
  truthy("small circles stay apart beside a big unrelated network", g[0] !== g[4]);
  check("…and each stays whole", new Set(g.slice(0, 4)).size + new Set(g.slice(4, 7)).size, 2);
  check("…and the strangers are one group", new Set(g.slice(7)).size, 1);
}
{
  // The classic ring of cliques: six triangles, each tied to the next by one
  // edge. Modularity's resolution limit is what a careless implementation
  // trips on here (merging neighbours); six is the right answer at this size.
  const edges = [];
  for (let t = 0; t < 6; t++) {
    const base = t * 3;
    edges.push(...clique([base, base + 1, base + 2]));
    edges.push([base + 2, ((t + 1) % 6) * 3]);
  }
  const g = detectCommunities(18, edges);
  check("ring of six triangles → six groups", new Set(g).size, 6);
  let together = 0;
  for (let t = 0; t < 6; t++)
    if (g[t * 3] === g[t * 3 + 1] && g[t * 3] === g[t * 3 + 2]) together++;
  check("each triangle kept whole", together, 6);
}
{
  const g = detectCommunities(3, []);
  check("no edges → everyone their own group", new Set(g).size, 3);
  check("empty graph → empty partition", detectCommunities(0, []).length, 0);
  // Biggest group is numbered 0.
  const big = detectCommunities(5, [...clique([2, 3, 4]), [0, 1]]);
  check("biggest group numbered first", big[2], 0);
  // Same graph, same answer — the colours must not reshuffle per reload.
  const e = [...clique([0, 1, 2, 3]), ...clique([4, 5, 6]), [0, 4], [7, 8]];
  check(
    "deterministic",
    JSON.stringify(detectCommunities(9, e)),
    JSON.stringify(detectCommunities(9, e)),
  );
}
{
  const comp = connectedComponents(5, [[0, 1], [1, 2], [3, 4]]);
  check("components: 0~2 joined", comp[0] === comp[2], true);
  check("components: 3,4 apart from 0", comp[3] === comp[0], false);
}

// ─── Seeded world ───────────────────────────────────────────────────

const ET_DAY = new Intl.DateTimeFormat("en-CA", {
  timeZone: "America/New_York",
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
});
const dayOffset = (n) => ET_DAY.format(new Date(Date.now() - n * 86_400_000));

async function cleanup() {
  await db.query(`DELETE FROM workouts WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(
    `DELETE FROM friendships WHERE user_id = ANY($1::text[]) OR friend_id = ANY($1::text[])`,
    [ALL],
  );
  await db.query(`DELETE FROM notification_settings WHERE user_id = ANY($1::text[])`, [ALL]);
  await db.query(`DELETE FROM users WHERE user_id = ANY($1::text[])`, [ALL]);
}

let wseq = 0;
/** One walk; `route` = [[lat, lng], ...] or null for a routeless walk. */
async function walk(user, daysAgo, route, { deleted = false } = {}) {
  const id = `net-w-${++wseq}`;
  const day = dayOffset(daysAgo);
  await db.query(
    `INSERT INTO workouts (workout_id, user_id, distance, local_date, date, timezone_offset,
                           workout_type, device_end_date, calories, total_duration, created_at,
                           deleted_at, source)
     VALUES ($1, $2, 1.1, $3::date, $3::date, -300, 'walking',
             $3::date + INTERVAL '18 hours' + ($4::int || ' minutes')::interval, 100, 900,
             NOW() - ($5::int || ' days')::interval,
             CASE WHEN $6::boolean THEN NOW() END, 'healthkit')`,
    [id, user, day, wseq, daysAgo, deleted],
  );
  if (route) {
    await db.query(
      `INSERT INTO workout_routes (workout_id, route, point_count) VALUES ($1, $2::jsonb, $3)`,
      [id, JSON.stringify(route), route.length],
    );
  }
}

/** A three-point route whose MIDDLE is the city and whose ends are a
 *  degree away — a map that read the start would put them somewhere else. */
const around = ([lat, lng]) => [
  [lat + 1, lng + 1],
  [lat, lng],
  [lat + 1, lng + 1],
];

const NYC = [40.71, -74.0];
const LONDON = [51.5, -0.12];
const TOKYO = [35.68, 139.69];
const SYDNEY = [-33.87, 151.21];

async function seed() {
  for (const [i, id] of ALL.entries()) {
    await db.query(
      `INSERT INTO users (user_id, username, apple_sub, email, current_streak, created_at, goal_miles)
       VALUES ($1, $2, $3, $4, 0, NOW() - ($5::int || ' days')::interval, 1.0)`,
      [id, id, id, `${id}@example.com`, 60 - i * 3],
    );
  }
  // net-a3 names net-a1 at onboarding — the tree draws that as a referral.
  await db.query(
    `UPDATE users SET referral_source = 'friend', referral_detail = '@NET-A1' WHERE user_id = 'net-a3'`,
  );

  const both = async (a, b) => {
    await db.query(
      `INSERT INTO friendships (user_id, friend_id, status, created_at)
       VALUES ($1, $2, 'accepted', NOW() - INTERVAL '10 days'),
              ($2, $1, 'accepted', NOW() - INTERVAL '9 days')`,
      [a, b],
    );
  };
  for (const [a, b] of clique(A)) await both(a, b);
  for (const [a, b] of clique(B)) await both(a, b);
  await both(C[0], C[1]);
  // The bridge exists in ONE direction only: either accepted row is a
  // friendship, and nothing may assume the pair is symmetric.
  await db.query(
    `INSERT INTO friendships (user_id, friend_id, status, created_at)
     VALUES ('net-a1', 'net-b1', 'accepted', NOW() - INTERVAL '5 days')`,
  );
  // A pending request is not a friendship — from a nobody, AND between two
  // people already in the graph (where it would otherwise join two islands).
  await db.query(
    `INSERT INTO friendships (user_id, friend_id, status)
     VALUES ('net-pend', 'net-a2', 'pending'), ('net-a2', 'net-c1', 'pending')`,
  );

  // a1: three recent walks in New York, the latest one a London trip.
  // Their place is where they MOSTLY walk, not where they last walked.
  await walk("net-a1", 6, around(NYC));
  await walk("net-a1", 5, around(NYC));
  await walk("net-a1", 4, around(NYC));
  await walk("net-a1", 1, around(LONDON));
  // b1: eight OLD Sydney walks, then six recent Tokyo ones. All-time they're
  // Sydney (8 > 6); over their last ten (6 Tokyo + 4 Sydney) they're Tokyo.
  for (let d = 0; d < 8; d++) await walk("net-b1", 200 + d, around(SYDNEY));
  for (let d = 0; d < 6; d++) await walk("net-b1", 40 + d, around(TOKYO));
  // c1: their only routed walk was deleted, plus an indoor walk → unlocated.
  await walk("net-c1", 3, around(LONDON), { deleted: true });
  await walk("net-c1", 2, null);
  // c2: a route of (0, 0) fixes is a null location, not the Atlantic.
  await walk("net-c2", 2, [[0, 0], [0, 0], [0, 0]]);
  // iso reports a timezone but no route.
  await db.query(
    `INSERT INTO notification_settings (user_id, timezone_offset_minutes) VALUES ('net-iso', -480)`,
  );
}

const snapshot = async () => {
  resetNetworkCaches();
  return { net: await getFriendNetwork(), loc: await getUserLocations() };
};

const cellOf = ([lat, lng]) => {
  const c = LOCATION_CELL_DEGREES;
  return `${(Math.floor(lat / c) + 0.5) * c},${(Math.floor(lng / c) + 0.5) * c}`;
};
const cellMap = (loc) =>
  new Map(loc.cells.map((c) => [`${c.lat},${c.lng}`, c]));
const cellDelta = (before, after, city, key = "users") =>
  (cellMap(after.loc).get(cellOf(city))?.[key] ?? 0) -
  (cellMap(before.loc).get(cellOf(city))?.[key] ?? 0);
const offsetUsers = (loc, off) =>
  loc.unlocated_by_offset.find((o) => o.offset_minutes === off)?.users ?? 0;

try {
  await cleanup();

  // A quiet table must not throw (median/max over nothing, no cells).
  const before = await snapshot();
  truthy("baseline network loads", Array.isArray(before.net.nodes));
  truthy("baseline locations load", Array.isArray(before.loc.cells));

  await seed();
  const after = await snapshot();
  const s0 = before.net.summary;
  const s1 = after.net.summary;

  // ── Friend graph ──
  check("total users +11", s1.total_users - s0.total_users, 11);
  check("connected users +9", s1.connected_users - s0.connected_users, 9);
  check("isolated users +2 (no friends, pending only)", s1.isolated_users - s0.isolated_users, 2);
  // 6 (clique) + 3 (triangle) + 1 (bridge) + 1 (pair) — each pair ONCE.
  check("friendships +11, one edge per pair", s1.friendships - s0.friendships, 11);
  check("pending requests +2", s1.pending_requests - s0.pending_requests, 2);
  check("islands +2 (A∪B and C)", s1.islands - s0.islands, 2);

  const { nodes, edges, groups } = after.net;
  const at = new Map(nodes.map((n, i) => [n.id, i]));
  const node = (id) => nodes[at.get(id)];
  truthy("everyone with a friend is a node", [...A, ...B, ...C].every((id) => at.has(id)));
  check("no-friends user is not a node", at.has(ISO), false);
  check("pending-only user is not a node", at.has(PEND), false);

  check("a1 has 4 friends (3 + the one-way bridge)", node("net-a1").friends, 4);
  check("b1 has 3 friends", node("net-b1").friends, 3);
  check("a2 has 3 friends (pending not counted)", node("net-a2").friends, 3);

  const bridge = edges.filter(
    ([a, b]) =>
      [nodes[a].id, nodes[b].id].sort().join() === "net-a1,net-b1",
  );
  check("the bridge is one edge", bridge.length, 1);
  truthy("edges are a < b", edges.every(([a, b]) => a < b));
  truthy("edge carries a since day", typeof bridge[0]?.[2] === "string");

  const gA = node("net-a1").group;
  const gB = node("net-b1").group;
  const gC = node("net-c1").group;
  truthy("the clique is one group", A.every((id) => node(id).group === gA));
  truthy("the triangle is one group", B.every((id) => node(id).group === gB));
  truthy("the bridge does not merge the two", gA !== gB);
  check("the island pair is one group", node("net-c2").group, gC);
  truthy("the island is its own group", gC !== gA && gC !== gB);
  check("clique group: 4 members", groups[gA].size, 4);
  check("clique group: 6 inside edges", groups[gA].internal_edges, 6);
  check("clique group: 1 edge out", groups[gA].external_edges, 1);
  check("clique hub is a1 (ties inside, most overall)", nodes[groups[gA].hub].id, "net-a1");
  check("a1 and b1 share an island", node("net-a1").island, node("net-b1").island);
  truthy("the pair is on another island", node("net-c1").island !== node("net-a1").island);
  check(
    "a3's typed '@NET-A1' resolves to a1",
    nodes[node("net-a3").referred_by]?.id,
    "net-a1",
  );
  check("nobody referred a2", node("net-a2").referred_by, null);

  // ── Map ──
  const l0 = before.loc.summary;
  const l1 = after.loc.summary;
  check("located +2 (a1, b1)", l1.located_users - l0.located_users, 2);
  // a2..a4, b2, b3, c1 (deleted route + indoor), iso, pend. c2 HAS a routed
  // walk, it's just unusable, so it's in neither count.
  check("unlocated +8", l1.unlocated_users - l0.unlocated_users, 8);
  check("New York cell +1", cellDelta(before, after, NYC), 1);
  check("New York counts them as active", cellDelta(before, after, NYC, "active"), 1);
  check("London trip did not move a1", cellDelta(before, after, LONDON), 0);
  check("Tokyo +1 (last ten walks, not all time)", cellDelta(before, after, TOKYO), 1);
  check("Sydney +0", cellDelta(before, after, SYDNEY), 0);
  check("Tokyo walks are 40+ days old → not active", cellDelta(before, after, TOKYO, "active"), 0);
  check(
    "the route's start (a degree off) is not where they're placed",
    cellDelta(before, after, [NYC[0] + 1, NYC[1] + 1]),
    0,
  );
  check("null island stays empty", cellDelta(before, after, [0, 0]), 0);
  check(
    "unlocated by offset: iso at UTC−8",
    offsetUsers(after.loc, -480) - offsetUsers(before.loc, -480),
    1,
  );
  truthy(
    "cells never carry a user id",
    after.loc.cells.every((c) => Object.keys(c).sort().join() === "active,lat,lng,users"),
  );
} finally {
  await cleanup();
  await db.close();
}

if (failures) {
  console.error(`\n${failures} check(s) failed`);
  process.exit(1);
}
console.log("\nadmin network: all checks passed");
process.exit(0);
