import { Workout } from '../types/workouts.js';
import { PostgresService } from './DbService.js';

const db = PostgresService.getInstance();

export async function uploadWorkouts(userId: string, workouts: Workout[]): Promise<string[]> {
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
        source
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
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
        END
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

	await db.transaction(
		workouts.flatMap((workout: Workout) => {
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
						workout.source || 'healthkit'
					]
				},
				...workout.splits.map(split => ({
					query: splitQuery,
					params: [workout.workoutId, split.splitNumber, split.duration, split.distance, split.pace]
				}))
			];
		})
	);

	return workouts.map(w => w.workoutId);
}

function dateStringMinus(dateStr: string, days: number): string {
	const [y, m, d] = dateStr.split('-').map(Number);
	const date = new Date(Date.UTC(y, m - 1, d));
	date.setUTCDate(date.getUTCDate() - days);
	return date.toISOString().slice(0, 10);
}

export async function getActiveStreak(userId: string) {
	const todayResult = await db.query(
		`
    SELECT to_char(
      (NOW() + (COALESCE(
        (SELECT timezone_offset FROM workouts WHERE user_id = $1 ORDER BY device_end_date DESC LIMIT 1),
        0
      ) || ' minutes')::interval)::date,
      'YYYY-MM-DD'
    ) AS user_today
  `,
		[userId]
	);
	const userToday: string = todayResult[0].user_today;
	const yesterday = dateStringMinus(userToday, 1);

	const qualifyingDaysQuery = `
    SELECT to_char(local_date, 'YYYY-MM-DD') AS local_date
    FROM workouts
    WHERE user_id = $1
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
		const results = await db.query(qualifyingDaysQuery, [userId, LIMIT, index * LIMIT]);
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
	AND split_distance >= 1
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

export async function getRecentWorkouts(userId: string, limit: number | null = 10) {
	const recentWorkoutsQuery = `
	SELECT * FROM workouts
	WHERE user_id = $1
	ORDER BY device_end_date DESC
	LIMIT $2
	`;

	return await db.query(recentWorkoutsQuery, [userId, limit]);
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
	`;

	const result = await db.query(todayMilesQuery, [userId]);
	return result[0]?.total_distance || 0;
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
		WHERE ws.split_distance >= 0.95
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
	const toNum = (v: number | string | null | undefined): number => (v == null ? 0 : typeof v === 'string' ? Number(v) : v);
	const pace = row?.best_split_pace_sec_mi;

	return {
		miles: toNum(row?.miles),
		durationSeconds: toNum(row?.duration_seconds),
		bestSplitPaceSecMi: pace == null ? null : Number(pace)
	};
}

export async function getQuantityDateRange(
	userId: string,
	startDate: string,
	endDate?: string,
	workoutTypes?: ('running' | 'walking')[]
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
		GROUP BY local_date
		ORDER BY local_date ASC
	`;

	const todaysDate = new Date().toISOString().split('T')[0];
	const start = new Date(startDate).toISOString().split('T')[0];
	const end = endDate ? new Date(endDate).toISOString().split('T')[0] : todaysDate;

	const typeMap: Record<string, 'running' | 'walking'> = {
		run: 'running',
		walk: 'walking',
		running: 'running',
		walking: 'walking'
	};
	const normalizedTypes = (workoutTypes ?? ['running', 'walking']).map(t => typeMap[t]).filter(Boolean);

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
	workoutTypes?: ('running' | 'walking')[]
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
		GROUP BY user_id, local_date
		ORDER BY user_id, local_date ASC
	`;

	const todaysDate = new Date().toISOString().split('T')[0];
	const start = new Date(startDate).toISOString().split('T')[0];
	const end = endDate ? new Date(endDate).toISOString().split('T')[0] : todaysDate;

	const typeMap: Record<string, 'running' | 'walking'> = {
		run: 'running',
		walk: 'walking',
		running: 'running',
		walking: 'walking'
	};
	const normalizedTypes = (workoutTypes ?? ['running', 'walking']).map(t => typeMap[t]).filter(Boolean);

	return await db.query(query, [userIds, start, end, normalizedTypes]);
}

/**
 * Batched manual-workout check for a set of users over a date range.
 * Returns the set of user_ids that have at least one manual/edited workout in range.
 */
export async function getUsersWithManualWorkouts(userIds: string[], startDate: string, endDate: string): Promise<Set<string>> {
	if (userIds.length === 0) return new Set();

	const result = await db.query<{ user_id: string }>(
		`SELECT DISTINCT user_id FROM workouts
		 WHERE user_id = ANY($1::text[])
			AND local_date >= $2
			AND local_date <= $3
			AND source IN ('manual', 'edited')`,
		[userIds, startDate, endDate]
	);

	return new Set(result.map(r => r.user_id));
}

export async function updateWorkout(
	userId: string,
	workoutId: string,
	updates: { distance?: number; totalDuration?: number; workoutType?: string }
) {
	const current = await db.query(
		'SELECT distance, total_duration, original_distance FROM workouts WHERE workout_id = $1 AND user_id = $2',
		[workoutId, userId]
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
			row.total_duration
		]
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
 */
export async function computePersonalRecords(
	userId: string,
	excludeWorkoutIds: string[] = []
): Promise<{ fastestSplitPaceSecMi: number; mostMilesInOneDay: number }> {
	const exclude = excludeWorkoutIds.length > 0;

	const paceQuery = exclude
		? `SELECT MIN(s.split_pace)::text AS min_pace
		   FROM workout_splits s
		   JOIN workouts w ON w.workout_id = s.workout_id
		   WHERE w.user_id = $1
		       AND s.split_pace > 0
		       AND s.split_distance >= 0.95
		       AND NOT (w.workout_id = ANY($2::text[]))`
		: `SELECT MIN(s.split_pace)::text AS min_pace
		   FROM workout_splits s
		   JOIN workouts w ON w.workout_id = s.workout_id
		   WHERE w.user_id = $1 AND s.split_pace > 0 AND s.split_distance >= 0.95`;

	const dayQuery = exclude
		? `SELECT COALESCE(MAX(day_total), 0)::text AS best_day FROM (
				SELECT SUM(distance) AS day_total FROM workouts
				WHERE user_id = $1 AND NOT (workout_id = ANY($2::text[]))
				GROUP BY local_date
			) t`
		: `SELECT COALESCE(MAX(day_total), 0)::text AS best_day FROM (
				SELECT SUM(distance) AS day_total FROM workouts
				WHERE user_id = $1 GROUP BY local_date
			) t`;

	const params: any[] = exclude ? [userId, excludeWorkoutIds] : [userId];

	const [paceRow, bestDayRow] = await Promise.all([
		db.query<{ min_pace: string | null }>(paceQuery, params),
		db.query<{ best_day: string | null }>(dayQuery, params)
	]);

	const fastestSplitPaceSecMi = paceRow[0]?.min_pace ? parseFloat(paceRow[0].min_pace) : 0;
	const mostMilesInOneDay = parseFloat(bestDayRow[0]?.best_day ?? '0') || 0;
	return { fastestSplitPaceSecMi, mostMilesInOneDay };
}
