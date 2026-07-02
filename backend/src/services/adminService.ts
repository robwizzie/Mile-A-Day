import { PostgresService } from "./DbService.js";

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
      (SELECT COUNT(*) FROM hype_log WHERE created_at >= CURRENT_DATE)::int AS hypes_today,
      (SELECT COUNT(*) FROM nudge_log)::int AS total_nudges,
      (SELECT COUNT(*) FROM nudge_log WHERE created_at >= CURRENT_DATE)::int AS nudges_today
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
