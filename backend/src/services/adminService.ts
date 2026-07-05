import { PostgresService } from "./DbService.js";
import { START_OF_TODAY_ET_SQL } from "./dailyResetTime.js";

const db = PostgresService.getInstance();

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
      (SELECT COALESCE(SUM(distance), 0) FROM workouts
         WHERE local_date = CURRENT_DATE
           AND deleted_at IS NULL AND exclusion_reason IS NULL)::float AS miles_today,
      (SELECT COUNT(DISTINCT user_id) FROM workouts
         WHERE local_date >= CURRENT_DATE - INTERVAL '7 days'
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
    FROM generate_series(CURRENT_DATE - INTERVAL '29 days', CURRENT_DATE, INTERVAL '1 day') d
    LEFT JOIN workouts w
      ON w.local_date = d::date
      AND w.deleted_at IS NULL AND w.exclusion_reason IS NULL
    GROUP BY d
    ORDER BY d
  `);
}

/** Recent errors, newest first, optionally filtered by category. */
export async function getErrors(category: string | null, limit: number) {
  return db.query(
    `SELECT id, category, user_id, message, context, created_at
     FROM error_log
     WHERE ($1::text IS NULL OR category = $1)
     ORDER BY created_at DESC
     LIMIT $2`,
    [category, limit],
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

  const fs = await import("fs");
  const path = await import("path");
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
