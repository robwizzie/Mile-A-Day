import crypto from "node:crypto";
import { PostgresService } from "./DbService.js";
import { getPublicStats } from "./publicStatsService.js";
import { START_OF_TODAY_ET_SQL, TODAY_ET_DATE_SQL } from "./dailyResetTime.js";
import { LIVE_PRESENCE_WINDOW_SECONDS } from "./liveTrackingService.js";
import { DAILY_GOAL_TOLERANCE, getTodayMiles } from "./workoutService.js";
import { effectiveStreakSql, fetchTodayCoverage } from "./streakFeatureCore.js";
import { getAtRisk } from "./adminAnalyticsService.js";

const db = PostgresService.getInstance();

/**
 * Desk display ("Mile A Day counter") feed.
 *
 * SECURITY MODEL — read this before adding a field.
 *  - A display key is a bearer secret for ONE user, minted by an admin and
 *    shown once. Only its SHA-256 is stored. It authenticates exactly one
 *    route (GET /display/feed); it is never a JWT and never reaches the
 *    authenticated API or /admin.
 *  - The feed is an explicit WHITELIST. Community numbers are global COUNTS
 *    and SUMS only — no ids, names, emails or per-user rows. The "me" block
 *    is the key owner's own data, the same things their own app shows them.
 *  - Friend names (who's out running, who nudged/hyped you) go through the
 *    same privacy rules the app applies to the owner: accepted friendship,
 *    the friend's share_live_presence opt-out, and blocks in BOTH directions.
 *    Only a username is ever returned — no user_id, real name or photo.
 *  - Nothing here writes user data. The only write is the key's own
 *    last_used_at stamp, throttled.
 */

export const DISPLAY_KEY_PREFIX = "madk_";
const KEY_BYTES = 32; // 256-bit secret
// Short enough that Admin -> Displays can call a board offline after 10 min.
const LAST_USED_STAMP_MS = 2 * 60 * 1000;
const AT_RISK_TTL_MS = 5 * 60 * 1000;
const FINISHED_WINDOW_MINUTES = 30;
const COMMUNITY_TTL_MS = 30_000;
const ALERT_WINDOW_HOURS = 24;
const MAX_ALERTS = 5;
const MAX_FRIENDS_RUNNING = 3;
const MAX_FRIENDS_FINISHED = 3;

export function hashDisplayKey(key: string): string {
  return crypto.createHash("sha256").update(key, "utf8").digest("hex");
}

/** A well-formed key: prefix + 43 base64url chars. Anything else is rejected
 *  before it touches the database. */
export function isWellFormedKey(key: string): boolean {
  return /^madk_[A-Za-z0-9_-]{43}$/.test(key);
}

// ─── Key management (admin only) ───────────────────────────────────────────

export interface DisplayKeyRow {
  id: string;
  username: string | null;
  label: string;
  key_prefix: string;
  created_at: string;
  last_used_at: string | null;
  revoked_at: string | null;
}

export async function createDisplayKey(
  userId: string,
  label: string,
  createdBy: string | null,
): Promise<{ key: string; row: DisplayKeyRow }> {
  const key = DISPLAY_KEY_PREFIX + crypto.randomBytes(KEY_BYTES).toString("base64url");
  const [row] = await db.query<DisplayKeyRow>(
    `WITH ins AS (
       INSERT INTO display_keys (user_id, key_hash, key_prefix, label, created_by)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING id, user_id, label, key_prefix, created_at, last_used_at, revoked_at
     )
     SELECT ins.id, u.username, ins.label, ins.key_prefix,
            ins.created_at::text, ins.last_used_at::text, ins.revoked_at::text
       FROM ins JOIN users u ON u.user_id = ins.user_id`,
    [userId, hashDisplayKey(key), key.slice(0, 9), label.slice(0, 60), createdBy],
  );
  return { key, row };
}

export async function listDisplayKeys(): Promise<DisplayKeyRow[]> {
  // Never selects key_hash.
  return db.query<DisplayKeyRow>(
    `SELECT k.id, u.username, k.label, k.key_prefix, k.created_at::text,
            k.last_used_at::text, k.revoked_at::text
       FROM display_keys k JOIN users u ON u.user_id = k.user_id
      ORDER BY k.revoked_at IS NOT NULL, k.created_at DESC
      LIMIT 200`,
  );
}

export async function revokeDisplayKey(id: string): Promise<boolean> {
  const rows = await db.query(
    `UPDATE display_keys SET revoked_at = NOW()
      WHERE id = $1 AND revoked_at IS NULL
      RETURNING id`,
    [id],
  );
  return rows.length > 0;
}

/** userId for a live (unrevoked) key whose owner still exists, else null. */
export async function resolveDisplayKey(key: string): Promise<string | null> {
  if (!isWellFormedKey(key)) return null;
  const rows = await db.query<{ id: string; user_id: string; stale: boolean }>(
    `SELECT k.id, k.user_id,
            (k.last_used_at IS NULL OR k.last_used_at < NOW() - ($2 || ' milliseconds')::interval) AS stale
       FROM display_keys k JOIN users u ON u.user_id = k.user_id
      WHERE k.key_hash = $1 AND k.revoked_at IS NULL`,
    [hashDisplayKey(key), String(LAST_USED_STAMP_MS)],
  );
  if (!rows.length) return null;
  if (rows[0].stale) {
    // Best effort; a failed stamp never fails the request.
    db.query(`UPDATE display_keys SET last_used_at = NOW() WHERE id = $1`, [rows[0].id])
      .catch(() => undefined);
  }
  return rows[0].user_id;
}

// ─── Community block (aggregates only, cached) ─────────────────────────────

export interface DisplayCommunity {
  total_users: number;
  total_miles: number;
  miles_today: number;
  active_7d: number;
  longest_streak: number;
  total_hypes: number;
  photos_shared: number;
  out_running_now: number;
  tokens_spent_today: number;
  badges_today: number;
  new_friends_today: number;
  hypes_today: number;
  nudges_today: number;
  miles_yesterday_same_time: number;
  streaks_at_risk: number;
}

let communityCache: { data: DisplayCommunity; at: number } | null = null;
let atRiskCache: { n: number; at: number } | null = null;

/** How many streaks are at risk today: the same rule as the admin panel
 *  (runner's own local day, not on an injury pause), as a COUNT only. */
async function streaksAtRisk(): Promise<number> {
  if (atRiskCache && Date.now() - atRiskCache.at < AT_RISK_TTL_MS) return atRiskCache.n;
  const n = (await getAtRisk()).length;
  atRiskCache = { n, at: Date.now() };
  return n;
}

async function getCommunity(): Promise<DisplayCommunity> {
  if (communityCache && Date.now() - communityCache.at < COMMUNITY_TTL_MS) {
    return communityCache.data;
  }
  const pub = await getPublicStats();
  const atRisk = await streaksAtRisk();
  const [row] = await db.query<Record<string, number>>(`
    SELECT
      -- Out on a tracked mile right now, counted the way the app decides
      -- presence (fresh heartbeat, not ended) and only among people who
      -- share their live presence.
      (SELECT COUNT(*) FROM live_tracking_sessions s
         LEFT JOIN notification_settings ns ON ns.user_id = s.user_id
        WHERE s.ended_at IS NULL
          AND s.last_seen_at > NOW() - INTERVAL '${LIVE_PRESENCE_WINDOW_SECONDS} seconds'
          AND COALESCE(ns.share_live_presence, TRUE) = TRUE)::int AS out_running_now,
      (SELECT COUNT(*) FROM streak_coverage
        WHERE created_at >= ${START_OF_TODAY_ET_SQL})::int AS tokens_spent_today,
      (SELECT COUNT(*) FROM user_badges
        WHERE earned_at >= ${START_OF_TODAY_ET_SQL})::int AS badges_today,
      -- A friendship is two rows; accepting keeps the request's old
      -- created_at and inserts the reverse row now, so count PAIRS that
      -- gained any row today.
      (SELECT COUNT(DISTINCT LEAST(user_id, friend_id) || ':' || GREATEST(user_id, friend_id))
         FROM friendships
        WHERE status = 'accepted' AND created_at >= ${START_OF_TODAY_ET_SQL})::int AS new_friends_today,
      (SELECT COUNT(*) FROM hype_log
        WHERE created_at >= ${START_OF_TODAY_ET_SQL})::int AS hypes_today,
      ((SELECT COUNT(*) FROM nudge_log WHERE created_at >= ${START_OF_TODAY_ET_SQL}) +
       (SELECT COUNT(*) FROM friend_nudge_log WHERE created_at >= ${START_OF_TODAY_ET_SQL}))::int AS nudges_today,
      -- Yesterday's miles logged by this time of day (for the race screen).
      (SELECT COALESCE(SUM(distance), 0) FROM workouts
        WHERE local_date = ${TODAY_ET_DATE_SQL} - 1
          AND device_end_date <= NOW() - INTERVAL '1 day'
          AND deleted_at IS NULL AND exclusion_reason IS NULL)::float AS miles_yesterday_same_time
  `);
  const data: DisplayCommunity = {
    total_users: pub.total_users,
    total_miles: pub.total_miles,
    miles_today: pub.miles_today,
    active_7d: pub.active_7d,
    longest_streak: pub.longest_streak,
    total_hypes: pub.total_hypes,
    photos_shared: pub.photos_shared,
    out_running_now: row?.out_running_now ?? 0,
    tokens_spent_today: row?.tokens_spent_today ?? 0,
    badges_today: row?.badges_today ?? 0,
    new_friends_today: row?.new_friends_today ?? 0,
    hypes_today: row?.hypes_today ?? 0,
    nudges_today: row?.nudges_today ?? 0,
    miles_yesterday_same_time: Math.round((row?.miles_yesterday_same_time ?? 0) * 10) / 10,
    streaks_at_risk: atRisk,
  };
  communityCache = { data, at: Date.now() };
  return data;
}

// ─── Owner block ───────────────────────────────────────────────────────────

export interface DisplayFeed {
  v: 1;
  community: DisplayCommunity;
  me: {
    username: string | null;
    mile_done: boolean;
    miles_today: number;
    streak: number;
    running_now: boolean;
    local_time: string;          // "HH:MM:SS" in the owner's timezone
    minutes_to_midnight: number; // until the owner's local day ends
    year_ago_miles: number | null; // their own miles on this date last year
  };
  friends_running: { name: string; miles: number }[];
  /** Friends whose tracked session ended in the last 30 min (same rules). */
  friends_finished: { id: string; name: string; miles: number }[];
  alerts: { id: string; kind: "nudge" | "hype"; from: string; at: string }[];
}

export async function getDisplayFeed(userId: string): Promise<DisplayFeed> {
  const [community, meRows, todayMiles, coverage, friends, alerts, finished] = await Promise.all([
    getCommunity(),
    db.query<{
      username: string | null;
      streak: number;
      running_now: boolean;
      local_time: string;
      minutes_to_midnight: number;
      year_ago_miles: number | null;
    }>(
      `WITH tz AS (
         SELECT COALESCE((SELECT timezone_offset FROM workouts
                           WHERE user_id = $1 ORDER BY device_end_date DESC LIMIT 1), 0) AS off
       ), loc AS (
         SELECT (NOW() AT TIME ZONE 'UTC') + (tz.off || ' minutes')::interval AS t FROM tz
       )
       SELECT u.username,
              (${effectiveStreakSql("u")})::int AS streak,
              EXISTS (SELECT 1 FROM live_tracking_sessions s
                       WHERE s.user_id = u.user_id AND s.ended_at IS NULL
                         AND s.last_seen_at > NOW() - INTERVAL '${LIVE_PRESENCE_WINDOW_SECONDS} seconds') AS running_now,
              to_char(loc.t, 'HH24:MI:SS') AS local_time,
              (EXTRACT(EPOCH FROM (date_trunc('day', loc.t) + INTERVAL '1 day' - loc.t)) / 60)::int AS minutes_to_midnight,
              (SELECT SUM(w.distance)::float FROM workouts w
                WHERE w.user_id = u.user_id
                  AND w.local_date = (loc.t - INTERVAL '1 year')::date
                  AND w.deleted_at IS NULL AND w.exclusion_reason IS NULL) AS year_ago_miles
         FROM users u, loc
        WHERE u.user_id = $1`,
      [userId],
    ),
    getTodayMiles(userId),
    fetchTodayCoverage([userId]),
    db.query<{ name: string; miles: number }>(
      `SELECT u.username AS name, ROUND(s.distance_miles::numeric, 1)::float AS miles
         FROM friendships f
         JOIN live_tracking_sessions s
           ON s.user_id = f.friend_id
          AND s.ended_at IS NULL
          AND s.last_seen_at > NOW() - INTERVAL '${LIVE_PRESENCE_WINDOW_SECONDS} seconds'
         JOIN users u ON u.user_id = f.friend_id
         LEFT JOIN notification_settings ns ON ns.user_id = f.friend_id
        WHERE f.user_id = $1
          AND f.status = 'accepted'
          AND u.username IS NOT NULL
          AND COALESCE(ns.share_live_presence, TRUE) = TRUE
          AND NOT EXISTS (
            SELECT 1 FROM user_blocks b
             WHERE (b.blocker_id = $1 AND b.blocked_id = f.friend_id)
                OR (b.blocker_id = f.friend_id AND b.blocked_id = $1))
        ORDER BY s.started_at DESC
        LIMIT ${MAX_FRIENDS_RUNNING}`,
      [userId],
    ),
    // The owner's own inbox: nudges and hypes sent TO them. Read-only (the
    // display never marks anything read). Sender shown by username only.
    db.query<{ id: string; kind: "nudge" | "hype"; from: string; at: string }>(
      `SELECT encode(sha256(n.id::text::bytea), 'hex') AS id,
              CASE n.type WHEN 'friend_nudge' THEN 'nudge' ELSE 'hype' END AS kind,
              COALESCE(su.username, 'A FRIEND') AS "from",
              to_char(n.created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS at
         FROM in_app_notifications n
         LEFT JOIN users su ON su.user_id = (n.data->>'user_id')
        WHERE n.user_id = $1
          AND n.type IN ('friend_nudge', 'hype_received')
          AND n.created_at > NOW() - INTERVAL '${ALERT_WINDOW_HOURS} hours'
          AND (n.data->>'user_id') IS DISTINCT FROM $1
          AND NOT EXISTS (
            SELECT 1 FROM user_blocks b
             WHERE (b.blocker_id = $1 AND b.blocked_id = (n.data->>'user_id'))
                OR (b.blocker_id = (n.data->>'user_id') AND b.blocked_id = $1))
        ORDER BY n.created_at DESC
        LIMIT ${MAX_ALERTS}`,
      [userId],
    ),
    // Friends who just FINISHED a tracked session: identical friendship,
    // presence opt-out and block rules to friends_running above.
    db.query<{ id: string; name: string; miles: number }>(
      `SELECT encode(sha256((s.session_id::text || s.ended_at::text)::bytea), 'hex') AS id,
              u.username AS name, ROUND(s.distance_miles::numeric, 1)::float AS miles
         FROM friendships f
         JOIN live_tracking_sessions s
           ON s.user_id = f.friend_id
          AND s.ended_at IS NOT NULL
          AND s.ended_at > NOW() - INTERVAL '${FINISHED_WINDOW_MINUTES} minutes'
         JOIN users u ON u.user_id = f.friend_id
         LEFT JOIN notification_settings ns ON ns.user_id = f.friend_id
        WHERE f.user_id = $1
          AND f.status = 'accepted'
          AND u.username IS NOT NULL
          AND COALESCE(ns.share_live_presence, TRUE) = TRUE
          AND NOT EXISTS (
            SELECT 1 FROM user_blocks b
             WHERE (b.blocker_id = $1 AND b.blocked_id = f.friend_id)
                OR (b.blocker_id = f.friend_id AND b.blocked_id = $1))
        ORDER BY s.ended_at DESC
        LIMIT ${MAX_FRIENDS_FINISHED}`,
      [userId],
    ),
  ]);

  const me = meRows[0];
  const miles = Number(todayMiles) || 0;
  const covered = Boolean(coverage[userId]);
  return {
    v: 1,
    community,
    me: {
      username: me?.username ?? null,
      mile_done: miles >= DAILY_GOAL_TOLERANCE || covered,
      miles_today: Math.round(miles * 100) / 100,
      streak: me?.streak ?? 0,
      running_now: Boolean(me?.running_now),
      local_time: me?.local_time ?? "00:00:00",
      minutes_to_midnight: me?.minutes_to_midnight ?? 0,
      year_ago_miles: me?.year_ago_miles == null ? null : Math.round(Number(me.year_ago_miles) * 100) / 100,
    },
    friends_running: friends.map((f) => ({ name: f.name, miles: Number(f.miles) || 0 })),
    friends_finished: finished.map((f) => ({ id: f.id.slice(0, 16), name: f.name, miles: Number(f.miles) || 0 })),
    alerts: alerts.map((a) => ({ id: a.id.slice(0, 16), kind: a.kind, from: a.from, at: a.at })),
  };
}
