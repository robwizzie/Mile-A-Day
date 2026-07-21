import { PostgresService } from "./DbService.js";
import { TODAY_ET_DATE_SQL } from "./dailyResetTime.js";

const db = PostgresService.getInstance();

/**
 * Community-wide counters for the marketing site's live stats band.
 *
 * PUBLIC + UNAUTHENTICATED. Only global aggregates may ever go in here —
 * no user ids, usernames, emails, per-user numbers, or anything that could
 * identify or enumerate a person. Values are rounded so the endpoint can't
 * be used to fingerprint individual workouts as they land.
 */
export interface PublicStats {
  total_users: number;
  total_miles: number;
  miles_today: number;
  total_hypes: number;
  total_nudges: number;
  // Additive community aggregates for the marketing band. Global only — a
  // distinct-active count, a total photo-post count, and the single longest
  // active streak (a bare max, identifies no one).
  active_7d: number;
  photos_shared: number;
  longest_streak: number;
}

// The endpoint is public and uncached queries hit five aggregate scans, so a
// short in-memory cache keeps a traffic spike (or someone hammering it) from
// turning into DB load. One minute matches the site's poll interval.
const CACHE_TTL_MS = 60_000;
let cache: { data: PublicStats; at: number } | null = null;

export async function getPublicStats(): Promise<PublicStats> {
  if (cache && Date.now() - cache.at < CACHE_TTL_MS) {
    return cache.data;
  }

  // Mile counts mirror the app/admin: soft-deleted and auto-excluded
  // (e.g. vehicle-speed) workouts don't count. "Today" is the ET calendar
  // day — the app's canonical daily-reset timezone.
  const [row] = await db.query<{
    total_users: number;
    total_miles: number;
    miles_today: number;
    total_hypes: number;
    total_nudges: number;
    active_7d: number;
    photos_shared: number;
    longest_streak: number;
  }>(`
    SELECT
      (SELECT COUNT(*) FROM users)::int AS total_users,
      (SELECT COALESCE(SUM(distance), 0) FROM workouts
         WHERE deleted_at IS NULL AND exclusion_reason IS NULL)::float AS total_miles,
      (SELECT COALESCE(SUM(distance), 0) FROM workouts
         WHERE local_date = ${TODAY_ET_DATE_SQL}
           AND deleted_at IS NULL AND exclusion_reason IS NULL)::float AS miles_today,
      (SELECT COUNT(*) FROM hype_log)::int AS total_hypes,
      ((SELECT COUNT(*) FROM nudge_log)
        + (SELECT COUNT(*) FROM friend_nudge_log))::int AS total_nudges,
      -- Distinct runners who logged a counting mile in the last 7 ET days.
      (SELECT COUNT(DISTINCT user_id) FROM workouts
         WHERE local_date >= ${TODAY_ET_DATE_SQL} - 6
           AND deleted_at IS NULL AND exclusion_reason IS NULL)::int AS active_7d,
      -- Deliberate photo posts (auto route cards excluded).
      (SELECT COUNT(*) FROM posts
         WHERE deleted_at IS NULL AND NOT is_auto)::int AS photos_shared,
      -- The single longest active streak in the community (a bare number).
      (SELECT COALESCE(MAX(current_streak), 0) FROM users)::int AS longest_streak
  `);

  const data: PublicStats = {
    total_users: row?.total_users ?? 0,
    total_miles: Math.round(row?.total_miles ?? 0),
    miles_today: Math.round((row?.miles_today ?? 0) * 10) / 10,
    total_hypes: row?.total_hypes ?? 0,
    total_nudges: row?.total_nudges ?? 0,
    active_7d: row?.active_7d ?? 0,
    photos_shared: row?.photos_shared ?? 0,
    longest_streak: row?.longest_streak ?? 0,
  };
  cache = { data, at: Date.now() };
  return data;
}
