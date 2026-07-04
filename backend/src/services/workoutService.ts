import { Workout } from "../types/workouts.js";
import { PostgresService } from "./DbService.js";

const db = PostgresService.getInstance();

export async function uploadWorkouts(
  userId: string,
  workouts: Workout[],
): Promise<string[]> {
  // Ownership guard: workout ids are visible to friends in feed payloads, so a
  // crafted upload could otherwise ON CONFLICT into ANOTHER user's row (and its
  // splits/route) and corrupt their data. Drop any id already owned by someone
  // else before building the transaction; the DO UPDATE below is additionally
  // guarded as a race backstop.
  if (workouts.length > 0) {
    const foreign = await db.query<{ workout_id: string }>(
      `SELECT workout_id FROM workouts
			WHERE workout_id = ANY($1::text[]) AND user_id <> $2`,
      [workouts.map((w) => w.workoutId), userId],
    );
    if (foreign.length > 0) {
      const foreignIds = new Set(foreign.map((r) => r.workout_id));
      console.warn(
        `[uploadWorkouts] Dropping ${foreign.length} workout(s) owned by another user (uploader ${userId})`,
      );
      workouts = workouts.filter((w) => !foreignIds.has(w.workoutId));
      if (workouts.length === 0) return [];
    }
  }

  const workoutQuery = `
      INSERT INTO workouts (
        user_id,
        workout_id,
        distance,
        local_date,
        date,
        timezone_offset,
        workout_type,
        device_end_date,
        calories,
        total_duration,
        source,
        exclusion_reason,
        speed_flagged
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
      ON CONFLICT (workout_id)
      DO UPDATE SET
        distance = EXCLUDED.distance,
        local_date = EXCLUDED.local_date,
        date = EXCLUDED.date,
        timezone_offset = EXCLUDED.timezone_offset,
        workout_type = EXCLUDED.workout_type,
        device_end_date = EXCLUDED.device_end_date,
        calories = EXCLUDED.calories,
        total_duration = EXCLUDED.total_duration,
        source = CASE
          WHEN workouts.source IN ('manual', 'edited') THEN workouts.source
          ELSE EXCLUDED.source
        END,
        -- Recompute the speed classification from the latest figures, but never
        -- clear a user soft-delete (deleted_at is intentionally not updated here).
        exclusion_reason = EXCLUDED.exclusion_reason,
        speed_flagged = EXCLUDED.speed_flagged
      WHERE workouts.user_id = $1
      RETURNING workout_id, (xmax = 0) AS inserted
    `;

  const splitQuery = `
        INSERT INTO workout_splits (workout_id, split_number, split_duration, split_distance, split_pace)
        VALUES ($1, $2, $3, $4, $5)
        ON CONFLICT (workout_id, split_number)
        DO UPDATE SET
			split_duration = EXCLUDED.split_duration,
			split_distance = EXCLUDED.split_distance,
			split_pace = EXCLUDED.split_pace
      `;

  const routeQuery = `
        INSERT INTO workout_routes (workout_id, route, point_count, updated_at)
        VALUES ($1, $2::jsonb, $3, NOW())
        ON CONFLICT (workout_id)
        DO UPDATE SET
			route = EXCLUDED.route,
			point_count = EXCLUDED.point_count,
			updated_at = NOW()
      `;

  await db.transaction(
    workouts.flatMap((workout: Workout) => {
      const speed = classifyWorkoutSpeed(
        workout.distance,
        workout.totalDuration,
      );
      const route = sanitizeRoute(workout.route);
      return [
        {
          query: workoutQuery,
          params: [
            userId,
            workout.workoutId,
            workout.distance,
            workout.localDate,
            workout.date,
            workout.timezoneOffset,
            workout.workoutType,
            workout.deviceEndDate,
            workout.calories,
            workout.totalDuration,
            workout.source || "healthkit",
            speed.exclusionReason,
            speed.speedFlagged,
          ],
        },
        ...workout.splits.map((split) => ({
          query: splitQuery,
          params: [
            workout.workoutId,
            split.splitNumber,
            split.duration,
            split.distance,
            split.pace,
          ],
        })),
        ...(route
          ? [
              {
                query: routeQuery,
                params: [
                  workout.workoutId,
                  JSON.stringify(route),
                  route.length,
                ],
              },
            ]
          : []),
      ];
    }),
  );

  return workouts.map((w) => w.workoutId);
}

// A trace only needs enough fidelity to draw a small map; clients downsample
// before upload and this is the server-side backstop.
const MAX_ROUTE_POINTS = 300;

/**
 * Validate + normalize an uploaded GPS trace. Returns null (skip storage) for
 * anything that isn't a plausible [[lat, lng], ...] polyline with >= 2 points.
 * Coordinates are rounded to 5 decimals (~1m) and long traces are downsampled.
 */
function sanitizeRoute(route: unknown): [number, number][] | null {
  if (!Array.isArray(route) || route.length < 2) return null;
  const points: [number, number][] = [];
  for (const p of route) {
    if (!Array.isArray(p) || p.length < 2) return null;
    const lat = Number(p[0]);
    const lng = Number(p[1]);
    if (
      !Number.isFinite(lat) ||
      !Number.isFinite(lng) ||
      Math.abs(lat) > 90 ||
      Math.abs(lng) > 180
    ) {
      return null;
    }
    points.push([
      Math.round(lat * 100000) / 100000,
      Math.round(lng * 100000) / 100000,
    ]);
  }
  if (points.length <= MAX_ROUTE_POINTS) return points;
  const stride = (points.length - 1) / (MAX_ROUTE_POINTS - 1);
  const sampled: [number, number][] = [];
  for (let i = 0; i < MAX_ROUTE_POINTS; i++) {
    sampled.push(points[Math.round(i * stride)]);
  }
  return sampled;
}

/**
 * Classify a workout by its average speed to catch "left tracking on in the car".
 * A human can't run/walk a mile faster than ~15 mph (the mile world record), and
 * only running/walking workouts ever reach us, so:
 *   - >= 20 mph  → physically impossible on foot → auto-exclude (does NOT count).
 *                  Conservative on purpose: zero risk of rejecting a real run.
 *   - 13–20 mph  → suspicious but theoretically human → flag for the user to
 *                  review/delete; still counts.
 * Guards against missing/zero data (returns "not flagged").
 */
const VEHICLE_EXCLUDE_MPH = 20;
const VEHICLE_FLAG_MPH = 13;

function classifyWorkoutSpeed(
  distance: number | null | undefined,
  totalDuration: number | null | undefined,
): { exclusionReason: string | null; speedFlagged: boolean } {
  const d = Number(distance);
  const secs = Number(totalDuration);
  if (!isFinite(d) || !isFinite(secs) || d <= 0 || secs <= 0) {
    return { exclusionReason: null, speedFlagged: false };
  }
  const mph = (d * 3600) / secs;
  if (mph >= VEHICLE_EXCLUDE_MPH) {
    return { exclusionReason: "vehicle_speed", speedFlagged: true };
  }
  if (mph >= VEHICLE_FLAG_MPH) {
    return { exclusionReason: null, speedFlagged: true };
  }
  return { exclusionReason: null, speedFlagged: false };
}

function dateStringMinus(dateStr: string, days: number): string {
  const [y, m, d] = dateStr.split("-").map(Number);
  const date = new Date(Date.UTC(y, m - 1, d));
  date.setUTCDate(date.getUTCDate() - days);
  return date.toISOString().slice(0, 10);
}

/**
 * Today's date (YYYY-MM-DD) in the user's local timezone, derived from the
 * timezone_offset of their most recent workout (UTC if they have none).
 */
export async function getUserLocalToday(userId: string): Promise<string> {
  const todayResult = await db.query<{ user_today: string }>(
    `
    SELECT to_char(
      (NOW() + (COALESCE(
        (SELECT timezone_offset FROM workouts WHERE user_id = $1 ORDER BY device_end_date DESC LIMIT 1),
        0
      ) || ' minutes')::interval)::date,
      'YYYY-MM-DD'
    ) AS user_today
  `,
    [userId],
  );
  return todayResult[0].user_today;
}

export async function getActiveStreak(userId: string) {
  const userToday = await getUserLocalToday(userId);
  const yesterday = dateStringMinus(userToday, 1);

  const qualifyingDaysQuery = `
    SELECT to_char(local_date, 'YYYY-MM-DD') AS local_date
    FROM workouts
    WHERE user_id = $1
    AND deleted_at IS NULL AND exclusion_reason IS NULL
    GROUP BY local_date
    HAVING SUM(distance) >= 0.95
    ORDER BY local_date DESC
    LIMIT $2 OFFSET $3
  `;

  const LIMIT = 100;
  let index = 0;
  let streak = 0;
  let streakStartDay: string | undefined;
  let expectedDate: string | undefined;

  while (true) {
    const results = await db.query(qualifyingDaysQuery, [
      userId,
      LIMIT,
      index * LIMIT,
    ]);
    if (results.length === 0) break;

    for (const row of results) {
      const date: string = row.local_date;

      if (expectedDate === undefined) {
        if (date !== userToday && date !== yesterday) {
          return { streak: 0, start: undefined };
        }
        streak = 1;
        streakStartDay = date;
        expectedDate = dateStringMinus(date, 1);
      } else if (date === expectedDate) {
        streak++;
        streakStartDay = date;
        expectedDate = dateStringMinus(date, 1);
      } else {
        return { streak, start: streakStartDay };
      }
    }

    index++;
  }

  return { streak, start: streakStartDay };
}

export async function getTotalMiles(userId: string, startDate?: string) {
  let distanceQuery = `
    SELECT SUM(distance) FROM workouts
    WHERE user_id = $1
    AND deleted_at IS NULL AND exclusion_reason IS NULL
    `;

  const params: (string | number)[] = [userId];

  if (startDate) {
    distanceQuery += ` AND local_date >= $2`;
    params.push(startDate);
  }

  return (await db.query(distanceQuery, params))[0]?.sum;
}

export async function getBestMilesDay(userId: string, startDate?: string) {
  let bestDayQuery = `
    SELECT local_date, SUM(distance) as total_distance FROM workouts
    WHERE user_id = $1
    AND deleted_at IS NULL AND exclusion_reason IS NULL
    `;

  const params: (string | number)[] = [userId];

  if (startDate) {
    bestDayQuery += ` AND local_date >= $2`;
    params.push(startDate);
  }

  bestDayQuery += `
    GROUP BY local_date
    ORDER BY total_distance DESC
    LIMIT 1
    `;

  return (await db.query(bestDayQuery, params))[0];
}

export async function getBestSplit(userId: string, startDate?: string) {
  let bestSplitQuery = `
    SELECT 
      ws.split_pace AS best_split_time,
      w.*
    FROM workout_splits ws
    JOIN workouts w ON ws.workout_id = w.workout_id
    WHERE w.user_id = $1
	AND split_distance >= 0.95
	AND ws.split_pace > 0
	`;

  const params: (string | number)[] = [userId];

  if (startDate) {
    bestSplitQuery += ` AND w.local_date >= $2`;
    params.push(startDate);
  }

  bestSplitQuery += `
    ORDER BY ws.split_pace ASC
    LIMIT 1
	`;

  const result = await db.query(bestSplitQuery, params);

  if (!result || result.length === 0) {
    return null;
  }

  const { best_split_time, ...workout } = result[0];

  return { best_split_time, workout };
}

export async function getRecentWorkouts(
  userId: string,
  limit: number | null = 10,
) {
  const recentWorkoutsQuery = `
	SELECT * FROM workouts
	WHERE user_id = $1
	AND deleted_at IS NULL
	ORDER BY device_end_date DESC
	LIMIT $2
	`;

  return await db.query(recentWorkoutsQuery, [userId, limit]);
}

/**
 * Every stored GPS route for a user's live workouts, newest first — powers the
 * personal route heatmap (all paths overlaid on one map). Self-access only:
 * route sharing settings gate what FRIENDS see, but your own history is
 * always yours. Capped because routes are ~300 points each; 1000 routes
 * (~3 years of daily runs) is already several MB of JSON.
 */
export async function getUserRoutes(userId: string, limit: number = 1000) {
  return await db.query<{
    workout_id: string;
    local_date: string;
    workout_type: string;
    route: unknown;
  }>(
    `SELECT w.workout_id, w.local_date, w.workout_type, wr.route
		 FROM workout_routes wr
		 JOIN workouts w ON w.workout_id = wr.workout_id
		 WHERE w.user_id = $1 AND w.deleted_at IS NULL
		 ORDER BY w.device_end_date DESC
		 LIMIT $2`,
    [userId, limit],
  );
}

/**
 * Today's date ('YYYY-MM-DD') in the user's local timezone, derived from their
 * most recent workout's timezone_offset (matches workouts.local_date format).
 * Falls back to the server's UTC date if the user has no workouts.
 */
export async function getUserLocalDate(userId: string): Promise<string> {
  const rows = await db.query<{ local_date: string }>(
    `SELECT (NOW() + (COALESCE(
			(SELECT timezone_offset FROM workouts WHERE user_id = $1 ORDER BY device_end_date DESC LIMIT 1),
			0
		) || ' minutes')::interval)::date::text AS local_date`,
    [userId],
  );
  return rows[0].local_date;
}

export async function getTodayMiles(userId: string) {
  // Use the user's timezone offset from their most recent workout to determine
  // what "today" is in their local time (local_date is stored in user's timezone)
  const todayMilesQuery = `
	WITH user_tz AS (
		SELECT COALESCE(
			(SELECT timezone_offset FROM workouts WHERE user_id = $1 ORDER BY device_end_date DESC LIMIT 1),
			0
		) AS tz_offset
	)
	SELECT SUM(w.distance) as total_distance FROM workouts w, user_tz
	WHERE w.user_id = $1
	AND w.local_date = (NOW() + (user_tz.tz_offset || ' minutes')::interval)::date
	AND w.deleted_at IS NULL AND w.exclusion_reason IS NULL
	`;

  const result = await db.query(todayMilesQuery, [userId]);
  return result[0]?.total_distance || 0;
}

/**
 * Total miles a user logged on a specific local date (their timezone).
 * Used to validate "did they complete their mile that day?" for historical
 * events like an old mile-completion notification being hyped.
 */
export async function getMilesOnLocalDate(
  userId: string,
  localDate: string,
): Promise<number> {
  const result = await db.query<{ total_distance: string | number | null }>(
    `SELECT COALESCE(SUM(distance), 0) AS total_distance
		FROM workouts
		WHERE user_id = $1 AND local_date = $2::date AND deleted_at IS NULL AND exclusion_reason IS NULL`,
    [userId, localDate],
  );
  const value = result[0]?.total_distance;
  return value == null ? 0 : Number(value);
}

export interface DailyGoalStatus {
  completed: boolean;
  miles: number;
  goalMiles: number;
  localDate: string;
}

/**
 * Whether the user has met their personal daily goal (goal_miles) today, in
 * their local timezone. This is the authoritative server-side gate for posting
 * a story/feed post — never trust a client-supplied "completed" flag.
 */
export async function getDailyGoalStatus(
  userId: string,
): Promise<DailyGoalStatus> {
  const localDate = await getUserLocalDate(userId);
  const [miles, goalRows] = await Promise.all([
    getMilesOnLocalDate(userId, localDate),
    db.query<{ goal_miles: string | number | null }>(
      `SELECT goal_miles FROM users WHERE user_id = $1`,
      [userId],
    ),
  ]);
  const goalMiles = Number(goalRows[0]?.goal_miles ?? 1);
  // Small epsilon so a goal stored as 1.0 isn't missed by 1.0 reading 0.9999.
  const completed = miles + 1e-9 >= goalMiles;
  return { completed, miles, goalMiles, localDate };
}

export interface TodayStats {
  miles: number;
  durationSeconds: number;
  bestSplitPaceSecMi: number | null;
}

/**
 * Aggregate today's workout stats for a user, using the user's local-date
 * predicate (same as getTodayMiles).
 *
 * bestSplitPaceSecMi: MIN split pace (sec/mi) across today's splits where
 * split_distance >= 0.95. Falls back to MIN(total_duration / distance) over
 * today's workouts with distance >= 0.95. NULL if neither is available.
 */
export async function getTodayStats(userId: string): Promise<TodayStats> {
  const query = `
	WITH user_tz AS (
		SELECT COALESCE(
			(SELECT timezone_offset FROM workouts WHERE user_id = $1 ORDER BY device_end_date DESC LIMIT 1),
			0
		) AS tz_offset
	),
	today_workouts AS (
		SELECT w.workout_id, w.distance, w.total_duration
		FROM workouts w, user_tz
		WHERE w.user_id = $1
			AND w.local_date = (NOW() + (user_tz.tz_offset || ' minutes')::interval)::date
			AND w.deleted_at IS NULL AND w.exclusion_reason IS NULL
	),
	totals AS (
		SELECT
			COALESCE(SUM(distance), 0) AS miles,
			COALESCE(SUM(total_duration), 0) AS duration_seconds
		FROM today_workouts
	),
	split_best AS (
		SELECT MIN(ws.split_pace) AS pace
		FROM today_workouts tw
		JOIN workout_splits ws ON ws.workout_id = tw.workout_id
		WHERE ws.split_distance >= 0.95 AND ws.split_pace > 0
	),
	workout_best AS (
		SELECT MIN(total_duration / NULLIF(distance, 0)) AS pace
		FROM today_workouts
		WHERE distance >= 0.95
	)
	SELECT
		t.miles::float8 AS miles,
		t.duration_seconds::float8 AS duration_seconds,
		COALESCE(sb.pace, wb.pace) AS best_split_pace_sec_mi
	FROM totals t
	LEFT JOIN split_best sb ON TRUE
	LEFT JOIN workout_best wb ON TRUE
	`;

  const rows = await db.query<{
    miles: number | string;
    duration_seconds: number | string;
    best_split_pace_sec_mi: number | string | null;
  }>(query, [userId]);

  const row = rows[0];
  const toNum = (v: number | string | null | undefined): number =>
    v == null ? 0 : typeof v === "string" ? Number(v) : v;
  const pace = row?.best_split_pace_sec_mi;

  return {
    miles: toNum(row?.miles),
    durationSeconds: toNum(row?.duration_seconds),
    bestSplitPaceSecMi: pace == null ? null : Number(pace),
  };
}

// Shared normalization for the date-range aggregation queries below: clamp the
// range to calendar dates (default end = today) and map competition activity
// aliases (run/walk) onto stored workout_type values. ONE definition so the
// scoring sum, the per-type breakdown, and the single-user variant can never
// disagree on what counts.
function normalizeDateRange(
  startDate: string,
  endDate?: string,
): { start: string; end: string } {
  const todaysDate = new Date().toISOString().split("T")[0];
  return {
    start: new Date(startDate).toISOString().split("T")[0],
    end: endDate ? new Date(endDate).toISOString().split("T")[0] : todaysDate,
  };
}

function normalizeWorkoutTypes(
  workoutTypes?: ("running" | "walking")[],
): string[] {
  const typeMap: Record<string, "running" | "walking"> = {
    run: "running",
    walk: "walking",
    running: "running",
    walking: "walking",
  };
  return (workoutTypes ?? ["running", "walking"])
    .map((t) => typeMap[t])
    .filter(Boolean);
}

export async function getQuantityDateRange(
  userId: string,
  startDate: string,
  endDate?: string,
  workoutTypes?: ("running" | "walking")[],
) {
  let query = `
		SELECT
			TO_CHAR(local_date, 'YYYY-MM-DD') as local_date,
			SUM(distance) as total_distance
		FROM workouts
		WHERE user_id = $1
			AND local_date >= $2
			AND local_date <= $3
			AND workout_type = ANY($4::text[])
			AND deleted_at IS NULL AND exclusion_reason IS NULL
		GROUP BY local_date
		ORDER BY local_date ASC
	`;

  const { start, end } = normalizeDateRange(startDate, endDate);
  const normalizedTypes = normalizeWorkoutTypes(workoutTypes);

  return await db.query(query, [userId, start, end, normalizedTypes]);
}

/**
 * Batched variant of getQuantityDateRange — returns one row per (user_id, local_date)
 * for an entire set of users in a single query. Used by competitionService to score
 * all participants at once instead of looping per user.
 */
export async function getQuantityDateRangeBatch(
  userIds: string[],
  startDate: string,
  endDate?: string,
  workoutTypes?: ("running" | "walking")[],
): Promise<{ user_id: string; local_date: string; total_distance: number }[]> {
  if (userIds.length === 0) return [];

  const query = `
		SELECT
			user_id,
			TO_CHAR(local_date, 'YYYY-MM-DD') as local_date,
			SUM(distance) as total_distance
		FROM workouts
		WHERE user_id = ANY($1::text[])
			AND local_date >= $2
			AND local_date <= $3
			AND workout_type = ANY($4::text[])
			AND deleted_at IS NULL AND exclusion_reason IS NULL
		GROUP BY user_id, local_date
		ORDER BY user_id, local_date ASC
	`;

  const { start, end } = normalizeDateRange(startDate, endDate);
  const normalizedTypes = normalizeWorkoutTypes(workoutTypes);

  return await db.query(query, [userIds, start, end, normalizedTypes]);
}

/**
 * Per-day, per-workout-type distance + workout counts for a set of users —
 * powers the competition detail view's walk/run breakdown (stats panel,
 * calendar day detail). Same filters as getQuantityDateRangeBatch, but keeps
 * workout_type instead of collapsing it.
 */
export async function getActivityBreakdownBatch(
  userIds: string[],
  startDate: string,
  endDate?: string,
  workoutTypes?: ("running" | "walking")[],
): Promise<
  {
    user_id: string;
    local_date: string;
    workout_type: string;
    total_distance: number;
    workout_count: number;
  }[]
> {
  if (userIds.length === 0) return [];

  const query = `
		SELECT
			user_id,
			TO_CHAR(local_date, 'YYYY-MM-DD') as local_date,
			workout_type,
			SUM(distance) as total_distance,
			COUNT(*)::int as workout_count
		FROM workouts
		WHERE user_id = ANY($1::text[])
			AND local_date >= $2
			AND local_date <= $3
			AND workout_type = ANY($4::text[])
			AND deleted_at IS NULL AND exclusion_reason IS NULL
		GROUP BY user_id, local_date, workout_type
		ORDER BY user_id, local_date ASC
	`;

  const { start, end } = normalizeDateRange(startDate, endDate);
  const normalizedTypes = normalizeWorkoutTypes(workoutTypes);

  return await db.query(query, [userIds, start, end, normalizedTypes]);
}

/**
 * Batched manual-workout check for a set of users over a date range.
 * Returns the set of user_ids that have at least one manual/edited workout in range.
 */
export async function getUsersWithManualWorkouts(
  userIds: string[],
  startDate: string,
  endDate: string,
): Promise<Set<string>> {
  if (userIds.length === 0) return new Set();

  const result = await db.query<{ user_id: string }>(
    `SELECT DISTINCT user_id FROM workouts
		 WHERE user_id = ANY($1::text[])
			AND local_date >= $2
			AND local_date <= $3
			AND source IN ('manual', 'edited')
			AND deleted_at IS NULL AND exclusion_reason IS NULL`,
    [userIds, startDate, endDate],
  );

  return new Set(result.map((r) => r.user_id));
}

export async function updateWorkout(
  userId: string,
  workoutId: string,
  updates: { distance?: number; totalDuration?: number; workoutType?: string },
) {
  const current = await db.query(
    "SELECT distance, total_duration, original_distance FROM workouts WHERE workout_id = $1 AND user_id = $2",
    [workoutId, userId],
  );

  if (!current || current.length === 0) {
    return null;
  }

  const row = current[0];

  const result = await db.query(
    `UPDATE workouts SET
			distance = COALESCE($3, distance),
			total_duration = COALESCE($4, total_duration),
			workout_type = COALESCE($5, workout_type),
			source = 'edited',
			original_distance = COALESCE(original_distance, $6),
			original_duration = COALESCE(original_duration, $7)
		WHERE workout_id = $1 AND user_id = $2
		RETURNING *`,
    [
      workoutId,
      userId,
      updates.distance ?? null,
      updates.totalDuration ?? null,
      updates.workoutType ?? null,
      row.distance,
      row.total_duration,
    ],
  );

  return result[0];
}

/**
 * Returns the user's two tracked personal records computed from workouts,
 * optionally excluding a set of workout IDs (used to compute the "pre-upload"
 * baseline so the caller can detect a PR set by this upload).
 *
 * - fastestSplitPaceSecMi: MIN(split_pace) across qualifying splits (>=0.95mi, >0 pace).
 *   0 if the user has no qualifying splits.
 * - mostMilesInOneDay: MAX(SUM(distance) GROUP BY local_date). 0 if no workouts.
 * - fastestSplitDate / bestDayDate: local_date (YYYY-MM-DD) that set each record,
 *   null when there is no record. Ties resolve to the most recent date.
 */
export async function computePersonalRecords(
  userId: string,
  excludeWorkoutIds: string[] = [],
): Promise<{
  fastestSplitPaceSecMi: number;
  mostMilesInOneDay: number;
  fastestSplitDate: string | null;
  bestDayDate: string | null;
}> {
  const exclude = excludeWorkoutIds.length > 0;
  const excludeClause = exclude
    ? `AND NOT (w.workout_id = ANY($2::text[]))`
    : "";

  const paceQuery = `SELECT s.split_pace::text AS min_pace,
	       to_char(w.local_date, 'YYYY-MM-DD') AS pace_date
	   FROM workout_splits s
	   JOIN workouts w ON w.workout_id = s.workout_id
	   WHERE w.user_id = $1
	       AND s.split_pace > 0
	       AND s.split_distance >= 0.95
	       ${excludeClause}
	   ORDER BY s.split_pace ASC, w.local_date DESC
	   LIMIT 1`;

  const dayQuery = `SELECT SUM(w.distance)::text AS best_day,
	       to_char(w.local_date, 'YYYY-MM-DD') AS best_day_date
	   FROM workouts w
	   WHERE w.user_id = $1 ${excludeClause}
	       AND w.deleted_at IS NULL AND w.exclusion_reason IS NULL
	   GROUP BY w.local_date
	   ORDER BY SUM(w.distance) DESC, w.local_date DESC
	   LIMIT 1`;

  const params: any[] = exclude ? [userId, excludeWorkoutIds] : [userId];

  const [paceRow, bestDayRow] = await Promise.all([
    db.query<{ min_pace: string | null; pace_date: string | null }>(
      paceQuery,
      params,
    ),
    db.query<{ best_day: string | null; best_day_date: string | null }>(
      dayQuery,
      params,
    ),
  ]);

  const fastestSplitPaceSecMi = paceRow[0]?.min_pace
    ? parseFloat(paceRow[0].min_pace)
    : 0;
  const mostMilesInOneDay = parseFloat(bestDayRow[0]?.best_day ?? "0") || 0;
  return {
    fastestSplitPaceSecMi,
    mostMilesInOneDay,
    fastestSplitDate: paceRow[0]?.pace_date ?? null,
    bestDayDate: bestDayRow[0]?.best_day_date ?? null,
  };
}
