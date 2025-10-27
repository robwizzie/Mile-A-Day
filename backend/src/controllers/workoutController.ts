import { Request, Response } from 'express';
import { PostgresService } from '../services/DbService.js';
import hasRequiredKeys from '../utils/hasRequiredKeys.js';

const db = PostgresService.getInstance();

type Workout = {
	workoutId: string;
	distance: number;
	localDate: string;
	date: string;
	timezoneOffset: number;
	workoutType: string;
	deviceEndDate: string;
	calories: number;
	totalDuration: number;
	splitTimes: number[];
};

export async function uploadWorkouts(req: Request, res: Response) {
	if (!hasRequiredKeys(['userId'], req, res)) return;

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

	try {
		if (!Array.isArray(req.body)) {
			return res.status(400).json({
				error: 'Request body is not an array'
			});
		}

		await db.transaction(
			req.body.flatMap((workout: Workout) => {
				return [
					{
						query: workoutQuery,
						params: [
							req.params.userId,
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

		res.status(200).json({
			message: 'Successfully uploaded workouts.'
		});
	} catch (error) {
		return res.status(500).json({
			error: error instanceof Error ? error.message : 'Unknown error'
		});
	}
}

export async function getStreak(req: Request, res: Response) {
	if (!hasRequiredKeys(['userId'], req, res)) return;

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

	try {
		const LIMIT = 100;
		let index = 0;
		let streak = 0;
		while (true) {
			const results = await db.query(dayDistanceQuery, [req.params.userId, LIMIT, index * LIMIT]);

			if (results.length === 0) {
				break;
			}

			for (const row of results) {
				if (row.total_distance < 0.95) {
					return res.status(200).json({ streak });
				}
				streak++;
			}

			index++;
		}

		return res.status(200).json({ streak });
	} catch (error) {
		return res.status(500).json({
			error: error instanceof Error ? error.message : 'Unknown error'
		});
	}
}

export async function getWorkoutRange() {}

export async function getRecentWorkouts() {}
