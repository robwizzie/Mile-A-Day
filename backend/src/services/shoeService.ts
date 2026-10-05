import { PostgresService } from "./DbService.js";
import { countedWorkoutSql } from "./mileTime.js";

const db = PostgresService.getInstance();

/**
 * Shoes are PRIVATE gear: every function here is called only from
 * `requireSelfAccess` routes, and nothing outside this file reads the
 * `shoes` / `workout_shoes` tables — no feed, profile, friend or post query
 * may ever join them.
 */

/** Workout types a default shoe is stamped onto — everything on foot. */
export const SHOE_FOOT_TYPES = ["running", "walking", "hiking", "other"];

/** A runaway-client backstop, far above any real rotation. */
export const MAX_SHOES_PER_USER = 50;

export interface ShoeRow {
  shoe_id: string;
  name: string;
  brand: string | null;
  colorway: string | null;
  image_url: string | null;
  starting_miles: number;
  replace_at_miles: number | null;
  is_default: boolean;
  retired_at: string | null;
  created_at: string;
  tracked_miles: number;
  total_miles: number;
  workout_count: number;
  first_used: string | null;
  last_used: string | null;
}

export interface ShoeInput {
  name?: string;
  brand?: string | null;
  colorway?: string | null;
  starting_miles?: number;
  replace_at_miles?: number | null;
  is_default?: boolean;
  retired?: boolean;
}

// Mileage is derived at read, never stored: it has to follow every edit,
// delete and duplicate decision on the workouts underneath, and
// `countedWorkoutSql` is what keeps a Strava+Watch twin from counting twice.
const SHOE_SELECT = `
  SELECT s.shoe_id::text AS shoe_id, s.name, s.brand, s.colorway,
         s.image_url, s.starting_miles, s.replace_at_miles,
         s.is_default,
         to_char(s.retired_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS retired_at,
         to_char(s.created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS created_at,
         COALESCE(m.miles, 0)::float8 AS tracked_miles,
         (s.starting_miles + COALESCE(m.miles, 0))::float8 AS total_miles,
         COALESCE(m.workouts, 0)::int AS workout_count,
         m.first_used::text AS first_used,
         m.last_used::text AS last_used
  FROM shoes s
  LEFT JOIN LATERAL (
    SELECT SUM(w.distance) AS miles,
           COUNT(*) AS workouts,
           MIN(w.local_date) AS first_used,
           MAX(w.local_date) AS last_used
    FROM workout_shoes ws
    JOIN workouts w
      ON w.workout_id = ws.workout_id AND w.user_id = ws.user_id
    WHERE ws.shoe_id = s.shoe_id
      AND ws.user_id = s.user_id
      AND ${countedWorkoutSql("w")}
  ) m ON true
`;

export async function listShoes(userId: string): Promise<ShoeRow[]> {
  return db.query<ShoeRow>(
    `${SHOE_SELECT}
     WHERE s.user_id = $1
     ORDER BY (s.retired_at IS NOT NULL), s.is_default DESC,
              m.last_used DESC NULLS LAST, s.created_at DESC`,
    [userId],
  );
}

export async function getShoe(
  userId: string,
  shoeId: string,
): Promise<ShoeRow | null> {
  const rows = await db.query<ShoeRow>(
    `${SHOE_SELECT} WHERE s.user_id = $1 AND s.shoe_id = $2::uuid`,
    [userId, shoeId],
  );
  return rows[0] ?? null;
}

/** Runs `fn` inside BEGIN/COMMIT on one client. */
async function inTransaction<T>(
  fn: (q: (sql: string, params?: any[]) => Promise<any[]>) => Promise<T>,
): Promise<T> {
  const client = await db.getClient();
  try {
    await client.query("BEGIN");
    const result = await fn(
      async (sql, params) => (await client.query(sql, params)).rows,
    );
    await client.query("COMMIT");
    return result;
  } catch (err) {
    await client.query("ROLLBACK");
    throw err;
  } finally {
    client.release();
  }
}

// Clearing the old default is its own statement, run before the new one is
// set: the one-default-per-user index is checked row by row, so the two
// writes can't share one statement.
const CLEAR_DEFAULT_SQL = `
  UPDATE shoes SET is_default = false, default_since = NULL, updated_at = now()
  WHERE user_id = $1 AND is_default AND shoe_id <> $2::uuid`;

export async function countShoes(userId: string): Promise<number> {
  const rows = await db.query<{ n: number }>(
    `SELECT COUNT(*)::int AS n FROM shoes WHERE user_id = $1`,
    [userId],
  );
  return rows[0]?.n ?? 0;
}

export async function createShoe(
  userId: string,
  input: Required<Pick<ShoeInput, "name">> & ShoeInput,
): Promise<ShoeRow> {
  const shoeId = await inTransaction(async (q) => {
    if (input.is_default) {
      await q(CLEAR_DEFAULT_SQL, [
        userId,
        "00000000-0000-0000-0000-000000000000",
      ]);
    }
    const rows = await q(
      `INSERT INTO shoes (user_id, name, brand, colorway,
                          starting_miles, replace_at_miles, is_default, default_since)
       VALUES ($1, $2, $3, $4, $5, $6, $7::boolean,
               CASE WHEN $7::boolean THEN now() END)
       RETURNING shoe_id::text AS shoe_id`,
      [
        userId,
        input.name,
        input.brand ?? null,
        input.colorway ?? null,
        input.starting_miles ?? 0,
        input.replace_at_miles ?? null,
        input.is_default === true,
      ],
    );
    return rows[0].shoe_id as string;
  });
  return (await getShoe(userId, shoeId))!;
}

export async function updateShoe(
  userId: string,
  shoeId: string,
  patch: ShoeInput,
): Promise<ShoeRow | null> {
  const found = await inTransaction(async (q) => {
    const existing = await q(
      `SELECT is_default, retired_at FROM shoes
       WHERE user_id = $1 AND shoe_id = $2::uuid FOR UPDATE`,
      [userId, shoeId],
    );
    if (!existing.length) return false;

    const sets: string[] = [];
    const params: any[] = [userId, shoeId];
    const set = (column: string, value: unknown) => {
      params.push(value);
      sets.push(`${column} = $${params.length}`);
    };
    if (patch.name !== undefined) set("name", patch.name);
    if (patch.brand !== undefined) set("brand", patch.brand);
    if (patch.colorway !== undefined) set("colorway", patch.colorway);
    if (patch.starting_miles !== undefined)
      set("starting_miles", patch.starting_miles);
    if (patch.replace_at_miles !== undefined)
      set("replace_at_miles", patch.replace_at_miles);

    // A retired pair can't be the default; retiring the default leaves the
    // user with none rather than silently promoting another pair.
    const retiring = patch.retired === true;
    if (patch.retired !== undefined) {
      sets.push(
        retiring
          ? `retired_at = COALESCE(retired_at, now())`
          : `retired_at = NULL`,
      );
    }
    if (retiring || patch.is_default === false) {
      sets.push(`is_default = false`, `default_since = NULL`);
    } else if (patch.is_default === true && !existing[0].is_default) {
      await q(CLEAR_DEFAULT_SQL, [userId, shoeId]);
      sets.push(`is_default = true`, `default_since = now()`);
      // Making a retired pair the default brings it back into rotation.
      if (patch.retired === undefined) sets.push(`retired_at = NULL`);
    }

    if (sets.length) {
      await q(
        `UPDATE shoes SET ${sets.join(", ")}, updated_at = now()
         WHERE user_id = $1 AND shoe_id = $2::uuid`,
        params,
      );
    }
    return true;
  });
  return found ? getShoe(userId, shoeId) : null;
}

/** Deletes the shoe; returns its image path so the caller can unlink it. */
export async function deleteShoe(
  userId: string,
  shoeId: string,
): Promise<{ deleted: boolean; imageUrl: string | null }> {
  // workout_shoes.shoe_id is ON DELETE SET NULL: the workouts it was on keep
  // an explicit "no shoe" rather than being re-stamped with today's default
  // by the next full sync.
  const rows = await db.query<{ image_url: string | null }>(
    `DELETE FROM shoes WHERE user_id = $1 AND shoe_id = $2::uuid RETURNING image_url`,
    [userId, shoeId],
  );
  return { deleted: rows.length > 0, imageUrl: rows[0]?.image_url ?? null };
}

/** Points the shoe at a new image; returns the old path (to unlink) or undefined if no such shoe. */
export async function setShoeImage(
  userId: string,
  shoeId: string,
  imageUrl: string,
): Promise<{ found: boolean; previous: string | null }> {
  const rows = await db.query<{ previous: string | null }>(
    `UPDATE shoes s SET image_url = $3, updated_at = now()
     FROM (SELECT image_url FROM shoes WHERE user_id = $1 AND shoe_id = $2::uuid) old
     WHERE s.user_id = $1 AND s.shoe_id = $2::uuid
     RETURNING old.image_url AS previous`,
    [userId, shoeId, imageUrl],
  );
  return { found: rows.length > 0, previous: rows[0]?.previous ?? null };
}

export async function shoeExists(
  userId: string,
  shoeId: string,
): Promise<boolean> {
  const rows = await db.query(
    `SELECT 1 FROM shoes WHERE user_id = $1 AND shoe_id = $2::uuid`,
    [userId, shoeId],
  );
  return rows.length > 0;
}

export type WorkoutShoeSource = "user" | "default" | "predicted" | null;

/**
 * The shoe on one workout:
 *  - a row exists → its shoe (NULL = the user said "none"), source = who set it;
 *  - the workout has synced but has no row → none (it predates the default,
 *    or isn't on foot);
 *  - the workout hasn't reached the server yet (the recap opens before the
 *    sync) → the current default, `predicted`, which is exactly what the
 *    sync will stamp when it lands.
 */
export async function getWorkoutShoe(
  userId: string,
  workoutId: string,
): Promise<{ shoe_id: string | null; source: WorkoutShoeSource }> {
  const rows = await db.query<{
    assigned: boolean;
    shoe_id: string | null;
    assigned_by: "user" | "default" | null;
    synced: boolean;
    default_id: string | null;
  }>(
    `SELECT
       ws.user_id IS NOT NULL AS assigned,
       ws.shoe_id::text AS shoe_id,
       ws.assigned_by,
       EXISTS (SELECT 1 FROM workouts w
               WHERE w.workout_id = $2::text AND w.user_id = $1::text) AS synced,
       (SELECT d.shoe_id::text FROM shoes d
        WHERE d.user_id = $1::text AND d.is_default AND d.retired_at IS NULL) AS default_id
     FROM (SELECT 1) one
     LEFT JOIN workout_shoes ws ON ws.user_id = $1::text AND ws.workout_id = $2::text`,
    [userId, workoutId],
  );
  const r = rows[0];
  if (r.assigned) return { shoe_id: r.shoe_id, source: r.assigned_by };
  if (r.synced) return { shoe_id: null, source: null };
  return r.default_id
    ? { shoe_id: r.default_id, source: "predicted" }
    : { shoe_id: null, source: null };
}

/** Explicit pick (or explicit "none" with `shoeId` null). Ownership checked by the caller. */
export async function setWorkoutShoe(
  userId: string,
  workoutId: string,
  shoeId: string | null,
): Promise<void> {
  await db.query(
    `INSERT INTO workout_shoes (user_id, workout_id, shoe_id, assigned_by, assigned_at)
     VALUES ($1, $2, $3::uuid, 'user', now())
     ON CONFLICT (user_id, workout_id) DO UPDATE
       SET shoe_id = EXCLUDED.shoe_id, assigned_by = 'user', assigned_at = now()`,
    [userId, workoutId, shoeId],
  );
}

export interface ShoeWorkoutRow {
  workout_id: string;
  local_date: string;
  workout_type: string;
  distance: number;
  total_duration: number;
}

/** The counted workouts behind a shoe's mileage, newest first. */
export async function listShoeWorkouts(
  userId: string,
  shoeId: string,
  limit = 100,
): Promise<ShoeWorkoutRow[]> {
  return db.query<ShoeWorkoutRow>(
    `SELECT w.workout_id, w.local_date::text AS local_date, w.workout_type,
            w.distance, w.total_duration
     FROM workout_shoes ws
     JOIN workouts w ON w.workout_id = ws.workout_id AND w.user_id = ws.user_id
     WHERE ws.user_id = $1 AND ws.shoe_id = $2::uuid AND ${countedWorkoutSql("w")}
     ORDER BY w.local_date DESC, w.device_end_date DESC NULLS LAST
     LIMIT $3`,
    [userId, shoeId, limit],
  );
}

/**
 * Spliced into the workout upload transaction AFTER the upsert: stamps the
 * user's default shoe onto the workouts in this batch that are on foot,
 * ended after that pair BECAME the default, and carry no assignment yet.
 *
 * `ON CONFLICT DO NOTHING` is what makes it safe to run on every sync: a pick
 * made on the recap (before the workout synced), an explicit "none", and an
 * earlier stamp all win, and a full re-sync of history can't sweep old
 * workouts onto a pair bought last week.
 */
export function defaultShoeStampStatement(
  userId: string,
  workoutIds: string[],
) {
  return {
    query: `
      INSERT INTO workout_shoes (user_id, workout_id, shoe_id, assigned_by)
      SELECT $1::text, w.workout_id, s.shoe_id, 'default'
      FROM shoes s
      JOIN workouts w ON w.user_id = s.user_id
      WHERE s.user_id = $1::text
        AND s.is_default
        AND s.retired_at IS NULL
        AND w.workout_id = ANY($2::text[])
        AND w.deleted_at IS NULL
        AND w.workout_type = ANY($3::text[])
        AND w.device_end_date >= COALESCE(s.default_since, s.created_at)
      ON CONFLICT (user_id, workout_id) DO NOTHING`,
    params: [userId, workoutIds, SHOE_FOOT_TYPES],
  };
}
