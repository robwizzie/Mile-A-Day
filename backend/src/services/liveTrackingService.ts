import { PostgresService } from "./DbService.js";
import { mileHypeKeyMatchSql } from "./hypeService.js";
import { getUserLocalToday } from "./workoutService.js";

const db = PostgresService.getInstance();

/**
 * Live tracking presence. One row per user in live_tracking_sessions (PK
 * user_id, replaced by upsert on every start), presence decided at query time:
 * an un-ended session whose heartbeat is fresher than this window. 150s ≈
 * three missed 45s client heartbeats — long enough to ride out a flaky
 * cell moment mid-walk, short enough that a force-quit disappears fast.
 *
 * Delivery is PULL-ONLY (heartbeat responses). No push types, no
 * client_features: old builds simply never call these endpoints.
 */
export const LIVE_PRESENCE_WINDOW_SECONDS = 150;

export interface LiveFriend {
  user_id: string;
  username: string | null;
  first_name: string | null;
  last_name: string | null;
  profile_image_url: string | null;
  workout_type: string;
  started_at: string;
  /** The friend's CURRENT local date — the composite key half a viewer needs
   *  to send them a mile hype with zero hype-side changes. */
  local_date: string;
}

export interface LiveHype {
  id: string;
  sender_id: string;
  username: string | null;
  first_name: string | null;
  last_name: string | null;
  profile_image_url: string | null;
  context_label: string | null;
  created_at: string;
}

const ISO_TS = `'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'`;

/** Sanitized workout type — free text from the client, bounded and defaulted. */
function cleanWorkoutType(raw: unknown): string {
  const s = typeof raw === "string" ? raw.trim().toLowerCase() : "";
  if (s === "running" || s === "walking") return s;
  return "walking";
}

/**
 * Start (or replace) the user's live session. A new start overwrites any
 * zombie row from a crashed session — this is also the implicit cleanup.
 */
export async function startSession(
  userId: string,
  workoutType: unknown,
): Promise<{ session_id: string; started_at: string }> {
  const rows = await db.query<{ session_id: string; started_at: string }>(
    `INSERT INTO live_tracking_sessions
       (user_id, session_id, workout_type, started_at, last_seen_at, ended_at)
     VALUES ($1, gen_random_uuid(), $2, NOW(), NOW(), NULL)
     ON CONFLICT (user_id) DO UPDATE SET
       session_id = EXCLUDED.session_id,
       workout_type = EXCLUDED.workout_type,
       started_at = NOW(),
       last_seen_at = NOW(),
       ended_at = NULL
     RETURNING session_id,
       to_char(started_at AT TIME ZONE 'UTC', ${ISO_TS}) AS started_at`,
    [userId, cleanWorkoutType(workoutType)],
  );
  return rows[0];
}

/**
 * Bump the session's liveness and return what the tracker wants to know:
 * which accepted friends are out right now (their share_live_presence pref
 * gates being SEEN, not seeing), and any mile hypes that landed on me since
 * this session started. Returns null when there's no live session matching
 * this session_id — a stale device with an old id gets null, and the client
 * responds by calling start again (or stopping).
 */
export async function heartbeat(
  userId: string,
  sessionId: string,
): Promise<{ friends_out: LiveFriend[]; hypes: LiveHype[] } | null> {
  const bumped = await db.query<{ started_at: Date }>(
    `UPDATE live_tracking_sessions SET last_seen_at = NOW()
     WHERE user_id = $1 AND session_id = $2 AND ended_at IS NULL
     RETURNING started_at`,
    [userId, sessionId],
  );
  if (bumped.length === 0) return null;
  // timestamptz comes back as a JS Date (house rule) — passed straight back
  // in as a parameter below, never string-manipulated.
  const startedAt = bumped[0].started_at;

  const [friendsOut, myLocalDate] = await Promise.all([
    db.query<LiveFriend>(
      `SELECT u.user_id, u.username, u.first_name, u.last_name,
              u.profile_image_url, s.workout_type,
              to_char(s.started_at AT TIME ZONE 'UTC', ${ISO_TS}) AS started_at,
              to_char(
                (NOW() + (COALESCE(
                  (SELECT w2.timezone_offset FROM workouts w2
                   WHERE w2.user_id = f.friend_id
                   ORDER BY w2.device_end_date DESC LIMIT 1),
                  0
                ) || ' minutes')::interval)::date,
                'YYYY-MM-DD'
              ) AS local_date
       FROM friendships f
       JOIN live_tracking_sessions s
         ON s.user_id = f.friend_id
        AND s.ended_at IS NULL
        AND s.last_seen_at > NOW() - INTERVAL '${LIVE_PRESENCE_WINDOW_SECONDS} seconds'
       JOIN users u ON u.user_id = f.friend_id
       LEFT JOIN notification_settings ns ON ns.user_id = f.friend_id
       WHERE f.user_id = $1
         AND f.status = 'accepted'
         AND COALESCE(ns.share_live_presence, TRUE) = TRUE
       ORDER BY s.started_at DESC`,
      [userId],
    ),
    getUserLocalToday(userId),
  ]);

  // Mile hypes that landed on me since this session started. Canonical key
  // matching goes through mileHypeKeyMatchSql against a derived one-row
  // relation — the encoding is never hand-written, and no workouts row needs
  // to exist yet mid-walk (composite-keyed hypes insert without one). A
  // session spanning local midnight stops matching pre-midnight hypes (the
  // key changes); those still arrive via the normal push/inbox path.
  const hypes = await db.query<LiveHype>(
    `SELECT h.id, h.sender_id, u.username, u.first_name, u.last_name,
            u.profile_image_url, h.context_label,
            to_char(h.created_at AT TIME ZONE 'UTC', ${ISO_TS}) AS created_at
     FROM hype_log h
     JOIN users u ON u.user_id = h.sender_id
     CROSS JOIN (SELECT $1::text AS user_id, $2::date AS local_date) me
     WHERE h.target_id = $1
       AND h.context_type = 'mile'
       AND ${mileHypeKeyMatchSql("h", "me")}
       AND h.created_at >= $3
     ORDER BY h.created_at ASC
     LIMIT 50`,
    [userId, myLocalDate, startedAt],
  );

  return { friends_out: friendsOut, hypes };
}

/** End the session. Idempotent — 0 rows (already ended / never started) is fine. */
export async function endSession(
  userId: string,
  sessionId: string,
): Promise<void> {
  await db.query(
    `UPDATE live_tracking_sessions SET ended_at = NOW(), last_seen_at = NOW()
     WHERE user_id = $1 AND session_id = $2 AND ended_at IS NULL`,
    [userId, sessionId],
  );
}
