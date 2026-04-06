import { Workout } from '../types/workouts.js';
import { PostgresService } from './DbService.js';

const db = PostgresService.getInstance();

export async function uploadWorkouts(userId: string, workouts: Workout[]) {
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
}

export async function getActiveStreak(userId: string) {
	const dayDistanceQuery = `
    SELECT 
      local_date,
      SUM(distance) as total_distance,
      COUNT(*) as workout_count,
      SUM(calories) as total_calories,
      SUM(total_duration) as total_duration
    FROM workouts
    WHERE user_id = $1
    GROUP BY local_date
    ORDER BY local_date DESC
    LIMIT $2 OFFSET $3
  `;

	const LIMIT = 100;
	let index = 0;
	let streak = 0;
	let streakStartDay;
	while (true) {
		const results = await db.query(dayDistanceQuery, [userId, LIMIT, index * LIMIT]);

		if (results.length === 0) {
			break;
		}

		for (const row of results) {
			if (row.total_distance < 0.95) {
				return { streak, start: streakStartDay };
			}
			streakStartDay = row.local_date;
			streak++;
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
