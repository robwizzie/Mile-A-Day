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

/**
 * A default is chosen per ACTIVITY, so running shoes can stay off walks.
 * Every on-foot type files under one of the two (`shoeActivitySql`).
 */
export const SHOE_ACTIVITIES = ["walking", "running"] as const;
export type ShoeActivity = (typeof SHOE_ACTIVITIES)[number];

export function isShoeActivity(value: unknown): value is ShoeActivity {
  return value === "walking" || value === "running";
}

/** 13:30/mi — the walk/run divide iOS draws `other` workouts with. */
const WALK_RUN_PACE_SECONDS = 810;

/**
 * Which default an on-foot workout takes: runs → running; walks and hikes →
 * walking; `other` (how Fitbit-via-Google-Health stamps walks) by pace, on
 * the same 13:30/mi line iOS uses to draw them as a walk or a run. Mirrored
 * by iOS `ShoeActivity.of(_:)`, which predicts it before the sync.
 */
export function shoeActivitySql(w: string): string {
  return `(CASE
    WHEN ${w}.workout_type = 'running' THEN 'running'
    WHEN ${w}.workout_type = 'other' AND ${w}.distance > 0
         AND ${w}.total_duration > 0
         AND ${w}.total_duration / ${w}.distance < ${WALK_RUN_PACE_SECONDS}
      THEN 'running'
    ELSE 'walking'
  END)`;
}

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
  /** Default for either activity — kept for builds that predate the split. */
  is_default: boolean;
  /** The activities this pair is the default for, e.g. ["running"]. */
  default_for: ShoeActivity[];
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
  /** Legacy: true = default for every activity, false = for none. */
  is_default?: boolean;
  /** The full set this pair should be the default for; wins over `is_default`. */
  default_for?: ShoeActivity[];
  retired?: boolean;
}

/** `default_for` if sent, else the legacy `is_default` as both/none. */
function requestedDefaults(input: ShoeInput): ShoeActivity[] | undefined {
  if (input.default_for !== undefined) return input.default_for;
  if (input.is_default === undefined) return undefined;
  return input.is_default ? [...SHOE_ACTIVITIES] : [];
}

// Mileage is derived at read, never stored: it has to follow every edit,
// delete and duplicate decision on the workouts underneath, and
// `countedWorkoutSql` is what keeps a Strava+Watch twin from counting twice.
const SHOE_SELECT = `
  SELECT s.shoe_id::text AS shoe_id, s.name, s.brand, s.colorway,
         s.image_url, s.starting_miles, s.replace_at_miles,
         cardinality(d.activities) > 0 AS is_default,
         d.activities AS default_for,
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
  CROSS JOIN LATERAL (
    SELECT COALESCE(array_agg(sd.activity ORDER BY sd.activity DESC), '{}')
             AS activities
    FROM shoe_defaults sd
    WHERE sd.shoe_id = s.shoe_id AND sd.user_id = s.user_id
  ) d
`;

export async function listShoes(userId: string): Promise<ShoeRow[]> {
  return db.query<ShoeRow>(
    `${SHOE_SELECT}
     WHERE s.user_id = $1
     ORDER BY (s.retired_at IS NOT NULL), cardinality(d.activities) DESC,
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

/**
 * Makes `shoeId` the default for exactly `activities`: takes it off any
 * activity not listed (leaving that activity with no default) and puts it on
 * each listed one, replacing whichever pair held it. An activity it already
 * held keeps its `since`, so re-saving never moves the stamping line.
 */
async function applyDefaultsFor(
  q: (sql: string, params?: any[]) => Promise<any[]>,
  userId: string,
  shoeId: string,
  activities: ShoeActivity[],
) {
  await q(
    `DELETE FROM shoe_defaults
     WHERE user_id = $1 AND shoe_id = $2::uuid AND NOT (activity = ANY($3::text[]))`,
    [userId, shoeId, activities],
  );
  if (!activities.length) return;
  await q(
    `INSERT INTO shoe_defaults (user_id, activity, shoe_id, since)
     SELECT $1::text, a.activity, $2::uuid, now()
     FROM unnest($3::text[]) AS a(activity)
     ON CONFLICT (user_id, activity) DO UPDATE
       SET shoe_id = EXCLUDED.shoe_id, since = EXCLUDED.since
       WHERE shoe_defaults.shoe_id <> EXCLUDED.shoe_id`,
    [userId, shoeId, activities],
  );
}

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
    const rows = await q(
      `INSERT INTO shoes (user_id, name, brand, colorway,
                          starting_miles, replace_at_miles)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING shoe_id::text AS shoe_id`,
      [
        userId,
        input.name,
        input.brand ?? null,
        input.colorway ?? null,
        input.starting_miles ?? 0,
        input.replace_at_miles ?? null,
      ],
    );
    const id = rows[0].shoe_id as string;
    const defaults = requestedDefaults(input);
    if (defaults?.length) await applyDefaultsFor(q, userId, id, defaults);
    return id;
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
      `SELECT retired_at FROM shoes
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

    // A retired pair can't be a default; retiring one leaves its activities
    // with none rather than silently promoting another pair.
    const retiring = patch.retired === true;
    if (patch.retired !== undefined) {
      sets.push(
        retiring
          ? `retired_at = COALESCE(retired_at, now())`
          : `retired_at = NULL`,
      );
    }
    const defaults = retiring ? [] : requestedDefaults(patch);
    if (defaults !== undefined) {
      await applyDefaultsFor(q, userId, shoeId, defaults);
      // Making a retired pair a default brings it back into rotation.
      if (defaults.length && patch.retired === undefined) {
        sets.push(`retired_at = NULL`);
      }
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
 *    sync) → the default for `activity`, `predicted`, which is exactly what
 *    the sync will stamp when it lands. A build that predates per-activity
 *    defaults sends no activity: it gets a prediction only when both
 *    activities share one pair, never a guess between two.
 */
export async function getWorkoutShoe(
  userId: string,
  workoutId: string,
  activity?: ShoeActivity,
): Promise<{ shoe_id: string | null; source: WorkoutShoeSource }> {
  const rows = await db.query<{
    assigned: boolean;
    shoe_id: string | null;
    assigned_by: "user" | "default" | null;
    synced: boolean;
    walking_id: string | null;
    running_id: string | null;
  }>(
    `SELECT
       ws.user_id IS NOT NULL AS assigned,
       ws.shoe_id::text AS shoe_id,
       ws.assigned_by,
       EXISTS (SELECT 1 FROM workouts w
               WHERE w.workout_id = $2::text AND w.user_id = $1::text) AS synced,
       (SELECT d.shoe_id::text FROM shoe_defaults d
        JOIN shoes s ON s.shoe_id = d.shoe_id AND s.retired_at IS NULL
        WHERE d.user_id = $1::text AND d.activity = 'walking') AS walking_id,
       (SELECT d.shoe_id::text FROM shoe_defaults d
        JOIN shoes s ON s.shoe_id = d.shoe_id AND s.retired_at IS NULL
        WHERE d.user_id = $1::text AND d.activity = 'running') AS running_id
     FROM (SELECT 1) one
     LEFT JOIN workout_shoes ws ON ws.user_id = $1::text AND ws.workout_id = $2::text`,
    [userId, workoutId],
  );
  const r = rows[0];
  if (r.assigned) return { shoe_id: r.shoe_id, source: r.assigned_by };
  if (r.synced) return { shoe_id: null, source: null };
  const predicted =
    activity === "walking"
      ? r.walking_id
      : activity === "running"
        ? r.running_id
        : r.walking_id === r.running_id
          ? r.walking_id
          : null;
  return predicted
    ? { shoe_id: predicted, source: "predicted" }
    : { shoe_id: null, source: null };
}

/**
 * Sets (or, with `shoeId` null, clears) the default for one activity.
 * Choosing a retired pair brings it back into rotation. Returns the pair
 * that LOST the activity, if any, with how many of that activity's workouts
 * it was given automatically — the app offers to take it off those, since a
 * pair you've just said isn't for walks is usually carrying walks it was
 * never worn on. Ownership of `shoeId` is checked by the caller.
 */
export async function setActivityDefault(
  userId: string,
  activity: ShoeActivity,
  shoeId: string | null,
): Promise<{ shoe_id: string; auto_assigned: number } | null> {
  const previousId = await inTransaction(async (q) => {
    const prev = await q(
      `SELECT shoe_id::text AS shoe_id FROM shoe_defaults
       WHERE user_id = $1 AND activity = $2 FOR UPDATE`,
      [userId, activity],
    );
    if (shoeId === null) {
      await q(`DELETE FROM shoe_defaults WHERE user_id = $1 AND activity = $2`, [
        userId,
        activity,
      ]);
    } else {
      await q(
        `UPDATE shoes SET retired_at = NULL, updated_at = now()
         WHERE user_id = $1 AND shoe_id = $2::uuid AND retired_at IS NOT NULL`,
        [userId, shoeId],
      );
      await q(
        `INSERT INTO shoe_defaults (user_id, activity, shoe_id, since)
         VALUES ($1, $2, $3::uuid, now())
         ON CONFLICT (user_id, activity) DO UPDATE
           SET shoe_id = EXCLUDED.shoe_id, since = EXCLUDED.since
           WHERE shoe_defaults.shoe_id <> EXCLUDED.shoe_id`,
        [userId, activity, shoeId],
      );
    }
    const before = (prev[0]?.shoe_id as string | undefined) ?? null;
    return before !== shoeId ? before : null;
  });
  if (!previousId) return null;
  const rows = await db.query<{ n: number }>(
    `SELECT COUNT(*)::int AS n
     FROM workout_shoes ws
     JOIN workouts w ON w.workout_id = ws.workout_id AND w.user_id = ws.user_id
     WHERE ws.user_id = $1 AND ws.shoe_id = $2::uuid AND ws.assigned_by = 'default'
       AND ${countedWorkoutSql("w")}
       AND ${shoeActivitySql("w")} = $3`,
    [userId, previousId, activity],
  );
  return { shoe_id: previousId, auto_assigned: rows[0]?.n ?? 0 };
}

/**
 * Takes the pair off every `activity` workout the sync stamped it onto,
 * leaving each an explicit "no shoe" (so nothing re-stamps it). Picks the
 * user made themselves are never touched. Returns how many changed.
 */
export async function clearAutoAssigned(
  userId: string,
  shoeId: string,
  activity: ShoeActivity,
): Promise<number> {
  const rows = await db.query(
    `UPDATE workout_shoes ws
     SET shoe_id = NULL, assigned_by = 'user', assigned_at = now()
     FROM workouts w
     WHERE ws.user_id = $1 AND ws.shoe_id = $2::uuid AND ws.assigned_by = 'default'
       AND w.workout_id = ws.workout_id AND w.user_id = ws.user_id
       AND ${shoeActivitySql("w")} = $3
     RETURNING ws.workout_id`,
    [userId, shoeId, activity],
  );
  return rows.length;
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
 * Spliced into the workout upload transaction AFTER the upsert: stamps each
 * on-foot workout in this batch with the default for ITS activity
 * (`shoeActivitySql`), when it ended after that pair BECAME the default for
 * that activity and carries no assignment yet. No default for an activity
 * (the user chose "none") stamps nothing.
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
      SELECT $1::text, w.workout_id, d.shoe_id, 'default'
      FROM workouts w
      JOIN shoe_defaults d
        ON d.user_id = w.user_id AND d.activity = ${shoeActivitySql("w")}
      JOIN shoes s
        ON s.shoe_id = d.shoe_id AND s.user_id = d.user_id AND s.retired_at IS NULL
      WHERE w.user_id = $1::text
        AND w.workout_id = ANY($2::text[])
        AND w.deleted_at IS NULL
        AND w.workout_type = ANY($3::text[])
        AND w.device_end_date >= d.since
      ON CONFLICT (user_id, workout_id) DO NOTHING`,
    params: [userId, workoutIds, SHOE_FOOT_TYPES],
  };
}
