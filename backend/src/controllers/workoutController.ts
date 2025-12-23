import { Request, Response } from 'express';
import { PostgresService } from '../services/DbService.js';
import hasRequiredKeys from '../utils/hasRequiredKeys.js';
import { getUser } from '../services/userService.js';
import { Workout } from '../types/workouts.js';
import {
	getActiveStreak,
	uploadWorkouts as uploadWorkoutsDb,
	getRecentWorkouts as getRecentWorkoutsDb,
	getTotalMiles,
	getBestMilesDay,
	getBestSplit,
	getTodayMiles
} from '../services/workoutService.js';

export async function uploadWorkouts(req: Request, res: Response) {
	if (!hasRequiredKeys(['userId'], req, res)) return;

	try {
		if (!Array.isArray(req.body)) {
			return res.status(400).json({
				error: 'Request body is not an array'
			});
		}

		const userId = req.params.userId;

		const user = await getUser({ userId });
		if (!user) {
			return res.status(400).send({ error: `No user found with ID ${userId}` });
		}

		await uploadWorkoutsDb(userId, req.body);

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

	try {
		const userId = req.params.userId;

		const user = await getUser({ userId });
		if (!user) {
			return res.status(400).send({ error: `No user found with ID ${userId}` });
		}

		const { streak } = await getActiveStreak(userId);

		return res.status(200).json({ streak });
	} catch (error) {
		return res.status(500).json({
			error: error instanceof Error ? error.message : 'Unknown error'
		});
	}
}

export async function getWorkoutRange() {}

export async function getRecentWorkouts(req: Request, res: Response) {
	if (!hasRequiredKeys(['userId'], req, res)) return;

	const limitParam = typeof req.query.limit === 'string' ? req.query.limit : '';
	let resultLimit: number | null = parseInt(limitParam);
	if (isNaN(resultLimit)) {
		resultLimit = null;
	}

	try {
		const userId = req.params.userId;

		const user = await getUser({ userId });
		if (!user) {
			return res.status(400).send({ error: `No user found with ID ${userId}` });
		}

		const results = await getRecentWorkoutsDb(userId, resultLimit);

		return res.status(200).json(results);
	} catch (error) {
		return res.status(500).json({
			error: error instanceof Error ? error.message : 'Unknown error'
		});
	}
}

export async function getUserStats(req: Request, res: Response) {
	if (!hasRequiredKeys(['userId'], req, res)) return;

	try {
		const userId = req.params.userId;
		const currentStreak = req.query.current_streak === 'true';

		const user = await getUser({ userId });
		if (!user) {
			return res.status(400).send({ error: `No user found with ID ${userId}` });
		}

		const { streak, start } = await getActiveStreak(userId);

		const startDateParam = currentStreak ? start : undefined;
		const [total_miles, best_miles_day, best_split_time, recent_workouts, today_miles] = await Promise.all([
			getTotalMiles(userId, startDateParam),
			getBestMilesDay(userId, startDateParam),
			getBestSplit(userId, startDateParam),
			getRecentWorkoutsDb(userId, 10),
			getTodayMiles(userId)
		]);

		// Default goal miles is 1.0 (can be updated when user preferences are stored)
		const goal_miles = 1.0;

		return res.status(200).json({
			streak,
			start_date: start,
			total_miles,
			best_miles_day,
			best_split_time,
			recent_workouts,
			today_miles,
			goal_miles
		});
	} catch (error) {
		return res.status(500).json({
			error: error instanceof Error ? error.message : 'Unknown error'
		});
	}
}
