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
	getTodayMiles,
	updateWorkout as updateWorkoutDb
} from '../services/workoutService.js';
import { checkRaceCompletions } from '../services/competitionService.js';
import { notifyFriendsOfMileCompletion, checkCompetitionMilestones } from '../services/notificationService.js';

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

		try {
			await checkRaceCompletions(userId);
		} catch (raceError: any) {
			console.error('Error checking race completions:', raceError.message);
		}

		// Check if user has now completed their mile and notify friends
		try {
			const todayMiles = await getTodayMiles(userId);
			if (todayMiles >= 1.0) {
				notifyFriendsOfMileCompletion(userId).catch(err =>
					console.error('Error notifying friends:', err.message)
				);
			}
			checkCompetitionMilestones(userId).catch(err =>
				console.error('Error checking milestones:', err.message)
			);
		} catch (notifError: any) {
			console.error('Error checking notifications:', notifError.message);
		}

		res.status(200).json({
			message: 'Successfully uploaded workouts.'
		});
	} catch (error: any) {
		console.error('Error uploading workouts:', error.message);
		res.status(500).json({ error: 'Error uploading workouts: ' + error.message });
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
	} catch (error: any) {
		console.error('Error getting streak:', error.message);
		res.status(500).json({ error: 'Error getting streak: ' + error.message });
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
	} catch (error: any) {
		console.error('Error getting recent workouts:', error.message);
		res.status(500).json({ error: 'Error getting recent workouts: ' + error.message });
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
	} catch (error: any) {
		console.error('Error getting user stats:', error.message);
		res.status(500).json({ error: 'Error getting user stats: ' + error.message });
	}
}

export async function updateWorkout(req: Request, res: Response) {
	if (!hasRequiredKeys(['userId', 'workoutId'], req, res)) return;

	try {
		const { userId, workoutId } = req.params;
		const { distance, totalDuration, workoutType } = req.body;

		if (distance === undefined && totalDuration === undefined && workoutType === undefined) {
			return res.status(400).json({ error: 'No fields to update provided' });
		}

		if (distance !== undefined && (typeof distance !== 'number' || distance <= 0)) {
			return res.status(400).json({ error: 'Distance must be a positive number' });
		}

		if (totalDuration !== undefined && (typeof totalDuration !== 'number' || totalDuration <= 0)) {
			return res.status(400).json({ error: 'Duration must be a positive number' });
		}

		const user = await getUser({ userId });
		if (!user) {
			return res.status(400).json({ error: `No user found with ID ${userId}` });
		}

		const updated = await updateWorkoutDb(userId, workoutId, { distance, totalDuration, workoutType });

		if (!updated) {
			return res.status(404).json({ error: 'Workout not found' });
		}

		try {
			await checkRaceCompletions(userId);
		} catch (raceError: any) {
			console.error('Error checking race completions:', raceError.message);
		}

		res.status(200).json(updated);
	} catch (error: any) {
		console.error('Error updating workout:', error.message);
		res.status(500).json({ error: 'Error updating workout: ' + error.message });
	}
}
