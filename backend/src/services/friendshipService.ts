import { Friendship, User } from "../types/user.js";
import { PostgresService } from "./DbService.js";
import { runHypeMatchSql, runHypedByViewerMatchSql } from "./hypeService.js";
import { refreshCurrentStreak } from "./leaderboardService.js";

const db = PostgresService.getInstance();

type ErrorReturn = {
  error: string;
};

type MessageReturn = {
  message: string;
};

export async function areFriends(
  user1: string,
  user2: string,
): Promise<boolean> {
  if (user1 === user2) return true;
  const rows = await db.query<{ status: string }>(
    `SELECT status FROM friendships
		WHERE ((user_id = $1 AND friend_id = $2) OR (user_id = $2 AND friend_id = $1))
		  AND status = 'accepted'
		LIMIT 1`,
    [user1, user2],
  );
  return rows.length > 0;
}

export async function getFriendship(
  user1: string,
  user2: string,
): Promise<Friendship | ErrorReturn | null> {
  try {
    const existingFriendship = await db.query(
      "SELECT * FROM friendships WHERE (user_id = $1 AND friend_id = $2) OR (user_id = $2 AND friend_id = $1)",
      [user1, user2],
    );

    return (
      existingFriendship.find((friendship) => friendship.user_id === user1) ??
      existingFriendship[0]
    );
  } catch (err: any) {
    return { error: err.message };
  }
}

export async function getFriends(user: string): Promise<User[]> {
  // Safe column set only — never expose a real email through friend lists
  // (these are viewable by other users, not just the owner).
  // BACKWARDS COMPAT: the shipped App Store app decodes friends into a
  // BackendUser whose `email` is a NON-optional String, so a missing key
  // hard-fails Codable and breaks the friends list. Return an empty-string
  // email — present for the old client, leaks nothing. Drop it once the
  // email-optional app build has fully rolled out.
  const friends = await db.query(
    `
		SELECT u.user_id, u.username, u.first_name, u.last_name, u.bio,
			u.profile_image_url, u.current_streak, '' AS email
		FROM friendships f
		JOIN users u ON u.user_id = f.friend_id
		WHERE f.user_id = $1
			AND f.status = 'accepted'
		`,
    [user],
  );

  return refreshFriendStreaks(friends);
}

async function refreshFriendStreaks<T extends { user_id: string; current_streak?: number | null }>(
  friends: T[],
): Promise<T[]> {
  if (friends.length === 0) return friends;
  const refreshed = await Promise.all(
    friends.map(async (friend) => ({
      ...friend,
      current_streak: await refreshCurrentStreak(friend.user_id),
    })),
  );
  return refreshed;
}

export async function getSentRequests(user: string): Promise<User[]> {
  const sentRequests = await db.query(
    `
		SELECT u.* FROM friendships f
		JOIN users u ON u.user_id = f.friend_id
		WHERE f.user_id = $1
			AND f.status in ( 'pending', 'ignored' ) 
		`,
    [user],
  );

  return sentRequests;
}

type FriendRequestsReturn = {
  requests: User[];
  ignored_requests: User[];
};

export async function getFriendRequests(
  user: string,
): Promise<FriendRequestsReturn> {
  const friendRequests = await db.query(
    `
		SELECT u.*, f.status FROM friendships f
		JOIN users u ON u.user_id = f.user_id
		WHERE f.friend_id = $1
			AND f.status in ( 'pending', 'ignored' ) 
		`,
    [user],
  );

  const requests: User[] = [];
  const ignored_requests: User[] = [];

  friendRequests.forEach((request) => {
    const { status, ...user }: { status: "pending" | "ignored" } & User =
      request;
    if (status === "pending") {
      requests.push(user);
    } else if (status === "ignored") {
      ignored_requests.push(user);
    }
  });

  return { requests, ignored_requests };
}

export async function sendFriendRequest(
  user1: string,
  user2: string,
): Promise<MessageReturn | ErrorReturn> {
  try {
    await db.query(
      `
			INSERT INTO friendships (user_id, friend_id, status)
			VALUES ($1, $2, 'pending')
			ON CONFLICT (user_id, friend_id) DO NOTHING
			`,
      [user1, user2],
    );

    return { message: "Successfully sent friend request" };
  } catch (err: any) {
    return { error: err.message };
  }
}

export interface FriendActivity {
  user_id: string;
  username: string | null;
  first_name: string | null;
  last_name: string | null;
  profile_image_url: string | null;
  today_miles: number;
  completed_today: boolean;
}

export async function getFriendsActivityToday(
  userId: string,
): Promise<FriendActivity[]> {
  const results = await db.query(
    `
		SELECT
			u.user_id,
			u.username,
			u.first_name,
			u.last_name,
			u.profile_image_url,
			COALESCE((
				SELECT SUM(w.distance)
				FROM workouts w
				WHERE w.user_id = u.user_id
				AND w.local_date = (
					NOW() + (
						COALESCE(
							(SELECT timezone_offset FROM workouts WHERE user_id = u.user_id ORDER BY device_end_date DESC LIMIT 1),
							0
						) || ' minutes'
					)::interval
				)::date
				AND w.deleted_at IS NULL AND w.exclusion_reason IS NULL
			), 0)::float as today_miles
		FROM friendships f
		JOIN users u ON u.user_id = f.friend_id
		WHERE f.user_id = $1
			AND f.status = 'accepted'
		ORDER BY today_miles DESC
		`,
    [userId],
  );

  return results.map((r: any) => ({
    ...r,
    today_miles: parseFloat(r.today_miles) || 0,
    completed_today: parseFloat(r.today_miles) >= 1.0,
  }));
}

export interface FriendSuggestion {
  user_id: string;
  username: string | null;
  first_name: string | null;
  last_name: string | null;
  bio: string | null;
  profile_image_url: string | null;
  current_streak: number;
  mutual_friends: number;
  shared_competitions: number;
}

/**
 * "People you may know": friends-of-friends ranked by mutual-friend count,
 * plus people the user has shared a competition with but never friended.
 *
 * Exclusions: the user themself and anyone with ANY friendship row touching
 * the user (accepted rows exist in both directions; pending/ignored exist
 * one-way from the sender; rejected/removed rows are deleted — so a single
 * either-direction check covers every live relationship state).
 */
export async function getFriendSuggestions(
  userId: string,
  limit: number = 20,
): Promise<FriendSuggestion[]> {
  const suggestions = await db.query<FriendSuggestion>(
    `
		WITH my_friends AS (
			-- Accepted friendships are stored bidirectionally, so one
			-- direction is enough to enumerate the friend set.
			SELECT friend_id AS fid
			FROM friendships
			WHERE user_id = $1 AND status = 'accepted'
		),
		excluded AS (
			SELECT CASE WHEN user_id = $1 THEN friend_id ELSE user_id END AS uid
			FROM friendships
			WHERE user_id = $1 OR friend_id = $1
		),
		fof AS (
			SELECT f.friend_id AS suggested_id, COUNT(*)::int AS mutual_friends
			FROM friendships f
			JOIN my_friends mf ON mf.fid = f.user_id
			WHERE f.status = 'accepted'
			GROUP BY f.friend_id
		),
		shared_comps AS (
			SELECT cu2.user_id AS suggested_id,
				COUNT(DISTINCT cu2.competition_id)::int AS shared_competitions
			FROM competition_users cu1
			JOIN competition_users cu2
				ON cu2.competition_id = cu1.competition_id
				AND cu2.user_id <> cu1.user_id
			WHERE cu1.user_id = $1
				AND cu1.invite_status = 'accepted'
				AND cu2.invite_status = 'accepted'
			GROUP BY cu2.user_id
		),
		candidates AS (
			SELECT suggested_id FROM fof
			UNION
			SELECT suggested_id FROM shared_comps
		)
		SELECT u.user_id, u.username, u.first_name, u.last_name, u.bio,
			u.profile_image_url, u.current_streak,
			COALESCE(fof.mutual_friends, 0) AS mutual_friends,
			COALESCE(sc.shared_competitions, 0) AS shared_competitions
		FROM candidates c
		JOIN users u ON u.user_id = c.suggested_id
		LEFT JOIN fof ON fof.suggested_id = c.suggested_id
		LEFT JOIN shared_comps sc ON sc.suggested_id = c.suggested_id
		WHERE c.suggested_id <> $1
			AND c.suggested_id NOT IN (SELECT uid FROM excluded)
			-- Guests have no username; an unaddressable suggestion card is
			-- useless, so skip them.
			AND u.username IS NOT NULL
		ORDER BY COALESCE(fof.mutual_friends, 0) DESC,
			COALESCE(sc.shared_competitions, 0) DESC,
			u.username ASC
		LIMIT $2
		`,
    [userId, limit],
  );

  // Cold-start fallback: a sparse social graph (no friends-of-friends, no
  // shared competitions) yields an empty list, leaving "People You May Know"
  // blank. Top up with the most active runners the user isn't already
  // connected to so there's always something to discover.
  if (suggestions.length >= limit) {
    return suggestions;
  }

  const fallback = await db.query<FriendSuggestion>(
    `
		SELECT u.user_id, u.username, u.first_name, u.last_name, u.bio,
			u.profile_image_url, u.current_streak,
			0 AS mutual_friends, 0 AS shared_competitions
		FROM users u
		WHERE u.user_id <> $1
			AND u.username IS NOT NULL
			AND NOT EXISTS (
				SELECT 1 FROM friendships f
				WHERE (f.user_id = $1 AND f.friend_id = u.user_id)
					OR (f.friend_id = $1 AND f.user_id = u.user_id)
			)
		ORDER BY u.current_streak DESC NULLS LAST, u.username ASC
		LIMIT $2
		`,
    // Over-fetch so we can drop anyone already in the graph-based list.
    [userId, limit + 25],
  );

  const alreadySuggested = new Set(suggestions.map((s) => s.user_id));
  const extras = fallback
    .filter((u) => !alreadySuggested.has(u.user_id))
    .slice(0, limit - suggestions.length);

  return [...suggestions, ...extras];
}

export interface FeedWorkout {
  workout_id: string;
  user_id: string;
  username: string | null;
  first_name: string | null;
  last_name: string | null;
  profile_image_url: string | null;
  workout_type: string;
  distance: number;
  completed_at: string;
  is_self: boolean;
  is_hyped: boolean;
  // Detail fields — let the client surface duration/pace/calories/steps
  // inline without an extra round trip. Additive; older clients ignore them.
  total_duration: number;
  calories: number;
  steps: number | null;
  // Social-proof tally: total hypes this specific workout has received from
  // anyone (not just the viewer). Powers the "👏 N" badge on each feed row.
  hype_count: number;
}

/**
 * Rolling-48h activity feed: individual workouts from the viewer's accepted
 * friends plus the viewer, newest first. Each row is tagged with whether the
 * viewer has already hyped that specific workout (context_type 'mile', keyed
 * on workout_id) so the UI can show a one-shot hype button, plus the total
 * hype tally for that workout.
 */
export async function getFriendsWorkoutFeed(
  userId: string,
): Promise<FeedWorkout[]> {
  const rows = await db.query<FeedWorkout>(
    `
		WITH circle AS (
			SELECT friend_id AS uid FROM friendships
			WHERE user_id = $1 AND status = 'accepted'
			UNION
			SELECT $1 AS uid
		)
		SELECT
			w.workout_id,
			w.user_id,
			u.username,
			u.first_name,
			u.last_name,
			u.profile_image_url,
			w.workout_type,
			w.distance::float AS distance,
			w.device_end_date AS completed_at,
			w.total_duration::float AS total_duration,
			w.calories::float AS calories,
			w.steps,
			(w.user_id = $1) AS is_self,
			-- Unified RUN rule for button state (matches the feed/inbox): this
			-- run's mile hypes (day composite OR exact workout id) and its posts'
			-- hypes are one pool, so a mile hyped from any surface shows hyped
			-- here too and can't be hyped again. A different same-day workout
			-- keyed by its own id stays independently hypeable.
			EXISTS (
				SELECT 1 FROM hype_log h
				WHERE h.sender_id = $1
					AND h.target_id = w.user_id
					AND ${runHypedByViewerMatchSql("h", "w")}
			) AS is_hyped,
			(
				SELECT COUNT(DISTINCT hc.sender_id)::int FROM hype_log hc
				WHERE hc.target_id = w.user_id
					AND ${runHypeMatchSql("hc", "w")}
			) AS hype_count
		FROM workouts w
		JOIN circle c ON c.uid = w.user_id
		JOIN users u ON u.user_id = w.user_id
		LEFT JOIN notification_settings ns ON ns.user_id = w.user_id
		WHERE w.device_end_date >= NOW() - INTERVAL '48 hours'
		AND w.deleted_at IS NULL AND w.exclusion_reason IS NULL
		-- Respect the owner's share_workouts_to_feed opt-out on this legacy
		-- feed too, not just the unified feed (the viewer still sees their own).
		AND (COALESCE(ns.share_workouts_to_feed, true) = true OR w.user_id = $1)
		ORDER BY w.device_end_date DESC
		LIMIT 100
		`,
    [userId],
  );
  return rows;
}

/**
 * Number of accepted friends shared between the viewer and another user —
 * the "X mutual friends" line shown on a profile.
 */
export async function getMutualFriendCount(
  viewerId: string,
  otherId: string,
): Promise<number> {
  if (viewerId === otherId) return 0;
  const rows = await db.query<{ count: number }>(
    `
		SELECT COUNT(*)::int AS count
		FROM friendships a
		JOIN friendships b ON a.friend_id = b.friend_id
		WHERE a.user_id = $1 AND a.status = 'accepted'
			AND b.user_id = $2 AND b.status = 'accepted'
		`,
    [viewerId, otherId],
  );
  return rows[0]?.count ?? 0;
}

export async function updateFriendship(
  user1: string,
  user2: string,
  status: "accepted" | "rejected" | "ignored" | "removed",
): Promise<MessageReturn | ErrorReturn> {
  try {
    const existingFriendship = await getFriendship(user1, user2);

    if (!existingFriendship) {
      throw new Error(`No friendship found between ${user1} and ${user2}`);
    }

    if ("error" in existingFriendship) {
      throw new Error(existingFriendship.error);
    }

    if (existingFriendship.status === status) {
      throw new Error(`Friendship already has status ${status}`);
    } else if (
      (status === "removed" && existingFriendship.status === "accepted") ||
      (status === "rejected" &&
        (existingFriendship.status === "pending" ||
          existingFriendship.status === "ignored"))
    ) {
      await db.query(
        `
				DELETE FROM friendships
				WHERE (user_id = $1 AND friend_id = $2)
					OR (user_id = $2 AND friend_id = $1)
				`,
        [user1, user2],
      );

      await db.query(
        `
				DELETE FROM close_friends
				WHERE (user_id = $1 AND close_friend_id = $2)
					OR (user_id = $2 AND close_friend_id = $1)
				`,
        [user1, user2],
      );

      return {
        message:
          status === "rejected"
            ? "Successfully rejected friend request"
            : "Successfully deleted friendship",
      };
    } else if (existingFriendship.user_id === user1) {
      throw new Error(`User can't update a request they sent`);
    } else if (
      status === "accepted" &&
      (existingFriendship.status === "pending" ||
        existingFriendship.status === "ignored")
    ) {
      await db.transaction([
        {
          query: `
					UPDATE friendships
					SET status = 'accepted'
					WHERE user_id = $1 AND friend_id = $2
					`,
          params: [user2, user1],
        },
        {
          query: `
					INSERT INTO friendships (user_id, friend_id, status)
  					VALUES ($1, $2, 'accepted')
  					ON CONFLICT (user_id, friend_id) DO NOTHING
					`,
          params: [user1, user2],
        },
      ]);

      return { message: "Friend request successfully accepted" };
    } else if (status === "ignored") {
      await db.query(
        `
				UPDATE friendships
				SET status = 'ignored'
				WHERE user_id = $1 AND friend_id = $2
				`,
        [user2, user1],
      );

      return { message: "Friend request successfully ignored" };
    } else {
      throw new Error("Invalid status.");
    }
  } catch (err: any) {
    return { error: err.message };
  }
}
