import { PostgresService } from "./DbService.js";
import { BadRequestError } from "../errors/Errors.js";
import { isStealthNow } from "./stealthService.js";

const db = PostgresService.getInstance();

/**
 * Live routes on a buddy walk: the ONE place a walker's position leaves their
 * phone during a workout, and only because they turned it on for this walk.
 *
 * - A `buddy_live_routes` row IS the consent. No row, nothing stored, nothing
 *   served. Turning it off deletes the row, so "off" also takes back the line.
 * - Reciprocal: you only see the routes of others on the walk once you're
 *   sharing yours.
 * - The hide-start-and-end trim happens on the PHONE, which can do what this
 *   table can't: a point is released only after the walker has moved past it
 *   by their `route_privacy_meters`, so neither end of the walk is ever sent.
 * - Ephemeral: rows go when the walker finishes or leaves and when the session
 *   closes. The lasting route is `workout_routes`, through `servedRouteFrom`.
 *   `sweepStaleLiveRoutes` is the backstop for a phone that simply vanished.
 *
 * Separate from `recordProgress` on purpose: that path is load-bearing at one
 * write per walker per 5 seconds, and this one posts far less often.
 */

/** Points in one upload. The phone sends every ~20s, so this is generous. */
export const MAX_POINTS_PER_POST = 60;
/** Stored per walker. At the phone's 20m spacing this is about 30km. */
export const MAX_POINTS_PER_WALKER = 1500;
/** Served per walker: a map line needs no more, and this is polled. */
export const MAX_POINTS_SERVED = 400;

/** A line no phone has touched for this long belongs to nobody. */
const STALE_AFTER_HOURS = 12;

/** The owner's standing settings that veto sharing. No row reads as defaults. */
function mayShareSql(userExpr: string): string {
  return `NOT EXISTS (
    SELECT 1 FROM notification_settings ns
     WHERE ns.user_id = ${userExpr}
       AND (ns.share_route_maps = false OR ns.workout_visibility = 'private')
  )`;
}

async function maySetting(userId: string): Promise<boolean> {
  const rows = await db.query(`SELECT 1 WHERE ${mayShareSql("$1")}`, [userId]);
  return rows.length > 0;
}

/** Round to 5 decimals (about a metre) and refuse anything that isn't a point. */
function cleanPoints(raw: unknown): [number, number][] {
  if (!Array.isArray(raw) || raw.length === 0) {
    throw new BadRequestError("invalid_points");
  }
  if (raw.length > MAX_POINTS_PER_POST) {
    throw new BadRequestError("too_many_points");
  }
  return raw.map((point) => {
    if (!Array.isArray(point) || point.length !== 2) {
      throw new BadRequestError("invalid_points");
    }
    const [lat, lng] = point;
    if (
      typeof lat !== "number" || typeof lng !== "number" ||
      !Number.isFinite(lat) || !Number.isFinite(lng) ||
      Math.abs(lat) > 90 || Math.abs(lng) > 180
    ) {
      throw new BadRequestError("invalid_points");
    }
    return [Math.round(lat * 1e5) / 1e5, Math.round(lng * 1e5) / 1e5];
  });
}

/** Every Nth point, always keeping the newest so the line reaches the head. */
function thinned(points: [number, number][]): [number, number][] {
  if (points.length <= MAX_POINTS_SERVED) return points;
  const stride = points.length / (MAX_POINTS_SERVED - 1);
  const kept: [number, number][] = [];
  for (let i = 0; i < MAX_POINTS_SERVED - 1; i++) {
    kept.push(points[Math.floor(i * stride)]);
  }
  kept.push(points[points.length - 1]);
  return kept;
}

/** Remove everyone's live line. Called wherever a session closes. */
export async function clearLiveRoutes(sessionId: string): Promise<void> {
  await db.query(`DELETE FROM buddy_live_routes WHERE session_id = $1`, [
    sessionId,
  ]);
}

/** Remove one walker's live line: they finished, left, or turned it off. */
export async function clearLiveRoute(
  sessionId: string,
  userId: string,
): Promise<void> {
  await db.query(
    `DELETE FROM buddy_live_routes WHERE session_id = $1 AND user_id = $2`,
    [sessionId, userId],
  );
}

/** The backstop. Runs when anyone opts in, so it needs no cron of its own. */
export async function sweepStaleLiveRoutes(): Promise<void> {
  await db.query(
    `DELETE FROM buddy_live_routes
      WHERE updated_at < NOW() - make_interval(hours => $1)`,
    [STALE_AFTER_HOURS],
  );
}

export async function setLiveRouteSharing(
  sessionId: string,
  userId: string,
  enabled: boolean,
): Promise<{ sharing: boolean }> {
  if (!enabled) {
    await clearLiveRoute(sessionId, userId);
    return { sharing: false };
  }

  const rows = await db.query<{ location_type: string | null }>(
    `SELECT p.location_type
       FROM buddy_session_participants p
       JOIN buddy_sessions s ON s.id = p.session_id
      WHERE p.session_id = $1 AND p.user_id = $2
        AND p.status IN ('joined', 'ready', 'active')
        AND s.status IN ('lobby', 'active')`,
    [sessionId, userId],
  );
  if (rows.length === 0) throw new BadRequestError("not_active");
  if (rows[0].location_type === "indoor") {
    throw new BadRequestError("route_sharing_unavailable");
  }
  // Refused, never quietly accepted: the app explains why the switch is off.
  if (!(await maySetting(userId)) || (await isStealthNow(userId))) {
    throw new BadRequestError("route_sharing_unavailable");
  }

  await db.query(
    `INSERT INTO buddy_live_routes (session_id, user_id)
     VALUES ($1, $2)
     ON CONFLICT (session_id, user_id) DO UPDATE SET updated_at = NOW()`,
    [sessionId, userId],
  );
  await sweepStaleLiveRoutes();
  return { sharing: true };
}

export async function appendLiveRoutePoints(
  sessionId: string,
  userId: string,
  rawPoints: unknown,
): Promise<{ sharing: boolean; accepted: number }> {
  const points = cleanPoints(rawPoints);

  // Re-checked on every post: a setting flipped mid-walk takes effect at once,
  // and takes what was already sent with it.
  if (!(await maySetting(userId)) || (await isStealthNow(userId))) {
    await clearLiveRoute(sessionId, userId);
    return { sharing: false, accepted: 0 };
  }

  const updated = await db.query<{ point_count: number }>(
    `UPDATE buddy_live_routes r
        SET points = r.points || $3::jsonb,
            point_count = r.point_count + $4::integer,
            updated_at = NOW()
       FROM buddy_sessions s, buddy_session_participants p
      WHERE r.session_id = $1 AND r.user_id = $2
        AND s.id = r.session_id AND s.status = 'active'
        AND p.session_id = r.session_id AND p.user_id = r.user_id
        AND p.status = 'active'
        AND r.point_count + $4::integer <= $5::integer
      RETURNING r.point_count`,
    [
      sessionId,
      userId,
      JSON.stringify(points),
      points.length,
      MAX_POINTS_PER_WALKER,
    ],
  );
  if (updated.length > 0) return { sharing: true, accepted: points.length };

  // Not stored: either they aren't sharing, or the line is full. Only the
  // second is still sharing, and the phone should stop sending either way.
  const row = await db.query(
    `SELECT 1 FROM buddy_live_routes WHERE session_id = $1 AND user_id = $2`,
    [sessionId, userId],
  );
  return { sharing: row.length > 0, accepted: 0 };
}

export async function getLiveRoutes(
  sessionId: string,
  viewerId: string,
): Promise<{
  sharing: boolean;
  routes: { user_id: string; points: [number, number][] }[];
}> {
  const mine = await db.query(
    `SELECT 1
       FROM buddy_live_routes r
       JOIN buddy_session_participants p
         ON p.session_id = r.session_id AND p.user_id = r.user_id
       JOIN buddy_sessions s ON s.id = r.session_id
      WHERE r.session_id = $1 AND r.user_id = $2
        AND p.status IN ('joined', 'ready', 'active')
        AND s.status IN ('lobby', 'active')`,
    [sessionId, viewerId],
  );
  if (mine.length === 0) return { sharing: false, routes: [] };

  const rows = await db.query<{
    user_id: string;
    points: [number, number][];
  }>(
    `SELECT r.user_id, r.points
       FROM buddy_live_routes r
       JOIN buddy_session_participants p
         ON p.session_id = r.session_id AND p.user_id = r.user_id
      WHERE r.session_id = $1
        AND r.user_id <> $2
        AND r.point_count > 0
        AND p.status = 'active'
        AND ${mayShareSql("r.user_id")}
        AND NOT EXISTS (
          SELECT 1 FROM user_blocks b
           WHERE (b.blocker_id = $2 AND b.blocked_id = r.user_id)
              OR (b.blocker_id = r.user_id AND b.blocked_id = $2)
        )
      ORDER BY r.user_id`,
    [sessionId, viewerId],
  );
  return {
    sharing: true,
    routes: rows.map((row) => ({
      user_id: row.user_id,
      points: thinned(row.points),
    })),
  };
}
