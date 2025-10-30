import { Workout } from '../types/workouts';
import { PostgresService } from './DbService';

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
        total_duration
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
      ON CONFLICT (user_id, workout_id)
      DO UPDATE SET
        distance = EXCLUDED.distance,
        local_date = EXCLUDED.local_date,
        date = EXCLUDED.date,
        timezone_offset = EXCLUDED.timezone_offset,
        workout_type = EXCLUDED.workout_type,
        device_end_date = EXCLUDED.device_end_date,
        calories = EXCLUDED.calories,
        total_duration = EXCLUDED.total_duration
      RETURNING workout_id, (xmax = 0) AS inserted
    `;

	const splitQuery = `
        INSERT INTO workout_splits (workout_id, split_number, split_time)
        VALUES ($1, $2, $3)
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
						workout.totalDuration
					]
				},
				...workout.splitTimes.map((split: number, i: number) => ({
					query: splitQuery,
					params: [workout.workoutId, i, split]
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
      ws.split_time AS best_split_time,
      w.*
    FROM workout_splits ws
    JOIN workouts w ON ws.workout_id = w.workout_id
    WHERE w.user_id = $1
	`;

	const params: (string | number)[] = [userId];

	if (startDate) {
		bestSplitQuery += ` AND w.local_date >= $2`;
		params.push(startDate);
	}

	bestSplitQuery += `
    ORDER BY ws.split_time ASC
    LIMIT 1
	`;

	const { best_split_time, ...workout } = (await db.query(bestSplitQuery, params))[0] || {};

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
