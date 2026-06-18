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
	updateWorkout as updateWorkoutDb,
	computePersonalRecords,
	getUserLocalToday
} from '../services/workoutService.js';
import { checkRaceCompletions } from '../services/competitionService.js';
import {
	notifyFriendsOfMileCompletion,
	notifyFriendsOfExtraWorkout,
	checkCompetitionMilestones,
	checkLeadChanges
} from '../services/notificationService.js';
import { evaluateWorkoutRewards } from '../services/badgeService.js';
import {
	fireBadgeEarnedPush,
	fanOutFriendBadgePush,
	fanOutFriendChallengePush,
	fanOutFriendPersonalBestPush
} from '../services/pushNotificationService.js';
import { refreshCurrentStreak } from '../services/leaderboardService.js';

export async function uploadWorkouts(req: Request, res: Response) {
	if (!hasRequiredKeys(['userId'], req, res)) return;

	try {
		if (!Array.isArray(req.body)) {
			return res.status(400).json({
				error: 'Request body is not an array'
			});
		}

		const userId = req.params.userId;

		// The iOS client sets ?fullSync=true on the bulk HealthKit backfill it runs
		// once when a user first sets up their account (and on re-login). Those uploads
		// are historical, so we must NOT spray friend-facing notifications ("got their
		// mile in", extra-workout, competition lead/milestone, friend badge/challenge,
		// personal-best) at other users. Absent/any-other value = normal sync (old
		// clients never send it), so behavior is unchanged for them.
		const isFullSync = req.query.fullSync === 'true' || req.query.fullSync === '1';

		// A notification only fires for activity from the last 24 hours. An old or
		// backdated workout (HealthKit can deliver backdated workouts; a manual log
		// can be for a past day) must NOT notify anyone — not friends, and not the
		// user for their own badge. We map each achievement back to the workout that
		// triggered it and suppress its push when that workout is outside the window.
		const recencyCutoffMs = Date.now() - 24 * 60 * 60 * 1000;
		const recentWorkoutIds = new Set(
			(req.body as Workout[])
				.filter(w => {
					const ts = Date.parse(w.deviceEndDate ?? w.date);
					return Number.isFinite(ts) && ts >= recencyCutoffMs;
				})
				.map(w => w.workoutId)
		);
		const hasRecentWorkout = recentWorkoutIds.size > 0;

		const user = await getUser({ userId });
		if (!user) {
			return res.status(400).send({ error: `No user found with ID ${userId}` });
		}

		const uploadedWorkoutIds = await uploadWorkoutsDb(userId, req.body);

		// Refresh the precomputed streak so the streak leaderboard stays fresh.
		// Fire-and-forget — recomputation reads ≤500 qualifying days for one
		// user, so it's cheap, but blocking the response on it isn't worth it.
		refreshCurrentStreak(userId).catch(err => console.error('Error refreshing current_streak:', err.message));

		try {
			await checkRaceCompletions(userId);
		} catch (raceError: any) {
			console.error('Error checking race completions:', raceError.message);
		}

		// Evaluate badges + daily challenges AFTER the upload transaction committed.
		// Kept inline (not fire-and-forget) so the response includes newly earned items.
		let rewards = {
			newlyEarnedBadges: [] as any[],
			newChallengeCompletions: [] as any[]
		};
		try {
			rewards = await evaluateWorkoutRewards(userId, uploadedWorkoutIds);
		} catch (rewardError: any) {
			console.error('Error evaluating workout rewards:', rewardError.message);
		}

		// Check if user has now completed their mile and notify friends.
		// Skipped on the initial account-setup backfill (isFullSync) and when this
		// upload carried no workout from the last 24h (a pure backfill of old data).
		if (!isFullSync && hasRecentWorkout) {
			try {
				const todayMiles = await getTodayMiles(userId);
				if (todayMiles >= 1.0) {
					const milestoneFired = await notifyFriendsOfMileCompletion(userId).catch(err => {
						console.error('Error notifying friends:', err.message);
						return false;
					});
					// If the mile was already completed before this upload, any new run/walk
					// workouts in this batch are "extras" — fan out a per-workout notification,
					// but only for the workouts that are themselves from the last 24h.
					if (!milestoneFired) {
						for (const w of req.body as Workout[]) {
							if (
								(w.workoutType === 'running' || w.workoutType === 'walking') &&
								recentWorkoutIds.has(w.workoutId)
							) {
								notifyFriendsOfExtraWorkout(userId, w.workoutId).catch(err =>
									console.error('Error notifying extra workout:', err.message)
								);
							}
						}
					}
				}
				(async () => {
					const notifiedRecipients = new Map<string, number>();
					await checkLeadChanges(userId, notifiedRecipients).catch(err =>
						console.error('Error checking lead changes:', err.message)
					);
					await checkCompetitionMilestones(userId, notifiedRecipients).catch(err =>
						console.error('Error checking milestones:', err.message)
					);
				})();
			} catch (notifError: any) {
				console.error('Error checking notifications:', notifError.message);
			}
		}

		// Fire badge + challenge push notifications (non-blocking). Each reward is
		// attributed to the workout that triggered it: if that workout is outside the
		// 24h window (e.g. a backfilled or manually-logged past run), NO push fires —
		// not the user's own badge_earned, not the friend fan-out. Aggregate rewards
		// with no single triggering workout fall back to "did this batch include any
		// workout from the last 24h". Friend fan-outs are additionally gated by
		// isFullSync so the setup backfill never notifies others.
		for (const badge of rewards.newlyEarnedBadges) {
			const fromRecentWorkout = badge.triggeringWorkoutId
				? recentWorkoutIds.has(badge.triggeringWorkoutId)
				: hasRecentWorkout;
			if (!fromRecentWorkout) continue;
			fireBadgeEarnedPush(userId, badge).catch(err => console.error('Error firing badge_earned push:', err.message));
			if (!isFullSync && badge.rarity !== 'common') {
				fanOutFriendBadgePush(userId, badge).catch(err =>
					console.error('Error fanning out friend_badge_earned:', err.message)
				);
			}
		}
		if (!isFullSync) {
			for (const completion of rewards.newChallengeCompletions) {
				const fromRecentWorkout = completion.completingWorkoutId
					? recentWorkoutIds.has(completion.completingWorkoutId)
					: hasRecentWorkout;
				if (!fromRecentWorkout) continue;
				fanOutFriendChallengePush(userId, completion).catch(err =>
					console.error('Error fanning out friend_challenge_completed:', err.message)
				);
			}
		}

		// PR detection: compare pre-upload PRs (excluding this batch) to post-upload PRs.
		// Fan out one notification per dimension that improved — but only when the
		// record was set TODAY (user's local date). Historical imports (e.g. a new
		// account's initial HealthKit backfill) raise the all-time max too, and
		// without this guard every backfill batch sprays bogus "new personal best"
		// pushes at the user's friends. The full-sync guard skips this outright;
		// the today-guard remains the backstop for normal syncs. Fire-and-forget.
		if (!isFullSync)
			(async () => {
				try {
					const [pre, post, userToday] = await Promise.all([
						computePersonalRecords(userId, uploadedWorkoutIds),
						computePersonalRecords(userId),
						getUserLocalToday(userId)
					]);
					const lastWorkoutId = uploadedWorkoutIds[uploadedWorkoutIds.length - 1] ?? '';

					if (
						post.fastestSplitPaceSecMi > 0 &&
						(pre.fastestSplitPaceSecMi === 0 || post.fastestSplitPaceSecMi < pre.fastestSplitPaceSecMi) &&
						post.fastestSplitDate === userToday
					) {
						fanOutFriendPersonalBestPush(userId, 'fastest_mile', post.fastestSplitPaceSecMi, lastWorkoutId).catch(
							err => console.error('Error fanning out friend_personal_best (fastest_mile):', err.message)
						);
					}
					if (post.mostMilesInOneDay > pre.mostMilesInOneDay && post.bestDayDate === userToday) {
						fanOutFriendPersonalBestPush(userId, 'most_miles_day', post.mostMilesInOneDay, lastWorkoutId).catch(err =>
							console.error('Error fanning out friend_personal_best (most_miles_day):', err.message)
						);
					}
				} catch (err: any) {
					console.error('Error detecting personal bests:', err.message);
				}
			})();

		res.status(200).json({
			message: 'Successfully uploaded workouts.',
			newlyEarnedBadges: rewards.newlyEarnedBadges,
			newChallengeCompletions: rewards.newChallengeCompletions
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

/**
 * Force a synchronous recompute of the user's current streak and return the
 * fresh value. The "recalibrate streak" feature: the client first re-uploads
 * its local HealthKit workouts (idempotent via ON CONFLICT) to backfill any
 * runs that never reached the server — e.g. a manual/backdated log whose
 * upload silently failed — then calls this so the streak reflects the
 * now-complete data immediately, instead of racing the fire-and-forget
 * refresh that the upload pipeline kicks off.
 */
export async function recalibrateStreak(req: Request, res: Response) {
	if (!hasRequiredKeys(['userId'], req, res)) return;

	try {
		const userId = req.params.userId;

		const user = await getUser({ userId });
		if (!user) {
			return res.status(400).send({ error: `No user found with ID ${userId}` });
		}

		const streak = await refreshCurrentStreak(userId);

		return res.status(200).json({ streak });
	} catch (error: any) {
		console.error('Error recalibrating streak:', error.message);
		res.status(500).json({ error: 'Error recalibrating streak: ' + error.message });
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

		const updated = await updateWorkoutDb(userId, workoutId, {
			distance,
			totalDuration,
			workoutType
		});

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
