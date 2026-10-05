/**
 * The admin dashboard's Network tab: who is friends with whom, which friend
 * GROUPS that forms, and where on the map people walk.
 *
 * Two loaders, both behind a TTL cache like every other admin panel (these
 * read production tables and the dashboard refetches on each tab mount):
 *
 *   getFriendNetwork  — every person with at least one accepted friend, every
 *                       friendship as ONE undirected edge, and the friend
 *                       groups found in it (Louvain community detection, done
 *                       here rather than in the browser so the check script
 *                       can pin it against a seeded world).
 *   getUserLocations  — a coarse grid of where people walk. There is no
 *                       location column on `users`; the only location the app
 *                       ever records is a GPS route, so a person's place is the
 *                       grid cell their recent routes most often pass through.
 *
 * Location is AGGREGATE ONLY by construction: the SQL returns cells and
 * counts, never a per-person coordinate, and a cell is LOCATION_CELL_DEGREES
 * wide (~17 miles) — city scale, never a street. Stealth walks contribute
 * nothing because they have no `workout_routes` row at all.
 */

import { PostgresService } from "./DbService.js";
import { PERSON_REFERRAL_SOURCES, referralHandleSql } from "./userService.js";
import { TODAY_ET_DATE_SQL } from "./dailyResetTime.js";

const db = PostgresService.getInstance();

/** Same counting rule as every other panel: not deleted, not excluded. */
const COUNTING_WORKOUT = `w.deleted_at IS NULL AND w.exclusion_reason IS NULL`;

// ─── Cache ──────────────────────────────────────────────────────────

const cacheResets: (() => void)[] = [];

/** Drop the caches. Only for scripts/admin-network-check.mjs. */
export function resetNetworkCaches(): void {
  for (const reset of cacheResets) reset();
}

function cached<T>(ttlMs: number, load: () => Promise<T>): () => Promise<T> {
  let hit: { at: number; data: T } | null = null;
  let inflight: Promise<T> | null = null;
  cacheResets.push(() => {
    hit = null;
  });
  return async () => {
    if (hit && Date.now() - hit.at < ttlMs) return hit.data;
    if (!inflight) {
      inflight = load()
        .then((data) => {
          hit = { at: Date.now(), data };
          return data;
        })
        .finally(() => {
          inflight = null;
        });
    }
    return inflight;
  };
}

// ─── Community detection (Louvain) ──────────────────────────────────

/**
 * Friend groups: a partition of the graph that maximises modularity — more
 * friendships inside each group than you'd expect by chance. Louvain is the
 * standard way to find one: move each person into whichever neighbouring
 * group gains the most, collapse the groups into single nodes, repeat until
 * nothing moves.
 *
 * Deterministic on purpose: nodes are visited in index order (the caller
 * sorts them by user id) and ties keep a node where it is, so the same graph
 * always draws the same groups and the colours don't reshuffle per reload.
 *
 * Scored PER SEPARATE NETWORK (connected component), never against the whole
 * graph. Modularity compares a group's inside edges with what the graph's
 * TOTAL size predicts, so scored globally, two tight circles joined by one
 * friendship merge as soon as enough unrelated friendships exist elsewhere —
 * a 4-person and a 3-person circle were one group in a graph of 1,500
 * friendships and two in a graph of 11. Groups never span networks anyway,
 * so each network is scored against its own size, and a group can't change
 * because strangers on another network made friends.
 *
 * Returns one group index per node, numbered biggest group first. A node with
 * no edges is its own group.
 */
export function detectCommunities(
  nodeCount: number,
  edges: readonly (readonly [number, number])[],
): number[] {
  // Level graph: weighted adjacency + self-loop weight (the edges a collapsed
  // group holds inside itself).
  let n = nodeCount;
  let adj: Map<number, number>[] = Array.from({ length: n }, () => new Map());
  let self: number[] = new Array(n).fill(0);
  const valid: (readonly [number, number])[] = [];
  for (const [a, b] of edges) {
    if (a === b || a < 0 || b < 0 || a >= n || b >= n) continue;
    valid.push([a, b]);
    adj[a].set(b, (adj[a].get(b) ?? 0) + 1);
    adj[b].set(a, (adj[b].get(a) ?? 0) + 1);
  }
  // Which separate network each level-node belongs to (see above).
  let network = connectedComponents(nodeCount, valid);

  // membership[original node] = node at the current level.
  let membership = Array.from({ length: nodeCount }, (_, i) => i);

  for (let level = 0; level < 32; level++) {
    const degree = new Array(n).fill(0);
    // Twice the edge weight of each network: the "2m" of its modularity.
    const m2Of = new Map<number, number>();
    let total = 0;
    for (let i = 0; i < n; i++) {
      let k = 2 * self[i];
      for (const w of adj[i].values()) k += w;
      degree[i] = k;
      total += k;
      m2Of.set(network[i], (m2Of.get(network[i]) ?? 0) + k);
    }
    if (total === 0) break;

    const comm = Array.from({ length: n }, (_, i) => i);
    const tot = degree.slice();
    let movedAny = false;

    for (let pass = 0; pass < 64; pass++) {
      let moved = false;
      for (let i = 0; i < n; i++) {
        const own = comm[i];
        const ki = degree[i];
        if (ki === 0) continue;
        const m2 = m2Of.get(network[i])!;
        // Weight from i into each neighbouring group.
        const toComm = new Map<number, number>();
        for (const [j, w] of adj[i]) {
          toComm.set(comm[j], (toComm.get(comm[j]) ?? 0) + w);
        }
        // Take i out of its group, then put it back wherever gains most.
        tot[own] -= ki;
        let best = own;
        let bestGain = (toComm.get(own) ?? 0) - (tot[own] * ki) / m2;
        for (const [c, wIn] of toComm) {
          if (c === own) continue;
          const gain = wIn - (tot[c] * ki) / m2;
          // Strictly better only, and a stable tie-break on the group id,
          // so the result never depends on Map iteration order.
          if (gain > bestGain + 1e-12 || (Math.abs(gain - bestGain) <= 1e-12 && best !== own && c < best)) {
            best = c;
            bestGain = gain;
          }
        }
        tot[best] += ki;
        if (best !== own) {
          comm[i] = best;
          moved = true;
          movedAny = true;
        }
      }
      if (!moved) break;
    }

    if (!movedAny) break;

    // Collapse each group into one node.
    const renumber = new Map<number, number>();
    for (let i = 0; i < n; i++) {
      if (!renumber.has(comm[i])) renumber.set(comm[i], renumber.size);
    }
    const nextN = renumber.size;
    const nextAdj: Map<number, number>[] = Array.from(
      { length: nextN },
      () => new Map(),
    );
    const nextSelf: number[] = new Array(nextN).fill(0);
    const nextNetwork: number[] = new Array(nextN).fill(0);
    for (let i = 0; i < n; i++) {
      const ci = renumber.get(comm[i])!;
      nextSelf[ci] += self[i];
      nextNetwork[ci] = network[i];
      for (const [j, w] of adj[i]) {
        if (j < i) continue; // each undirected edge once
        const cj = renumber.get(comm[j])!;
        if (ci === cj) {
          nextSelf[ci] += w;
        } else {
          nextAdj[ci].set(cj, (nextAdj[ci].get(cj) ?? 0) + w);
          nextAdj[cj].set(ci, (nextAdj[cj].get(ci) ?? 0) + w);
        }
      }
    }
    membership = membership.map((node) => renumber.get(comm[node])!);
    n = nextN;
    adj = nextAdj;
    self = nextSelf;
    network = nextNetwork;
  }

  // Number groups biggest-first; ties by their lowest member, so stable.
  const sizes = new Map<number, { size: number; first: number }>();
  membership.forEach((g, i) => {
    const s = sizes.get(g);
    if (s) s.size += 1;
    else sizes.set(g, { size: 1, first: i });
  });
  const order = [...sizes.entries()].sort(
    (a, b) => b[1].size - a[1].size || a[1].first - b[1].first,
  );
  const rank = new Map(order.map(([g], idx) => [g, idx]));
  return membership.map((g) => rank.get(g)!);
}

/** Connected components ("islands") via union-find; one id per node. */
export function connectedComponents(
  nodeCount: number,
  edges: readonly (readonly [number, number])[],
): number[] {
  const parent = Array.from({ length: nodeCount }, (_, i) => i);
  const find = (x: number): number => {
    while (parent[x] !== x) {
      parent[x] = parent[parent[x]];
      x = parent[x];
    }
    return x;
  };
  for (const [a, b] of edges) {
    const ra = find(a);
    const rb = find(b);
    if (ra !== rb) parent[Math.max(ra, rb)] = Math.min(ra, rb);
  }
  return parent.map((_, i) => find(i));
}

// ─── Friend network ─────────────────────────────────────────────────

export interface NetworkNode {
  id: string;
  username: string | null;
  name: string | null;
  /** Signup day (ET), YYYY-MM-DD. */
  joined: string;
  /** Last day with a counting workout, YYYY-MM-DD, or null. */
  last_active: string | null;
  /** Index into `nodes` of the person they named at onboarding, if that
   *  person is in this graph. Resolved exactly like the referral graph. */
  referred_by: number | null;
  friends: number;
  group: number;
  island: number;
}

export interface NetworkGroup {
  id: number;
  size: number;
  /** Friendships with both ends inside the group. */
  internal_edges: number;
  /** Friendships leaving the group. */
  external_edges: number;
  /** Index of the member with the most friends inside the group. */
  hub: number;
  /** Members active in the last 7 days. */
  active_7d: number;
}

export interface FriendNetwork {
  summary: {
    total_users: number;
    connected_users: number;
    isolated_users: number;
    friendships: number;
    groups: number;
    islands: number;
    largest_island: number;
    median_friends: number;
    max_friends: number;
    pending_requests: number;
  };
  nodes: NetworkNode[];
  /** [a, b, since] — node indexes, a < b, since = YYYY-MM-DD or null. */
  edges: [number, number, string | null][];
  /** Biggest first; `group` on a node indexes this array. */
  groups: NetworkGroup[];
}

async function loadFriendNetwork(): Promise<FriendNetwork> {
  // One undirected edge per pair. Acceptance writes a row in each direction,
  // but nothing here assumes both exist — either accepted row is a friendship.
  // `since` is the LATER of the two rows: the reverse row is written at
  // acceptance, which is when they actually became friends.
  const pairs = await db.query<{ a: string; b: string; since: string | null }>(`
    SELECT LEAST(f.user_id, f.friend_id) AS a,
           GREATEST(f.user_id, f.friend_id) AS b,
           to_char(MAX(f.created_at) AT TIME ZONE 'America/New_York', 'YYYY-MM-DD') AS since
    FROM friendships f
    WHERE f.status = 'accepted' AND f.user_id <> f.friend_id
    GROUP BY 1, 2
  `);

  const people = await db.query<{
    user_id: string;
    username: string | null;
    name: string | null;
    joined: string;
    last_active: string | null;
    referrer_id: string | null;
  }>(
    `
    WITH members AS (
      SELECT f.user_id FROM friendships f WHERE f.status = 'accepted'
      UNION
      SELECT f.friend_id FROM friendships f WHERE f.status = 'accepted'
    )
    SELECT u.user_id, u.username,
           NULLIF(TRIM(COALESCE(u.first_name, '') || ' ' || COALESCE(u.last_name, '')), '') AS name,
           to_char(u.created_at AT TIME ZONE 'America/New_York', 'YYYY-MM-DD') AS joined,
           (SELECT MAX(w.local_date)::text FROM workouts w
             WHERE w.user_id = u.user_id AND ${COUNTING_WORKOUT}) AS last_active,
           -- The referral graph's own precedence: a typed name that IS a
           -- username resolves to that account; an alias only fills the gap.
           CASE WHEN u.referral_source = ANY($1::text[])
                     AND COALESCE(btrim(u.referral_detail), '') <> ''
                THEN COALESCE(ru.user_id, au.user_id) END AS referrer_id
    FROM members m
    JOIN users u ON u.user_id = m.user_id
    LEFT JOIN users ru ON lower(ru.username) = ${referralHandleSql("u.referral_detail")}
    LEFT JOIN referral_aliases ra ON ra.alias = ${referralHandleSql("u.referral_detail")}
    LEFT JOIN users au ON au.user_id = ra.user_id
    ORDER BY u.user_id
  `,
    [[...PERSON_REFERRAL_SOURCES]],
  );

  const [{ total_users, pending_requests }] = await db.query<{
    total_users: number;
    pending_requests: number;
  }>(`
    SELECT (SELECT COUNT(*)::int FROM users) AS total_users,
           (SELECT COUNT(*)::int FROM friendships WHERE status = 'pending') AS pending_requests
  `);

  // A users row can carry several aliases' worth of LEFT JOIN matches only if
  // the alias table held duplicates (it's keyed on alias), so one row per id —
  // but dedupe anyway rather than trust it.
  const index = new Map<string, number>();
  const unique = people.filter((p) => {
    if (index.has(p.user_id)) return false;
    index.set(p.user_id, index.size);
    return true;
  });

  const edges: [number, number, string | null][] = [];
  for (const p of pairs) {
    const a = index.get(p.a);
    const b = index.get(p.b);
    if (a === undefined || b === undefined) continue;
    edges.push(a < b ? [a, b, p.since] : [b, a, p.since]);
  }
  edges.sort((x, y) => x[0] - y[0] || x[1] - y[1]);

  const plain = edges.map(([a, b]) => [a, b] as const);
  const group = detectCommunities(unique.length, plain);
  const islandRoot = connectedComponents(unique.length, plain);

  const degree = new Array(unique.length).fill(0);
  for (const [a, b] of plain) {
    degree[a] += 1;
    degree[b] += 1;
  }

  // Islands numbered biggest first, like groups.
  const islandSize = new Map<number, number>();
  for (const r of islandRoot) islandSize.set(r, (islandSize.get(r) ?? 0) + 1);
  const islandOrder = [...islandSize.entries()].sort(
    (a, b) => b[1] - a[1] || a[0] - b[0],
  );
  const islandRank = new Map(islandOrder.map(([r], i) => [r, i]));

  const activeCutoff = new Date(Date.now() - 7 * 86_400_000)
    .toISOString()
    .slice(0, 10);

  const nodes: NetworkNode[] = unique.map((p, i) => ({
    id: p.user_id,
    username: p.username,
    name: p.name,
    joined: p.joined,
    last_active: p.last_active,
    referred_by:
      p.referrer_id && p.referrer_id !== p.user_id
        ? (index.get(p.referrer_id) ?? null)
        : null,
    friends: degree[i],
    group: group[i],
    island: islandRank.get(islandRoot[i])!,
  }));

  const groupCount = group.length ? Math.max(...group) + 1 : 0;
  const groups: NetworkGroup[] = Array.from({ length: groupCount }, (_, id) => ({
    id,
    size: 0,
    internal_edges: 0,
    external_edges: 0,
    hub: -1,
    active_7d: 0,
  }));
  const innerDegree = new Array(nodes.length).fill(0);
  for (const [a, b] of plain) {
    if (group[a] === group[b]) {
      groups[group[a]].internal_edges += 1;
      innerDegree[a] += 1;
      innerDegree[b] += 1;
    } else {
      groups[group[a]].external_edges += 1;
      groups[group[b]].external_edges += 1;
    }
  }
  nodes.forEach((node, i) => {
    const g = groups[node.group];
    g.size += 1;
    if (node.last_active && node.last_active >= activeCutoff) g.active_7d += 1;
    // Hub: most friends INSIDE the group, then most friends overall, then
    // the lowest index (= lowest user id) so it never flickers.
    if (
      g.hub < 0 ||
      innerDegree[i] > innerDegree[g.hub] ||
      (innerDegree[i] === innerDegree[g.hub] && degree[i] > degree[g.hub])
    ) {
      g.hub = i;
    }
  });

  const sortedDegrees = [...degree].sort((a, b) => a - b);
  const median = sortedDegrees.length
    ? sortedDegrees[Math.floor((sortedDegrees.length - 1) / 2)]
    : 0;

  return {
    summary: {
      total_users,
      connected_users: nodes.length,
      isolated_users: Math.max(total_users - nodes.length, 0),
      friendships: edges.length,
      groups: groups.length,
      islands: islandSize.size,
      largest_island: islandOrder[0]?.[1] ?? 0,
      median_friends: median,
      max_friends: sortedDegrees[sortedDegrees.length - 1] ?? 0,
      pending_requests,
    },
    nodes,
    edges,
    groups,
  };
}

export const getFriendNetwork = cached(60_000, loadFriendNetwork);

// ─── Where people walk ──────────────────────────────────────────────

/** Grid cell size in degrees. 0.25° ≈ 17 miles north–south: a city, not a street. */
export const LOCATION_CELL_DEGREES = 0.25;
/** How many of a person's most recent routed walks place them. */
export const LOCATION_RECENT_ROUTES = 10;
/** "Active" for the map's second count. */
export const LOCATION_ACTIVE_DAYS = 30;

export interface UserLocations {
  cell_degrees: number;
  /** How many recent routed walks place a person (LOCATION_RECENT_ROUTES). */
  routes_per_person: number;
  summary: {
    total_users: number;
    located_users: number;
    active_located_users: number;
    unlocated_users: number;
  };
  /** Cell centres, biggest first. */
  cells: { lat: number; lng: number; users: number; active: number }[];
  /** People with no GPS route, by the UTC offset their phone last reported
   *  (minutes; null = never reported). */
  unlocated_by_offset: { offset_minutes: number | null; users: number }[];
}

async function loadUserLocations(): Promise<UserLocations> {
  const cell = LOCATION_CELL_DEGREES;

  // Per person: the middle point of each of their last N routed walks (the
  // middle, not the start — a start is usually a front door), snapped to the
  // grid; their place is the cell those walks land in MOST often, so one trip
  // away doesn't move them. `point_count` indexes the middle without a second
  // detoast of the route (jsonb_array_length would read the whole value again).
  // The LATERAL walks the (user_id, device_end_date DESC) index and stops
  // at N, so only N routes per person are ever read.
  const cells = await db.query<{
    lat: number;
    lng: number;
    users: number;
    active: number;
  }>(
    `
    WITH recent AS (
      SELECT u.user_id, r.workout_id, r.local_date
      FROM users u
      CROSS JOIN LATERAL (
        SELECT w.workout_id, w.local_date
        FROM workouts w
        WHERE w.user_id = u.user_id AND ${COUNTING_WORKOUT}
          AND EXISTS (SELECT 1 FROM workout_routes x WHERE x.workout_id = w.workout_id)
        ORDER BY w.device_end_date DESC
        LIMIT $2
      ) r
    ),
    picked AS (
      -- The route is read HERE, outside the LATERAL, so no plan can end up
      -- detoasting a route the LIMIT was about to throw away.
      SELECT rc.user_id, rc.local_date,
             wr.route -> GREATEST(wr.point_count / 2, 0) AS mid
      FROM recent rc
      JOIN workout_routes wr ON wr.workout_id = rc.workout_id
    ),
    mids AS (
      SELECT user_id, local_date,
             (mid ->> 0)::float8 AS lat,
             (mid ->> 1)::float8 AS lng
      FROM picked
      WHERE jsonb_typeof(mid) = 'array'
    ),
    snapped AS (
      SELECT user_id,
             floor(lat / $1)::int AS gy,
             floor(lng / $1)::int AS gx,
             COUNT(*) AS n,
             MAX(local_date) AS latest
      FROM mids
      WHERE lat BETWEEN -90 AND 90 AND lng BETWEEN -180 AND 180
        -- (0, 0) is a null fix written as numbers, not a walk in the Atlantic.
        AND NOT (lat = 0 AND lng = 0)
      GROUP BY 1, 2, 3
    ),
    home AS (
      SELECT DISTINCT ON (user_id) user_id, gy, gx
      FROM snapped
      ORDER BY user_id, n DESC, latest DESC, gy, gx
    )
    SELECT ((h.gy + 0.5) * $1)::float8 AS lat,
           ((h.gx + 0.5) * $1)::float8 AS lng,
           COUNT(*)::int AS users,
           COUNT(*) FILTER (
             WHERE (SELECT MAX(w.local_date) FROM workouts w
                     WHERE w.user_id = h.user_id AND ${COUNTING_WORKOUT})
                   >= ${TODAY_ET_DATE_SQL} - $3::int
           )::int AS active
    FROM home h
    GROUP BY h.gy, h.gx
    ORDER BY users DESC, lat, lng
  `,
    [cell, LOCATION_RECENT_ROUTES, LOCATION_ACTIVE_DAYS],
  );

  const [{ total_users }] = await db.query<{ total_users: number }>(
    `SELECT COUNT(*)::int AS total_users FROM users`,
  );

  // Everyone without a single counting routed walk: indoor-only walkers,
  // people whose phone never shared a route, and stealth-only users.
  const unlocated = await db.query<{
    offset_minutes: number | null;
    users: number;
  }>(`
    SELECT ns.timezone_offset_minutes AS offset_minutes, COUNT(*)::int AS users
    FROM users u
    LEFT JOIN notification_settings ns ON ns.user_id = u.user_id
    WHERE NOT EXISTS (
      SELECT 1 FROM workouts w
      JOIN workout_routes wr ON wr.workout_id = w.workout_id
      WHERE w.user_id = u.user_id AND ${COUNTING_WORKOUT}
    )
    GROUP BY 1
    ORDER BY users DESC, offset_minutes NULLS LAST
  `);

  const located = cells.reduce((s, c) => s + c.users, 0);
  return {
    cell_degrees: cell,
    routes_per_person: LOCATION_RECENT_ROUTES,
    summary: {
      total_users,
      located_users: located,
      active_located_users: cells.reduce((s, c) => s + c.active, 0),
      unlocated_users: unlocated.reduce((s, c) => s + c.users, 0),
    },
    cells,
    unlocated_by_offset: unlocated,
  };
}

/** Ten minutes: where people walk moves on the scale of weeks. */
export const getUserLocations = cached(10 * 60_000, loadUserLocations);
