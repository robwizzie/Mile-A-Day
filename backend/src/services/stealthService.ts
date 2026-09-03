import { PostgresService } from "./DbService.js";

/**
 * Stealth Mode — "friends never see WHERE this walk was".
 *
 * Two pieces, and the server is the authority for both:
 *   1. `stealth_windows` — the intervals a user asked for. Kept forever (a
 *      toggle-off CLOSES a window, it never deletes one) so a Watch/Strava walk
 *      that syncs days later is still classified. `ended_at` NULL = open; a
 *      FUTURE ended_at is "stealth until <date>"; a backdated started_at is
 *      "also hide routes since…".
 *   2. `workouts.stealth` — a per-workout STICKY stamp, set at sync when the
 *      workout's [start, end] overlaps any window (or the client asserted it).
 *      It only ever goes false→true: a walk recorded in stealth stays hidden
 *      after the mode is turned off, which is the whole point.
 *
 * INVARIANT: a stealth workout has NO `workout_routes` row. Enforced at write
 * (workoutService's conditional route insert + the cleanup statement below +
 * the retroactive paths here), never re-checked at read — every route-serving
 * surface is clean by construction because the row does not exist. The flag
 * itself is served to the OWNER only: to a friend a stealth walk must be
 * indistinguishable from share_route_maps=off.
 *
 * The workouts table has no start timestamp (`date` is a calendar date), so a
 * workout's start is derived as device_end_date - total_duration. That
 * duration is pause-excluded, so the derived start lands slightly LATE on a
 * paused walk — fine at window granularity, and it errs toward hiding.
 */

const db = PostgresService.getInstance();

/** How far back "also hide routes since…" may reach. */
export const MAX_BACKDATE_DAYS = 30;
/** How far ahead "stealth until <date>" may be set. */
export const MAX_UNTIL_DAYS = 90;
const WINDOW_LIST_LIMIT = 50;

export interface StealthWindowRow {
  started_at: string; // ISO
  ended_at: string | null; // ISO, null = open-ended
}

export interface StealthStatus {
  stealth_mode: boolean;
  stealth_until: string | null;
  stealth_windows: StealthWindowRow[];
}

/**
 * SQL: does ANY of this user's windows overlap the workout whose end is
 * `endParam` (timestamptz) and whose elapsed seconds are `durationParam`?
 * Overlap, not containment: a walk that straddles the moment stealth was
 * switched on (or off) is hidden — the conservative reading.
 */
export function stealthOverlapSql(
  userParam: string,
  endParam: string,
  durationParam: string,
): string {
  return `EXISTS (
		SELECT 1 FROM stealth_windows sw
		-- ::varchar keeps the param's deduced type equal to workouts.user_id's
		-- (the INSERT column that also binds it) — Postgres refuses a param
		-- deduced text here and varchar there.
		WHERE sw.user_id = ${userParam}::varchar
			AND sw.started_at <= ${endParam}::timestamptz
			AND (
				sw.ended_at IS NULL
				OR sw.ended_at >= ${endParam}::timestamptz
					- make_interval(secs => ${durationParam}::double precision)
			)
	)`;
}

/**
 * Transaction statement for uploadWorkouts: drop the stored route of any
 * workout in this batch that is (now) stealth. Covers a route that landed
 * BEFORE the workout became stealth — a backdated window, or an older client
 * re-pushing a trace the conditional insert already refused to update.
 */
export function stealthRouteCleanupStatement(
  userId: string,
  workoutIds: string[],
): { query: string; params: any[] } {
  return {
    query: `DELETE FROM workout_routes r USING workouts w
			WHERE r.workout_id = w.workout_id
				AND w.user_id = $1
				AND w.workout_id = ANY($2::text[])
				AND w.stealth`,
    params: [userId, workoutIds],
  };
}

// node-pg hands timestamptz back as a JS Date (only `date` columns are
// strings) — never string-op these; serialise explicitly.
function toIso(value: unknown): string | null {
  if (value == null) return null;
  if (value instanceof Date) return value.toISOString();
  const parsed = new Date(String(value));
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
}

const OPEN_WINDOW_WHERE = `user_id = $1
	AND started_at <= NOW()
	AND (ended_at IS NULL OR ended_at > NOW())`;

export async function isStealthNow(userId: string): Promise<boolean> {
  const rows = await db.query<{ ok: boolean }>(
    `SELECT EXISTS (SELECT 1 FROM stealth_windows WHERE ${OPEN_WINDOW_WHERE}) AS ok`,
    [userId],
  );
  return rows[0]?.ok === true;
}

export async function listWindows(
  userId: string,
  limit: number = WINDOW_LIST_LIMIT,
): Promise<StealthWindowRow[]> {
  const rows = await db.query<{ started_at: unknown; ended_at: unknown }>(
    `SELECT started_at, ended_at FROM stealth_windows
		 WHERE user_id = $1
		 ORDER BY started_at DESC
		 LIMIT $2`,
    [userId, limit],
  );
  return rows.map((r) => ({
    started_at: toIso(r.started_at) ?? new Date(0).toISOString(),
    ended_at: toIso(r.ended_at),
  }));
}

/** What the preferences payload carries — derived from the windows, one query. */
export async function stealthStatus(userId: string): Promise<StealthStatus> {
  const windows = await listWindows(userId);
  const now = Date.now();
  const open = windows.find(
    (w) =>
      Date.parse(w.started_at) <= now &&
      (w.ended_at === null || Date.parse(w.ended_at) > now),
  );
  return {
    stealth_mode: open !== undefined,
    stealth_until: open?.ended_at ?? null,
    stealth_windows: windows,
  };
}

/**
 * Turn stealth ON (or adjust the open window). `since` backdates the start
 * (never moves it later), `until` sets/clears the end only when
 * `untilProvided` — an enable that doesn't mention "until" leaves a trip-mode
 * end date alone. Always re-applies the stamp to existing workouts: idempotent,
 * bounded by the user's own rows, and it's what catches a Watch walk that
 * ended a minute before the toggle.
 */
export async function openWindow(
  userId: string,
  opts: {
    since?: Date | null;
    until?: Date | null;
    untilProvided?: boolean;
  } = {},
): Promise<StealthWindowRow> {
  const since = opts.since ? opts.since.toISOString() : null;
  const until = opts.until ? opts.until.toISOString() : null;
  const untilProvided = opts.untilProvided === true;

  const open = await db.query<{ id: number }>(
    `SELECT id FROM stealth_windows WHERE ${OPEN_WINDOW_WHERE}
		 ORDER BY started_at DESC LIMIT 1`,
    [userId],
  );

  let row: { started_at: unknown; ended_at: unknown };
  if (open.length > 0) {
    const updated = await db.query<{ started_at: unknown; ended_at: unknown }>(
      `UPDATE stealth_windows
			 SET started_at = LEAST(started_at, COALESCE($2::timestamptz, started_at)),
				 ended_at = CASE WHEN $4::boolean THEN $3::timestamptz ELSE ended_at END
			 WHERE id = $1
			 RETURNING started_at, ended_at`,
      [open[0].id, since, until, untilProvided],
    );
    row = updated[0];
  } else {
    const inserted = await db.query<{ started_at: unknown; ended_at: unknown }>(
      `INSERT INTO stealth_windows (user_id, started_at, ended_at)
			 VALUES ($1, COALESCE($2::timestamptz, NOW()), $3::timestamptz)
			 RETURNING started_at, ended_at`,
      [userId, since, until],
    );
    row = inserted[0];
  }

  const startedAt = toIso(row.started_at)!;
  const endedAt = toIso(row.ended_at);
  await applyStealthToExistingWorkouts(userId, startedAt, endedAt);
  return { started_at: startedAt, ended_at: endedAt };
}

/** Turn stealth OFF: closes the open window (kept for history). */
export async function closeWindow(userId: string): Promise<void> {
  await db.query(
    `UPDATE stealth_windows SET ended_at = NOW() WHERE ${OPEN_WINDOW_WHERE}`,
    [userId],
  );
}

/**
 * Stamp every already-synced workout that overlaps [startedAt, endedAt] and
 * delete its route, in ONE transaction. Bounded to the user's own rows.
 */
export async function applyStealthToExistingWorkouts(
  userId: string,
  startedAt: string,
  endedAt: string | null,
): Promise<void> {
  await db.transaction([
    {
      query: `UPDATE workouts w SET stealth = true
				WHERE w.user_id = $1
					AND COALESCE(w.stealth, false) = false
					AND w.device_end_date >= $2::timestamptz
					AND (
						$3::timestamptz IS NULL
						OR w.device_end_date - make_interval(secs => w.total_duration) <= $3::timestamptz
					)`,
      params: [userId, startedAt, endedAt],
    },
    {
      query: `DELETE FROM workout_routes r USING workouts w
				WHERE r.workout_id = w.workout_id AND w.user_id = $1 AND w.stealth`,
      params: [userId],
    },
  ]);
}

/**
 * Retroactive stealth for ONE workout the user owns: stamp + delete the route.
 * Returns false when the workout isn't theirs (the controller answers 404).
 * `db.transaction` returns nothing, hence the ownership pre-check.
 */
export async function hideWorkoutRoute(
  userId: string,
  workoutId: string,
): Promise<boolean> {
  const owned = await db.query(
    `SELECT 1 FROM workouts WHERE workout_id = $2 AND user_id = $1`,
    [userId, workoutId],
  );
  if (owned.length === 0) return false;
  await db.transaction([
    {
      query: `UPDATE workouts SET stealth = true WHERE workout_id = $2 AND user_id = $1`,
      params: [userId, workoutId],
    },
    {
      query: `DELETE FROM workout_routes r USING workouts w
				WHERE r.workout_id = w.workout_id AND w.workout_id = $2 AND w.user_id = $1`,
      params: [userId, workoutId],
    },
  ]);
  return true;
}
