import { PostgresService } from "./DbService.js";
import { mileHypeKeyMatchSql } from "./hypeService.js";
import { getUserLocalToday } from "./workoutService.js";
import { buddySessionsEnabled } from "./buddyFeatures.js";
import { BUDDY_MAX_PARTICIPANTS } from "../types/buddy.js";

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
  /** Live miles as of their last heartbeat. Monotonic. */
  distance_miles: number;
  /** THEIR daily goal, so progress is drawn against the right target. */
  goal_miles: number;
  /** The friend's CURRENT local date — the composite key half a viewer needs
   *  to send them a mile hype with zero hype-side changes. */
  local_date: string;
}

/**
 * A friend who is out right now, as seen from the Friends tab.
 *
 * Same presence source as `LiveFriend`, plus the buddy-room fields, because the
 * two questions are asked at different moments and only one of them was
 * answerable before. `heartbeat` tells the tracker who else is out while YOU
 * are already walking; this tells the Friends tab before you've started —
 * which is the moment the answer can actually change what you do.
 *
 * The buddy fields are null for a friend walking solo, and a solo walker is the
 * single best person to start a buddy walk with, so the client renders both:
 * "Join" for a room, "Ask to walk" for a solo walker.
 */
export interface FriendOutNow {
  user_id: string;
  username: string | null;
  first_name: string | null;
  last_name: string | null;
  profile_image_url: string | null;
  workout_type: string;
  started_at: string;
  /** Live miles as of their last heartbeat. Monotonic. */
  distance_miles: number;
  /** THEIR daily goal, so progress is drawn against the right target. */
  goal_miles: number;
  /** The friend's current local date, so a Friends-tab hype can land on the
   * active walk/run screen through the same mile-context path as heartbeat
   * hypes. */
  local_date: string;
  /** Non-null only when they're in a buddy room with space left. */
  buddy_session_id: string | null;
  buddy_join_code: string | null;
  buddy_mode: string | null;
  buddy_participant_count: number | null;
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
       distance_miles = 0,
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
  distanceMiles?: number,
): Promise<{ friends_out: LiveFriend[]; hypes: LiveHype[] } | null> {
  // GREATEST, never assignment: heartbeats can arrive out of order, and a
  // friend's live number is being watched by other people. It may stall, it
  // must never tick backwards. A missing/NaN value leaves the stored figure
  // alone rather than resetting it to zero.
  const reported =
    typeof distanceMiles === "number" && Number.isFinite(distanceMiles)
      ? Math.max(0, distanceMiles)
      : null;
  const bumped = await db.query<{ started_at: Date }>(
    `UPDATE live_tracking_sessions
        SET last_seen_at = NOW(),
            distance_miles = GREATEST(distance_miles, COALESCE($3, distance_miles))
     WHERE user_id = $1 AND session_id = $2 AND ended_at IS NULL
     RETURNING started_at`,
    [userId, sessionId, reported],
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
              s.distance_miles,
              u.goal_miles::float AS goal_miles,
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

/**
 * Friends out right now, for a caller who is NOT tracking.
 *
 * A deliberate SIBLING of `heartbeat`'s friends-out query rather than a
 * refactor of it. The heartbeat runs every 45s for everyone mid-walk; a bug
 * introduced while generalising it would take presence down during the exact
 * moment it matters. Duplicating ~15 lines of SELECT is the cheaper trade.
 *
 * Privacy is unchanged from the heartbeat's: `share_live_presence` gates being
 * SEEN (default true, opt-out), and only accepted friends are ever returned.
 * The block check is belt-and-braces — `blockUser` tears the friendship down
 * too, but that teardown is best-effort inside a try/catch, and every other
 * social query in the codebase filters blocks in both directions regardless.
 *
 * `buddySessionsEnabled` gates only the buddy DECORATION. Presence itself
 * shipped unflagged, so a caller with buddy off still gets their friends.
 */
export async function friendsOutNow(userId: string): Promise<FriendOutNow[]> {
  const buddyDecoration = buddySessionsEnabled()
    ? `LEFT JOIN LATERAL (
         SELECT bs.id, bs.join_code, bs.mode,
                (SELECT COUNT(*)::int FROM buddy_session_participants c
                   WHERE c.session_id = bs.id
                     AND c.status NOT IN ('left', 'declined')) AS participant_count
           FROM buddy_sessions bs
           JOIN buddy_session_participants theirs
             ON theirs.session_id = bs.id
            AND theirs.user_id = f.friend_id
            AND theirs.status NOT IN ('left', 'declined')
          WHERE bs.status IN ('lobby', 'active')
            -- Same window getJoinableFriendSessions uses, and it must stay the
            -- same one: this row's Join button posts to that endpoint, so a
            -- narrower bound here just hides an offer the server would accept
            -- and a wider one draws a button that 400s. A running walk is
            -- joinable while anyone is still in it; a lobby until the
            -- abandoned-lobby sweep would have cancelled it.
            AND (
              (bs.status = 'active' AND EXISTS (
                 SELECT 1 FROM buddy_session_participants live
                  WHERE live.session_id = bs.id AND live.status = 'active'
               ))
              OR (bs.status = 'lobby'
                  AND bs.created_at > NOW() - INTERVAL '3 hours')
            )
            -- Already in it? Then it isn't an offer.
            AND NOT EXISTS (
              SELECT 1 FROM buddy_session_participants mine
               WHERE mine.session_id = bs.id AND mine.user_id = $1
                 AND mine.status NOT IN ('left', 'declined')
            )
            AND (SELECT COUNT(*) FROM buddy_session_participants c
                  WHERE c.session_id = bs.id
                    AND c.status NOT IN ('left', 'declined')) < ${BUDDY_MAX_PARTICIPANTS}
          ORDER BY COALESCE(bs.started_at, bs.created_at) DESC
          LIMIT 1
       ) room ON TRUE`
    : `LEFT JOIN LATERAL (SELECT NULL::varchar AS id, NULL::varchar AS join_code,
                                 NULL::text AS mode, NULL::int AS participant_count
       ) room ON TRUE`;

  return db.query<FriendOutNow>(
    `SELECT u.user_id, u.username, u.first_name, u.last_name,
            u.profile_image_url, s.workout_type,
            to_char(s.started_at AT TIME ZONE 'UTC', ${ISO_TS}) AS started_at,
            s.distance_miles,
            -- THEIR goal, not the viewer's. A friend on a 2-mile goal rendered
            -- against a 1-mile bar reads as finished when they're halfway.
            u.goal_miles::float AS goal_miles,
            to_char(
              (NOW() + (COALESCE(
                (SELECT w2.timezone_offset FROM workouts w2
                 WHERE w2.user_id = f.friend_id
                 ORDER BY w2.device_end_date DESC LIMIT 1),
                0
              ) || ' minutes')::interval)::date,
              'YYYY-MM-DD'
            ) AS local_date,
            room.id AS buddy_session_id,
            room.join_code AS buddy_join_code,
            room.mode AS buddy_mode,
            room.participant_count AS buddy_participant_count
       FROM friendships f
       JOIN live_tracking_sessions s
         ON s.user_id = f.friend_id
        AND s.ended_at IS NULL
        AND s.last_seen_at > NOW() - INTERVAL '${LIVE_PRESENCE_WINDOW_SECONDS} seconds'
       JOIN users u ON u.user_id = f.friend_id
       LEFT JOIN notification_settings ns ON ns.user_id = f.friend_id
       ${buddyDecoration}
      WHERE f.user_id = $1
        AND f.status = 'accepted'
        AND COALESCE(ns.share_live_presence, TRUE) = TRUE
        AND NOT EXISTS (
          SELECT 1 FROM user_blocks b
           WHERE (b.blocker_id = $1 AND b.blocked_id = f.friend_id)
              OR (b.blocker_id = f.friend_id AND b.blocked_id = $1)
        )
      ORDER BY s.started_at DESC
      LIMIT 10`,
    [userId],
  );
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
