import { PostgresService } from "./DbService.js";
import type { BuddyActivityType } from "../types/buddy.js";

const db = PostgresService.getInstance();

/**
 * "Looking for a buddy right now", the Spotify-Jam moment for buddy walks.
 *
 * While someone's buddy setup screen is open the app heartbeats here. Two
 * friends who open it within the window see each other at the top of the
 * screen ("Alex is looking too"), so the walk two people standing together
 * meant to take becomes one tap instead of a search through a friend list.
 *
 * Deliberately NOT proximity: no location is sent or stored, only "now" and
 * walk vs run. It works for friends across town exactly as for friends side by
 * side, and needs no new permission (see getJoinableFriendSessions for why
 * proximity sensing was rejected).
 *
 * Symmetric by construction: the only way to learn who's looking is to be
 * looking yourself, and someone who has turned off live presence
 * (`share_live_presence`) is neither recorded nor shown anybody. Friends only,
 * enrolled, buddy-invites opt-in respected, no block either way: the same
 * gates as the invite picker, because every person this returns is one tap
 * from an invite.
 *
 * PULL ONLY. No push: broadcasting "your friend opened the buddy screen" to
 * every friend is spam, not a feature.
 */

/** A heartbeat older than this no longer means "looking". */
export const BUDDY_LOOKING_WINDOW_SECONDS = 150;

export interface LookingFriend {
  user_id: string;
  username: string | null;
  first_name: string | null;
  last_name: string | null;
  profile_image_url: string | null;
  current_streak: number | null;
  activity_type: string | null;
  looking_at: string;
}

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

/**
 * Record that `userId` is looking now, and return the friends who are too.
 * Returns [] (and records nothing) for someone who doesn't share presence.
 */
export async function markLookingAndList(
  userId: string,
  activityType: BuddyActivityType | null,
): Promise<LookingFriend[]> {
  const shares = await db.query<{ shares: boolean }>(
    `SELECT ${SHARES_PRESENCE_SQL("$1::text")} AS shares`,
    [userId],
  );
  if (shares[0]?.shares === false) {
    await clearLooking(userId);
    return [];
  }

  await db.query(
    `INSERT INTO buddy_looking (user_id, activity_type, looking_at)
     VALUES ($1::text, $2::varchar, NOW())
     ON CONFLICT (user_id)
     DO UPDATE SET activity_type = EXCLUDED.activity_type, looking_at = NOW()`,
    [userId, activityType],
  );

  return db.query<LookingFriend>(
    `SELECT u.user_id, u.username, u.first_name, u.last_name,
            u.profile_image_url, u.current_streak,
            l.activity_type, l.looking_at
       FROM friendships f
       JOIN buddy_looking l
         ON l.user_id = f.friend_id
        AND l.looking_at > NOW() - INTERVAL '${BUDDY_LOOKING_WINDOW_SECONDS} seconds'
       JOIN users u ON u.user_id = f.friend_id
      WHERE f.user_id = $1
        AND f.status = 'accepted'
        AND u.buddy_enrolled_at IS NOT NULL
        AND ${BUDDY_OPTED_IN_SQL("u.user_id")}
        AND ${SHARES_PRESENCE_SQL("u.user_id")}
        AND NOT EXISTS (
          SELECT 1 FROM user_blocks b
           WHERE (b.blocker_id = $1 AND b.blocked_id = u.user_id)
              OR (b.blocker_id = u.user_id AND b.blocked_id = $1)
        )
      ORDER BY l.looking_at DESC
      LIMIT 10`,
    [userId],
  );
}

/** Stop looking: the screen closed, or a walk was made or joined. */
export async function clearLooking(userId: string): Promise<void> {
  await db.query(`DELETE FROM buddy_looking WHERE user_id = $1`, [userId]);
}
