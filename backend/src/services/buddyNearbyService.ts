import { randomBytes } from "node:crypto";
import { PostgresService } from "./DbService.js";
import { BadRequestError } from "../errors/Errors.js";

const db = PostgresService.getInstance();

/**
 * Nearby friends, over Bluetooth, only while buddy setup is open.
 *
 * The phone broadcasts a short random token (BLE local name) and listens for
 * other phones' tokens; this service is the only thing that can turn a token
 * back into a person, and it only ever does that for the asker's FRIENDS. So
 * the broadcast itself identifies nobody: a stranger's phone hears eight
 * random characters that rotate every few minutes and resolve to nothing.
 *
 * Gates mirror "Looking right now" (`buddyLookingService`): accepted friends,
 * no block either way, buddy-enrolled, buddy invites on, and
 * `share_live_presence` SYMMETRIC — someone who doesn't share presence is
 * neither issued a token nor shown anyone.
 */

/** A token lives this long; the app asks for a fresh one before then. */
export const NEARBY_TOKEN_TTL_SECONDS = 10 * 60;
/** Reuse a token with at least this long left instead of minting another. */
const REUSE_IF_LEFT_SECONDS = 4 * 60;
/** Most tokens one resolve call may ask about. */
export const NEARBY_RESOLVE_LIMIT = 40;

const SHARES_PRESENCE_SQL = (userColumn: string) => `COALESCE(
    (SELECT ns.share_live_presence FROM notification_settings ns
      WHERE ns.user_id = ${userColumn}),
    TRUE
  )`;

const BUDDY_OPTED_IN_SQL = (userColumn: string) => `COALESCE(
    (SELECT ns.buddy_invites_enabled FROM notification_settings ns
      WHERE ns.user_id = ${userColumn}),
    TRUE
  )`;

/** Eight lowercase hex characters: short enough for a BLE local name. */
function mintToken(): string {
  return randomBytes(4).toString("hex");
}

/**
 * The token this user should broadcast now, or null when they don't share
 * presence (the app then neither broadcasts nor scans).
 */
export async function issueNearbyToken(
  userId: string,
): Promise<{ token: string; expires_in: number } | null> {
  const shares = await db.query<{ shares: boolean }>(
    `SELECT ${SHARES_PRESENCE_SQL("$1::text")} AS shares`,
    [userId],
  );
  if (shares[0]?.shares === false) {
    await db.query(`DELETE FROM buddy_nearby_tokens WHERE user_id = $1`, [
      userId,
    ]);
    return null;
  }
  // Housekeeping: this user's expired tokens, and a bounded sweep of anyone's.
  await db.query(
    `DELETE FROM buddy_nearby_tokens WHERE expires_at < NOW() - INTERVAL '1 hour'`,
  );
  const live = await db.query<{ token: string; left: number }>(
    `SELECT token, EXTRACT(EPOCH FROM (expires_at - NOW()))::int AS left
       FROM buddy_nearby_tokens
      WHERE user_id = $1 AND expires_at > NOW() + ($2 || ' seconds')::interval
      ORDER BY expires_at DESC LIMIT 1`,
    [userId, String(REUSE_IF_LEFT_SECONDS)],
  );
  if (live.length > 0) {
    return { token: live[0].token, expires_in: Number(live[0].left) };
  }
  for (let attempt = 0; attempt < 5; attempt++) {
    const token = mintToken();
    const inserted = await db.query<{ token: string }>(
      `INSERT INTO buddy_nearby_tokens (token, user_id, expires_at)
       VALUES ($1, $2, NOW() + ($3 || ' seconds')::interval)
       ON CONFLICT (token) DO NOTHING
       RETURNING token`,
      [token, userId, String(NEARBY_TOKEN_TTL_SECONDS)],
    );
    if (inserted.length > 0) {
      return { token, expires_in: NEARBY_TOKEN_TTL_SECONDS };
    }
  }
  throw new Error("could not mint a nearby token");
}

export interface NearbyFriend {
  user_id: string;
  username: string | null;
  first_name: string | null;
  last_name: string | null;
  profile_image_url: string | null;
  current_streak: number | null;
}

/** Stop broadcasting: setup closed. */
export async function clearNearbyTokens(userId: string): Promise<void> {
  await db.query(`DELETE FROM buddy_nearby_tokens WHERE user_id = $1`, [
    userId,
  ]);
}

/**
 * Which of the tokens this phone heard belong to the caller's friends.
 * Anything else (a stranger, an expired token, a blocked friend, someone not
 * sharing presence) is silently absent.
 */
export async function resolveNearbyTokens(
  userId: string,
  tokens: unknown,
): Promise<NearbyFriend[]> {
  if (!Array.isArray(tokens)) throw new BadRequestError("tokens_required");
  const clean = [
    ...new Set(
      tokens
        .filter((t): t is string => typeof t === "string")
        .map((t) => t.trim().toLowerCase())
        .filter((t) => /^[0-9a-f]{8}$/.test(t)),
    ),
  ].slice(0, NEARBY_RESOLVE_LIMIT);
  if (clean.length === 0) return [];

  return db.query<NearbyFriend>(
    `SELECT DISTINCT ON (u.user_id)
            u.user_id, u.username, u.first_name, u.last_name,
            u.profile_image_url, u.current_streak
       FROM buddy_nearby_tokens t
       JOIN users u ON u.user_id = t.user_id
       JOIN friendships f
         ON f.user_id = $1 AND f.friend_id = u.user_id AND f.status = 'accepted'
      WHERE t.token = ANY($2::text[])
        AND t.expires_at > NOW()
        AND u.user_id <> $1
        AND u.buddy_enrolled_at IS NOT NULL
        AND ${BUDDY_OPTED_IN_SQL("u.user_id")}
        AND ${SHARES_PRESENCE_SQL("u.user_id")}
        AND ${SHARES_PRESENCE_SQL("$1::text")}
        AND NOT EXISTS (
          SELECT 1 FROM user_blocks b
           WHERE (b.blocker_id = $1 AND b.blocked_id = u.user_id)
              OR (b.blocker_id = u.user_id AND b.blocked_id = $1)
        )
      ORDER BY u.user_id`,
    [userId, clean],
  );
}
