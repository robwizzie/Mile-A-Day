import fs from "fs";
import { promises as fsp } from "fs";
import path from "path";
import { PostgresService } from "./DbService.js";
import { START_OF_TODAY_ET_SQL, TODAY_ET_DATE_SQL } from "./dailyResetTime.js";

const db = PostgresService.getInstance();

// Uploaded media lives on the app server's local disk under <cwd>/uploads,
// with post photos in uploads/posts (see server.ts static mounts). Storage
// stats and integrity checks walk these directories directly.
const UPLOADS_ROOT = path.join(process.cwd(), "uploads");
const POSTS_MEDIA_DIR = path.join(UPLOADS_ROOT, "posts");

/** Resolve a user by their Apple `sub` (stable per Apple ID within our team,
 *  identical across the native app and the web Services ID). */
export async function getUserByAppleSub(sub: string): Promise<{
  user_id: string;
  role: string | null;
  email: string | null;
} | null> {
  const rows = await db.query(
    `SELECT user_id, role, email FROM users WHERE apple_sub = $1`,
    [sub],
  );
  return rows[0] ?? null;
}

/** Headline counters. One round trip via scalar subqueries. */
export async function getOverview() {
  // Mile counts mirror the rest of the app: soft-deleted (deleted_at) and
  // auto-excluded (exclusion_reason, e.g. vehicle-speed) workouts don't count.
  const [row] = await db.query(`
    SELECT
      (SELECT COUNT(*) FROM users)::int AS total_users,
      (SELECT COALESCE(SUM(distance), 0) FROM workouts
         WHERE deleted_at IS NULL AND exclusion_reason IS NULL)::float AS total_miles,
      -- "Today" must be the ET calendar day like every other daily counter:
      -- CURRENT_DATE is the DB server's UTC date, which flips at 8pm ET and
      -- zeroed miles_today every evening.
      (SELECT COALESCE(SUM(distance), 0) FROM workouts
         WHERE local_date = ${TODAY_ET_DATE_SQL}
           AND deleted_at IS NULL AND exclusion_reason IS NULL)::float AS miles_today,
      (SELECT COUNT(DISTINCT user_id) FROM workouts
         WHERE local_date >= ${TODAY_ET_DATE_SQL} - 7
           AND deleted_at IS NULL AND exclusion_reason IS NULL)::int AS active_users_7d,
      (SELECT COUNT(*) FROM hype_log)::int AS total_hypes,
      (SELECT COUNT(*) FROM hype_log
         WHERE created_at >= ${START_OF_TODAY_ET_SQL})::int AS hypes_today,
      -- Nudges live in TWO tables: friend_nudge_log (the friends-list nudge —
      -- the overwhelmingly common kind) and nudge_log (competition nudges).
      -- Counting only nudge_log made the dashboard read 0 forever. "Today"
      -- uses the app's midnight-ET reset, matching every other daily counter.
      ((SELECT COUNT(*) FROM nudge_log)
        + (SELECT COUNT(*) FROM friend_nudge_log))::int AS total_nudges,
      ((SELECT COUNT(*) FROM nudge_log
          WHERE created_at >= ${START_OF_TODAY_ET_SQL})
        + (SELECT COUNT(*) FROM friend_nudge_log
          WHERE created_at >= ${START_OF_TODAY_ET_SQL}))::int AS nudges_today
  `);
  return row;
}

/** Total miles per day for the last 30 days, zero-filled so the chart is
 *  continuous even on days nobody logged a mile. */
export async function getMilesByDay() {
  return db.query(`
    SELECT d::date::text AS date, COALESCE(SUM(w.distance), 0)::float AS miles
    FROM generate_series(${TODAY_ET_DATE_SQL} - 29, ${TODAY_ET_DATE_SQL}, INTERVAL '1 day') d
    LEFT JOIN workouts w
      ON w.local_date = d::date
      AND w.deleted_at IS NULL AND w.exclusion_reason IS NULL
    GROUP BY d
    ORDER BY d
  `);
}

/** Recent errors, newest first, optionally filtered by category and/or user. */
export async function getErrors(
  category: string | null,
  limit: number,
  userId: string | null = null,
) {
  return db.query(
    `SELECT e.id, e.category, e.user_id, u.username, e.message, e.context, e.created_at
     FROM error_log e
     LEFT JOIN users u ON u.user_id = e.user_id
     WHERE ($1::text IS NULL OR e.category = $1)
       AND ($3::text IS NULL OR e.user_id = $3)
     ORDER BY e.created_at DESC
     LIMIT $2`,
    [category, limit, userId],
  );
}

/** Error counts grouped by the user the error is attached to (for push
 *  errors that's the RECIPIENT), newest-first within, so admins can see who's
 *  generating the noise. NULL user_id rows collapse into one "no user" bucket. */
export async function getErrorsByUser() {
  return db.query(`
    SELECT e.user_id, u.username, COUNT(*)::int AS count,
           COUNT(*) FILTER (WHERE e.created_at >= NOW() - INTERVAL '24 hours')::int AS last_24h,
           MAX(e.created_at) AS last_at
    FROM error_log e
    LEFT JOIN users u ON u.user_id = e.user_id
    GROUP BY e.user_id, u.username
    ORDER BY count DESC
  `);
}

/** Error counts over a range, one row per (bucket, series). `series` is the
 *  category, or the user (username / id / "no user") when groupBy = 'user'.
 *  24h → hourly buckets; 7d/30d → daily. Buckets are UTC-keyed strings so the
 *  client can zero-fill against a matching `toISOString()`-derived axis.
 *  All SQL fragments come from whitelisted branches — no user input is
 *  interpolated, so this stays injection-safe.
 *  ponytail: bucket keys compared in UTC via AT TIME ZONE 'UTC', so it's
 *  independent of the DB session timezone. */
export async function getErrorTimeseries(
  range: "24h" | "7d" | "30d",
  groupBy: "category" | "user",
) {
  const bucketExpr =
    range === "24h"
      ? `to_char(date_trunc('hour', e.created_at AT TIME ZONE 'UTC'), 'YYYY-MM-DD"T"HH24')`
      : `to_char((e.created_at AT TIME ZONE 'UTC')::date, 'YYYY-MM-DD')`;
  const seriesExpr =
    groupBy === "user"
      ? `COALESCE(u.username, e.user_id, 'no user')`
      : `e.category`;
  const join =
    groupBy === "user" ? "LEFT JOIN users u ON u.user_id = e.user_id" : "";

  const params: unknown[] = [];
  let where: string;
  if (range === "24h") {
    where = `e.created_at >= NOW() - INTERVAL '24 hours'`;
  } else {
    params.push(range === "7d" ? 7 : 30);
    where = `e.created_at >= NOW() - ($1 || ' days')::interval`;
  }

  return db.query(
    `SELECT ${bucketExpr} AS bucket, ${seriesExpr} AS series, COUNT(*)::int AS count
     FROM error_log e
     ${join}
     WHERE ${where}
     GROUP BY 1, 2
     ORDER BY 1`,
    params,
  );
}

/** Category counts + last-24h count, for the error-view summary/filter. */
export async function getErrorSummary() {
  const byCategory = await db.query(`
    SELECT category, COUNT(*)::int AS count,
           COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '24 hours')::int AS last_24h
    FROM error_log
    GROUP BY category
    ORDER BY count DESC
  `);
  const [{ total }] = await db.query(
    `SELECT COUNT(*)::int AS total FROM error_log`,
  );
  return { total, byCategory };
}

// ─── Post forensics + restore (support tooling) ─────────────────────

/**
 * Every posts row for a user in a local-date window — INCLUDING soft-deleted
 * rows — with the linked workout and whether each media file still exists on
 * disk. Built for "my photo disappeared" investigations: the row shapes +
 * deleted_at timestamps show whether a photo post was deleted, replaced by an
 * auto card, or never existed, and file_exists says if a restore can still
 * bring the pixels back.
 */
export async function getPostForensics(
  userId: string,
  from: string,
  to: string,
) {
  const rows = await db.query<{
    post_id: string;
    workout_id: string | null;
    media_url: string;
    caption: string | null;
    is_auto: boolean;
    share_to_feed: boolean;
    share_to_story: boolean;
    local_date: string;
    story_expires_at: string | null;
    created_at: string;
    deleted_at: string | null;
    workout_type: string | null;
    workout_distance: number | null;
  }>(
    `SELECT p.post_id::text AS post_id, p.workout_id, p.media_url, p.caption,
			p.is_auto, p.share_to_feed, p.share_to_story,
			p.local_date::text AS local_date, p.story_expires_at, p.created_at,
			p.deleted_at,
			w.workout_type, w.distance::float AS workout_distance
		FROM posts p
		LEFT JOIN workouts w ON w.workout_id = p.workout_id
		WHERE p.user_id = $1 AND p.local_date BETWEEN $2::date AND $3::date
		ORDER BY p.created_at`,
    [userId, from, to],
  );

  return rows.map((r) => {
    // Stored values MAY carry a legacy ?e=&s= signature — always work on the
    // bare path for disk checks, and expose the bare FILENAME so recovery
    // (host snapshots, device caches) knows exactly what to look for. The
    // filename passes through the response signer untouched (it only rewrites
    // strings starting with /uploads/posts/).
    const barePath = r.media_url.split("?")[0];
    return {
      ...r,
      media_file: barePath.startsWith("/uploads/posts/")
        ? barePath.slice("/uploads/posts/".length)
        : null,
      media_file_exists: barePath.startsWith("/uploads/")
        ? fs.existsSync(path.join(process.cwd(), barePath.replace(/^\//, "")))
        : null,
    };
  });
}

/**
 * Clear a soft-deleted post's deleted_at so it surfaces again. Refuses when a
 * LIVE post now occupies the same one-per-workout slot (restoring would
 * violate the partial unique index). Restoring the ROW only helps if the
 * media file survived — check media_file_exists in getPostForensics first.
 */
export async function restoreDeletedPost(
  postId: string,
): Promise<
  | { status: "not_found" | "already_live" }
  | { status: "slot_taken"; by: string }
  | { status: "restored" }
> {
  const rows = await db.query<{
    post_id: string;
    user_id: string;
    workout_id: string | null;
    share_to_feed: boolean;
    share_to_story: boolean;
    deleted_at: string | null;
  }>(
    `SELECT post_id::text AS post_id, user_id, workout_id,
			share_to_feed, share_to_story, deleted_at
		FROM posts WHERE post_id = $1::uuid`,
    [postId],
  );
  const row = rows[0];
  if (!row) return { status: "not_found" };
  if (!row.deleted_at) return { status: "already_live" };

  if (row.workout_id) {
    const slotPredicate = row.share_to_feed
      ? "share_to_feed"
      : "(share_to_story AND NOT share_to_feed)";
    const occupied = await db.query<{ post_id: string }>(
      `SELECT post_id::text AS post_id FROM posts
			WHERE workout_id = $1 AND user_id = $2 AND deleted_at IS NULL
				AND ${slotPredicate}
			LIMIT 1`,
      [row.workout_id, row.user_id],
    );
    if (occupied[0]) return { status: "slot_taken", by: occupied[0].post_id };
  }

  await db.query(
    `UPDATE posts SET deleted_at = NULL WHERE post_id = $1::uuid`,
    [postId],
  );
  return { status: "restored" };
}

/**
 * Paginated + searchable user directory, enriched with the per-user rollups
 * the admin table shows (streak, lifetime miles, last-active day, live post
 * count, acquisition source). `search` matches username / email / full name
 * case-insensitively. Returns the page plus the total match count so the UI
 * can render "showing N of M" and page controls.
 */
export async function getUsers(opts: {
  search: string | null;
  limit: number;
  offset: number;
  sort?: "recent" | "streak" | "miles" | "active";
}) {
  const like = opts.search ? `%${opts.search}%` : null;
  const where = `WHERE ($1::text IS NULL
      OR u.username ILIKE $1
      OR u.email ILIKE $1
      OR (COALESCE(u.first_name, '') || ' ' || COALESCE(u.last_name, '')) ILIKE $1)`;

  const [{ total }] = await db.query<{ total: number }>(
    `SELECT COUNT(*)::int AS total FROM users u ${where}`,
    [like],
  );

  const orderBy =
    opts.sort === "streak"
      ? "u.current_streak DESC NULLS LAST, u.created_at DESC"
      : opts.sort === "miles"
        ? "total_miles DESC NULLS LAST, u.created_at DESC"
        : opts.sort === "active"
          ? "last_active DESC NULLS LAST, u.created_at DESC"
          : "u.created_at DESC";

  const users = await db.query(
    `SELECT u.user_id, u.username, u.first_name, u.last_name, u.email,
            u.role, u.current_streak, u.referral_source,
            u.created_at, u.terms_accepted_at,
            COALESCE(w.total_miles, 0)::float AS total_miles,
            w.last_active,
            COALESCE(p.post_count, 0)::int AS post_count
     FROM users u
     LEFT JOIN LATERAL (
       SELECT SUM(distance) AS total_miles, MAX(local_date)::text AS last_active
       FROM workouts
       WHERE user_id = u.user_id AND deleted_at IS NULL AND exclusion_reason IS NULL
     ) w ON TRUE
     LEFT JOIN LATERAL (
       SELECT COUNT(*) AS post_count
       FROM posts
       WHERE user_id = u.user_id AND deleted_at IS NULL
     ) p ON TRUE
     ${where}
     ORDER BY ${orderBy}
     LIMIT $2 OFFSET $3`,
    [like, opts.limit, opts.offset],
  );

  return { total, users };
}

/**
 * Everything the user-detail modal shows: profile, lifetime + recent activity
 * rollups, social graph counts, registered push devices, and the most recent
 * workouts and posts. Returns null when the id is unknown. Post media urls are
 * signed by the controller; profile images stay public and pass through.
 */
export async function getUserDetail(userId: string) {
  const [profile] = await db.query(
    `SELECT user_id, username, first_name, last_name, email, bio, role,
            profile_image_url, goal_miles::float AS goal_miles, current_streak,
            terms_accepted_at, onboarding_completed_at,
            referral_source, referral_detail, signup_goal, experience_level,
            created_at
     FROM users WHERE user_id = $1`,
    [userId],
  );
  if (!profile) return null;

  const [stats] = await db.query(
    `SELECT
       COALESCE(SUM(distance), 0)::float AS total_miles,
       COUNT(*)::int AS total_workouts,
       COUNT(DISTINCT local_date)::int AS active_days,
       COALESCE(SUM(distance) FILTER (WHERE local_date >= ${TODAY_ET_DATE_SQL} - 6), 0)::float AS miles_7d,
       COALESCE(SUM(distance) FILTER (WHERE local_date >= ${TODAY_ET_DATE_SQL} - 29), 0)::float AS miles_30d,
       MAX(local_date)::text AS last_active,
       MIN(local_date)::text AS first_active
     FROM workouts
     WHERE user_id = $1 AND deleted_at IS NULL AND exclusion_reason IS NULL`,
    [userId],
  );

  const [social] = await db.query(
    `SELECT
       (SELECT COUNT(*) FROM friendships WHERE user_id = $1 AND status = 'accepted')::int AS friends,
       (SELECT COUNT(*) FROM hype_log WHERE sender_id = $1)::int AS hypes_sent,
       (SELECT COUNT(*) FROM hype_log WHERE target_id = $1)::int AS hypes_received,
       ((SELECT COUNT(*) FROM friend_nudge_log WHERE sender_id = $1)
         + (SELECT COUNT(*) FROM nudge_log WHERE sender_id = $1))::int AS nudges_sent,
       ((SELECT COUNT(*) FROM friend_nudge_log WHERE target_id = $1)
         + (SELECT COUNT(*) FROM nudge_log WHERE target_id = $1))::int AS nudges_received,
       (SELECT COUNT(*) FROM posts WHERE user_id = $1 AND deleted_at IS NULL)::int AS posts_live,
       (SELECT COUNT(*) FROM posts WHERE user_id = $1)::int AS posts_total
     `,
    [userId],
  );

  const devices = await db.query(
    `SELECT environment, created_at, updated_at
     FROM device_tokens WHERE user_id = $1 ORDER BY updated_at DESC`,
    [userId],
  );

  const recentWorkouts = await db.query(
    `SELECT workout_id, workout_type, distance::float AS distance,
            local_date::text AS local_date, total_duration::float AS total_duration,
            deleted_at, exclusion_reason, speed_flagged
     FROM workouts WHERE user_id = $1
     ORDER BY local_date DESC, device_end_date DESC LIMIT 8`,
    [userId],
  );

  const recentPosts = await db.query(
    `SELECT post_id::text AS post_id, media_url, caption, is_auto, share_to_feed,
            share_to_story, local_date::text AS local_date, created_at, deleted_at
     FROM posts WHERE user_id = $1
     ORDER BY created_at DESC LIMIT 6`,
    [userId],
  );

  return {
    profile,
    stats,
    social,
    devices,
    recent_workouts: recentWorkouts,
    recent_posts: recentPosts,
  };
}

// ─── Engagement + growth ────────────────────────────────────────────

/** Active-user and new-signup counters over the standard windows. "Active" =
 *  logged a counting workout in the window (ET calendar days). New-user
 *  windows use signup time (created_at). */
export async function getEngagement() {
  const [row] = await db.query(`
    SELECT
      (SELECT COUNT(DISTINCT user_id) FROM workouts
         WHERE local_date = ${TODAY_ET_DATE_SQL}
           AND deleted_at IS NULL AND exclusion_reason IS NULL)::int AS dau,
      (SELECT COUNT(DISTINCT user_id) FROM workouts
         WHERE local_date >= ${TODAY_ET_DATE_SQL} - 6
           AND deleted_at IS NULL AND exclusion_reason IS NULL)::int AS wau,
      (SELECT COUNT(DISTINCT user_id) FROM workouts
         WHERE local_date >= ${TODAY_ET_DATE_SQL} - 29
           AND deleted_at IS NULL AND exclusion_reason IS NULL)::int AS mau,
      (SELECT COUNT(*) FROM users
         WHERE created_at >= ${START_OF_TODAY_ET_SQL})::int AS new_today,
      (SELECT COUNT(*) FROM users
         WHERE created_at >= NOW() - INTERVAL '7 days')::int AS new_7d,
      (SELECT COUNT(*) FROM users
         WHERE created_at >= NOW() - INTERVAL '30 days')::int AS new_30d
  `);
  return row;
}

/** New signups per day for the last 30 days (ET), zero-filled. */
export async function getSignupsByDay() {
  return db.query(`
    SELECT d::date::text AS date, COUNT(u.user_id)::int AS count
    FROM generate_series(${TODAY_ET_DATE_SQL} - 29, ${TODAY_ET_DATE_SQL}, INTERVAL '1 day') d
    LEFT JOIN users u
      ON (u.created_at AT TIME ZONE 'America/New_York')::date = d::date
    GROUP BY d
    ORDER BY d
  `);
}

/** Top-streak and top-miles leaderboards for the overview (fun stats). */
export async function getLeaderboards() {
  const topStreaks = await db.query(`
    SELECT user_id, username, current_streak
    FROM users
    WHERE current_streak > 0
    ORDER BY current_streak DESC, username ASC
    LIMIT 8
  `);
  const topMilers = await db.query(`
    SELECT u.user_id, u.username, COALESCE(SUM(w.distance), 0)::float AS total_miles
    FROM users u
    JOIN workouts w
      ON w.user_id = u.user_id AND w.deleted_at IS NULL AND w.exclusion_reason IS NULL
    GROUP BY u.user_id, u.username
    ORDER BY total_miles DESC
    LIMIT 8
  `);
  return { top_streaks: topStreaks, top_milers: topMilers };
}

/** Workout-type split (count + miles) across all counting workouts. */
export async function getWorkoutTypeBreakdown() {
  return db.query(`
    SELECT COALESCE(workout_type, 'unknown') AS type,
           COUNT(*)::int AS count,
           COALESCE(SUM(distance), 0)::float AS miles
    FROM workouts
    WHERE deleted_at IS NULL AND exclusion_reason IS NULL
    GROUP BY 1
    ORDER BY count DESC
  `);
}

// ─── Photo / post storage + analytics ───────────────────────────────

export interface StorageStats {
  disk: { total: number; free: number; used: number; used_pct: number } | null;
  uploads: { total_bytes: number; file_count: number };
  posts_media: {
    total_bytes: number;
    file_count: number;
    avg_bytes: number;
    largest: { file: string; bytes: number }[];
  };
  profile_media: { total_bytes: number; file_count: number };
  integrity: {
    referenced_on_disk: number;
    orphan_files: number;
    orphan_bytes: number;
    missing_files: number;
  };
  generated_at: string;
}

/** Recursively sum file sizes under a directory. Returns total bytes, file
 *  count, and a basename→size map (post filenames are unique uuids, so the
 *  flat map is safe for the integrity join). Missing dirs read as empty. */
async function walkDir(
  dir: string,
): Promise<{ bytes: number; count: number; files: Map<string, number> }> {
  const files = new Map<string, number>();
  let bytes = 0;
  let count = 0;
  let entries: fs.Dirent[];
  try {
    entries = await fsp.readdir(dir, { withFileTypes: true });
  } catch {
    return { bytes, count, files };
  }
  for (const ent of entries) {
    const full = path.join(dir, ent.name);
    if (ent.isDirectory()) {
      const sub = await walkDir(full);
      bytes += sub.bytes;
      count += sub.count;
      for (const [k, v] of sub.files) files.set(k, v);
    } else if (ent.isFile()) {
      try {
        const st = await fsp.stat(full);
        bytes += st.size;
        count += 1;
        files.set(ent.name, st.size);
      } catch {
        /* raced a delete — skip */
      }
    }
  }
  return { bytes, count, files };
}

// Walking the uploads tree + statting every file is disk-heavy; the dashboard
// polls, so a short cache keeps repeated loads from hammering the volume.
let storageCache: { data: StorageStats; at: number } | null = null;
const STORAGE_CACHE_TTL_MS = 30_000;

/**
 * Disk + media storage snapshot: how much the volume has, how much the
 * uploads tree (and post photos specifically) occupy, and integrity signals —
 * orphaned files on disk that no posts row references (safe-to-reclaim), and
 * live posts whose media file has vanished.
 */
export async function getStorageStats(): Promise<StorageStats> {
  if (storageCache && Date.now() - storageCache.at < STORAGE_CACHE_TTL_MS) {
    return storageCache.data;
  }

  const [uploads, posts] = await Promise.all([
    walkDir(UPLOADS_ROOT),
    walkDir(POSTS_MEDIA_DIR),
  ]);

  let disk: StorageStats["disk"] = null;
  try {
    const vfs = await fsp.statfs(process.cwd());
    const total = vfs.blocks * vfs.bsize;
    const free = vfs.bavail * vfs.bsize;
    const used = total - free;
    disk = {
      total,
      free,
      used,
      used_pct: total ? Math.round((used / total) * 1000) / 10 : 0,
    };
  } catch {
    disk = null;
  }

  // Integrity: reconcile on-disk post files against posts rows.
  const rows = await db.query<{ media_url: string; deleted_at: string | null }>(
    `SELECT media_url, deleted_at FROM posts`,
  );
  const referenced = new Set<string>();
  let missing = 0;
  for (const r of rows) {
    const base = path.basename(r.media_url.split("?")[0]);
    referenced.add(base);
    if (!r.deleted_at && !posts.files.has(base)) missing++;
  }
  let orphanFiles = 0;
  let orphanBytes = 0;
  let referencedOnDisk = 0;
  for (const [name, size] of posts.files) {
    if (referenced.has(name)) referencedOnDisk++;
    else {
      orphanFiles++;
      orphanBytes += size;
    }
  }

  const largest = [...posts.files.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5)
    .map(([file, bytes]) => ({ file, bytes }));

  const data: StorageStats = {
    disk,
    uploads: { total_bytes: uploads.bytes, file_count: uploads.count },
    posts_media: {
      total_bytes: posts.bytes,
      file_count: posts.count,
      avg_bytes: posts.count ? Math.round(posts.bytes / posts.count) : 0,
      largest,
    },
    profile_media: {
      total_bytes: Math.max(uploads.bytes - posts.bytes, 0),
      file_count: Math.max(uploads.count - posts.count, 0),
    },
    integrity: {
      referenced_on_disk: referencedOnDisk,
      orphan_files: orphanFiles,
      orphan_bytes: orphanBytes,
      missing_files: missing,
    },
    generated_at: new Date().toISOString(),
  };
  storageCache = { data, at: Date.now() };
  return data;
}

/** Post/photo headline counters: totals split by lifecycle (live/deleted),
 *  surface (feed/story), and origin (user photo vs auto route card). */
export async function getPostsSummary() {
  const [row] = await db.query(`
    SELECT
      COUNT(*)::int AS total,
      COUNT(*) FILTER (WHERE deleted_at IS NULL)::int AS live,
      COUNT(*) FILTER (WHERE deleted_at IS NOT NULL)::int AS deleted,
      COUNT(*) FILTER (WHERE deleted_at IS NULL AND share_to_feed)::int AS feed,
      COUNT(*) FILTER (WHERE deleted_at IS NULL AND share_to_story)::int AS story,
      COUNT(*) FILTER (WHERE is_auto)::int AS auto_cards,
      COUNT(*) FILTER (WHERE NOT is_auto)::int AS user_photos,
      COUNT(*) FILTER (WHERE local_date = ${TODAY_ET_DATE_SQL})::int AS today,
      COUNT(DISTINCT user_id)::int AS posters
    FROM posts
  `);
  return row;
}

/** Posts created per day for the last 30 days (ET), split total vs user
 *  photos (non-auto), zero-filled for a continuous chart. */
export async function getPostsByDay() {
  return db.query(`
    SELECT d::date::text AS date,
           COUNT(p.post_id)::int AS count,
           COUNT(p.post_id) FILTER (WHERE NOT p.is_auto)::int AS user_count
    FROM generate_series(${TODAY_ET_DATE_SQL} - 29, ${TODAY_ET_DATE_SQL}, INTERVAL '1 day') d
    LEFT JOIN posts p ON p.local_date = d::date
    GROUP BY d
    ORDER BY d
  `);
}

export type PostFilter =
  | "all"
  | "live"
  | "deleted"
  | "feed"
  | "story"
  | "auto"
  | "user";

/**
 * Paginated browse of all posts (newest first) for the content tab, with the
 * author, the linked workout, and whether the media file still exists on disk.
 * `filter` narrows by lifecycle/surface/origin; `search` matches username or
 * caption. Media urls are signed by the controller.
 */
export async function listPosts(opts: {
  search: string | null;
  filter: PostFilter;
  limit: number;
  offset: number;
}) {
  const clauses: string[] = [];
  const params: unknown[] = [];
  switch (opts.filter) {
    case "live":
      clauses.push("p.deleted_at IS NULL");
      break;
    case "deleted":
      clauses.push("p.deleted_at IS NOT NULL");
      break;
    case "feed":
      clauses.push("p.deleted_at IS NULL AND p.share_to_feed");
      break;
    case "story":
      clauses.push("p.deleted_at IS NULL AND p.share_to_story");
      break;
    case "auto":
      clauses.push("p.is_auto");
      break;
    case "user":
      clauses.push("NOT p.is_auto");
      break;
  }
  if (opts.search) {
    params.push(`%${opts.search}%`);
    clauses.push(
      `(u.username ILIKE $${params.length} OR p.caption ILIKE $${params.length})`,
    );
  }
  const where = clauses.length ? `WHERE ${clauses.join(" AND ")}` : "";

  const [{ total }] = await db.query<{ total: number }>(
    `SELECT COUNT(*)::int AS total
     FROM posts p LEFT JOIN users u ON u.user_id = p.user_id ${where}`,
    params,
  );

  params.push(opts.limit);
  const limIdx = params.length;
  params.push(opts.offset);
  const offIdx = params.length;

  const rows = await db.query<{
    post_id: string;
    user_id: string;
    username: string | null;
    profile_image_url: string | null;
    media_url: string;
    caption: string | null;
    is_auto: boolean;
    share_to_feed: boolean;
    share_to_story: boolean;
    local_date: string;
    created_at: string;
    deleted_at: string | null;
    workout_type: string | null;
    workout_distance: number | null;
  }>(
    `SELECT p.post_id::text AS post_id, p.user_id, u.username, u.profile_image_url,
            p.media_url, p.caption, p.is_auto, p.share_to_feed, p.share_to_story,
            p.local_date::text AS local_date, p.created_at, p.deleted_at,
            w.workout_type, w.distance::float AS workout_distance
     FROM posts p
     LEFT JOIN users u ON u.user_id = p.user_id
     LEFT JOIN workouts w ON w.workout_id = p.workout_id
     ${where}
     ORDER BY p.created_at DESC
     LIMIT $${limIdx} OFFSET $${offIdx}`,
    params,
  );

  const posts = rows.map((r) => {
    const barePath = r.media_url.split("?")[0];
    return {
      ...r,
      media_file_exists: barePath.startsWith("/uploads/")
        ? fs.existsSync(path.join(process.cwd(), barePath.replace(/^\//, "")))
        : null,
    };
  });

  return { total, posts };
}

// ─── Referrals / acquisition ────────────────────────────────────────

/**
 * Acquisition + onboarding analytics: where users say they came from, what
 * their signup goal / experience level is, top named friend-referrers, and the
 * onboarding completion funnel. `unknown` buckets users predating the
 * onboarding step (referral columns null).
 */
export async function getReferralStats() {
  const bySource = await db.query(`
    SELECT COALESCE(referral_source, 'unknown') AS source, COUNT(*)::int AS count
    FROM users GROUP BY 1 ORDER BY count DESC
  `);
  const byGoal = await db.query(`
    SELECT COALESCE(signup_goal, 'unknown') AS goal, COUNT(*)::int AS count
    FROM users GROUP BY 1 ORDER BY count DESC
  `);
  const byExperience = await db.query(`
    SELECT COALESCE(experience_level, 'unknown') AS level, COUNT(*)::int AS count
    FROM users GROUP BY 1 ORDER BY count DESC
  `);
  const friendReferrers = await db.query(`
    SELECT referral_detail AS detail, COUNT(*)::int AS count
    FROM users
    WHERE referral_source = 'friend' AND referral_detail IS NOT NULL AND referral_detail <> ''
    GROUP BY 1 ORDER BY count DESC LIMIT 10
  `);
  const [funnel] = await db.query(`
    SELECT
      COUNT(*)::int AS total,
      COUNT(*) FILTER (WHERE onboarding_completed_at IS NOT NULL)::int AS completed_onboarding,
      COUNT(*) FILTER (WHERE referral_source IS NOT NULL)::int AS gave_source
    FROM users
  `);
  return {
    by_source: bySource,
    by_goal: byGoal,
    by_experience: byExperience,
    friend_referrers: friendReferrers,
    funnel,
  };
}
