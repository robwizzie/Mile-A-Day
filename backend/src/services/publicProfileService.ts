import { PostgresService } from "./DbService.js";
import { countedWorkoutSql } from "./mileTime.js";
import { effectiveStreakSql } from "./streakFeatureCore.js";
import { DEFAULT_WORKOUT_VISIBILITY } from "./visibilityService.js";

const db = PostgresService.getInstance();

/** How many earned medals the public profile names. */
export const PUBLIC_PROFILE_MEDAL_LIMIT = 5;

export interface PublicProfileMedal {
  badge_id: string;
  name: string;
  icon: string;
  rarity: string;
  category: string;
}

/**
 * `/public/users/:username` — the world-readable profile behind the marketing
 * site's mileaday.run/u/<username> share page and its unfurl card. No viewer,
 * no auth: everything here can be forwarded anywhere.
 *
 * Always published (since launch, for every account): who this is — names,
 * bio, avatar — and the current streak. Those stay public for a 'private'
 * account too: the bio is text the user wrote to be shown, the streak is the
 * app's identity number (it rides every friend row and request), and taking
 * either away would change the meaning of fields shipped clients already read.
 * The banner joins that set: it's profile decoration, like the avatar.
 *
 * Published only when `workout_visibility` isn't 'private': lifetime miles,
 * friend count and a few earned medals. A 'private' account gets them as
 * null, so the page stays the minimal card — null means "not shared", never
 * zero.
 *
 * current_streak reads through effectiveStreakSql, never the raw column: the
 * stored row stays non-zero until the hourly decay sweep reaches it, so the
 * raw value can advertise a dead streak for up to an hour.
 */
export async function getPublicProfile(username: string) {
  const rows = await db.query<{
    user_id: string;
    username: string | null;
    first_name: string | null;
    last_name: string | null;
    bio: string | null;
    profile_image_url: string | null;
    current_streak: number;
    profile_banner_style: string | null;
    profile_banner_url: string | null;
    workout_visibility: string;
  }>(
    `SELECT u.user_id, u.username, u.first_name, u.last_name, u.bio,
            u.profile_image_url, (${effectiveStreakSql("u")})::int AS current_streak,
            u.profile_banner_style, u.profile_banner_url,
            COALESCE(ns.workout_visibility, '${DEFAULT_WORKOUT_VISIBILITY}') AS workout_visibility
     FROM users u
     LEFT JOIN notification_settings ns ON ns.user_id = u.user_id
     WHERE LOWER(u.username) = LOWER($1)`,
    [username],
  );
  const user = rows[0];
  if (!user) return null;

  const { workout_visibility, ...profile } = user;
  const sharesStats = workout_visibility !== "private";

  const [totals, friends, medals] = sharesStats
    ? await Promise.all([
        // The figure the miles_* medals award on (badgeService.computeAggregates).
        db.query<{ total_miles: string }>(
          `SELECT COALESCE(SUM(w.distance), 0)::text AS total_miles
           FROM workouts w WHERE w.user_id = $1 AND ${countedWorkoutSql("w")}`,
          [user.user_id],
        ),
        // The same rows the app's Friends tile lists (friendshipService.getFriends).
        db.query<{ count: number }>(
          `SELECT COUNT(*)::int AS count FROM friendships
           WHERE user_id = $1 AND status = 'accepted'`,
          [user.user_id],
        ),
        // Pinned first (the user's own pick, in slot order), then rarest,
        // then newest. Catalog columns only — what /badges/catalog serves.
        db.query<PublicProfileMedal>(
          `SELECT b.badge_id, b.name, b.icon, b.rarity, b.category
           FROM user_badges ub
           JOIN badges b ON b.badge_id = ub.badge_id
           WHERE ub.user_id = $1
           ORDER BY ub.pin_slot ASC NULLS LAST,
                    CASE b.rarity WHEN 'legendary' THEN 0 WHEN 'rare' THEN 1 ELSE 2 END,
                    ub.earned_at DESC, b.sort_order ASC
           LIMIT ${PUBLIC_PROFILE_MEDAL_LIMIT}`,
          [user.user_id],
        ),
      ])
    : [null, null, null];

  return {
    ...profile,
    total_miles: totals
      ? Math.round(parseFloat(totals[0]?.total_miles ?? "0") * 100) / 100
      : null,
    friend_count: friends ? (friends[0]?.count ?? 0) : null,
    medals: medals ?? null,
  };
}
