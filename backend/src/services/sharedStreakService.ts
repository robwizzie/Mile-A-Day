import { PostgresService } from "./DbService.js";
import { getUserLocalToday, dateStringMinus } from "./workoutService.js";

const db = PostgresService.getInstance();

/**
 * "Friend streaks" — the number of consecutive local days that BOTH the viewer
 * and a friend completed their daily mile (SUM(distance) >= 0.95, the same
 * qualifying-day rule as personal streaks in getActiveStreak). A shared day is
 * one whose local_date label both users qualified on; the head has the same
 * today/yesterday grace as a personal streak, anchored to the VIEWER's local
 * today. (Cross-timezone friends: each user's local_date is stamped in their
 * own tz, so we compare date labels — a reasonable v1 simplification.)
 *
 * Read-only and computed live — no new tables, no writes, no effect on the
 * personal streak. Bounded to a LOOKBACK_DAYS window (far larger than any
 * current streak — the app launched June 2026) so the query + walk stay cheap.
 */

const LOOKBACK_DAYS = 90;

export async function getSharedStreaks(
  viewerId: string,
  friendIds: string[],
): Promise<Record<string, number>> {
  const result: Record<string, number> = {};
  if (friendIds.length === 0) return result;

  // Only compute for people who are actually accepted friends of the viewer — a
  // shared streak with a non-friend is meaningless, and this avoids probing
  // arbitrary users' activity.
  const friendRows = await db.query<{ friend_id: string }>(
    `SELECT friend_id FROM friendships
     WHERE user_id = $1 AND status = 'accepted' AND friend_id = ANY($2::text[])`,
    [viewerId, friendIds],
  );
  const acceptedFriendIds = friendRows.map((r) => r.friend_id);
  if (acceptedFriendIds.length === 0) return result;

  const today = await getUserLocalToday(viewerId);
  const since = dateStringMinus(today, LOOKBACK_DAYS);
  const userIds = [viewerId, ...acceptedFriendIds];

  // One batched query for the viewer + all friends' qualifying days in the
  // window. Mirrors getActiveStreak's rule (>= 0.95, exclude deleted /
  // auto-excluded). idx_workouts_local_date_user_id covers this.
  const rows = await db.query<{ user_id: string; local_date: string }>(
    `SELECT user_id, to_char(local_date, 'YYYY-MM-DD') AS local_date
     FROM workouts
     WHERE user_id = ANY($1::text[])
       AND local_date >= $2::date
       AND deleted_at IS NULL AND exclusion_reason IS NULL
     GROUP BY user_id, local_date
     HAVING SUM(distance) >= 0.95`,
    [userIds, since],
  );

  const daysByUser = new Map<string, Set<string>>();
  for (const r of rows) {
    let set = daysByUser.get(r.user_id);
    if (!set) {
      set = new Set<string>();
      daysByUser.set(r.user_id, set);
    }
    set.add(r.local_date);
  }

  const viewerDays = daysByUser.get(viewerId) ?? new Set<string>();
  const yesterday = dateStringMinus(today, 1);

  for (const friendId of acceptedFriendIds) {
    const friendDays = daysByUser.get(friendId);
    if (!friendDays || viewerDays.size === 0) {
      result[friendId] = 0;
      continue;
    }
    result[friendId] = walkSharedStreak(
      viewerDays,
      friendDays,
      today,
      yesterday,
    );
  }

  return result;
}

/** Consecutive shared days ending at today or yesterday (grace), else 0. */
function walkSharedStreak(
  viewerDays: Set<string>,
  friendDays: Set<string>,
  today: string,
  yesterday: string,
): number {
  const isShared = (d: string) => viewerDays.has(d) && friendDays.has(d);

  let cursor: string;
  if (isShared(today)) cursor = today;
  else if (isShared(yesterday)) cursor = yesterday;
  else return 0;

  let streak = 0;
  while (isShared(cursor)) {
    streak++;
    cursor = dateStringMinus(cursor, 1);
  }
  return streak;
}
