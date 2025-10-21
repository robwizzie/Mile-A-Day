import { Request, Response } from 'express';
import { getUserStats, updateUserStats, addBadges, markBadgesAsViewed } from '../services/statsService.js';
import { UpdateStatsRequest, Badge } from '../types/stats.js';

/**
 * GET /stats/:userId
 * Get user stats and badges
 */
export async function getStats(req: Request, res: Response) {
	try {
		const { userId } = req.params;

		const data = await getUserStats(userId);

		res.json(data);
	} catch (error) {
		console.error('Error getting user stats:', error);
		res.status(500).json({ error: 'Failed to get user stats' });
	}
}

/**
 * PATCH /stats/:userId
 * Update user stats
 */
export async function updateStats(req: Request, res: Response) {
	try {
		const { userId } = req.params;
		const updates: UpdateStatsRequest = req.body;

		// Validate required fields
		if (
			typeof updates.streak !== 'number' ||
			typeof updates.total_miles !== 'number' ||
			typeof updates.fastest_mile_pace !== 'number' ||
			typeof updates.most_miles_in_one_day !== 'number'
		) {
			return res.status(400).json({
				error: 'Missing or invalid required fields: streak, total_miles, fastest_mile_pace, most_miles_in_one_day'
			});
		}

		await updateUserStats(userId, updates);

		res.json({ success: true, message: 'Stats updated successfully' });
	} catch (error) {
		console.error('Error updating user stats:', error);
		res.status(500).json({ error: 'Failed to update user stats' });
	}
}

/**
 * POST /stats/:userId/badges
 * Add badges to user
 */
export async function addUserBadges(req: Request, res: Response) {
	try {
		const { userId } = req.params;
		const { badges }: { badges: Omit<Badge, 'badge_id' | 'user_id'>[] } = req.body;

		if (!Array.isArray(badges)) {
			return res.status(400).json({ error: 'badges must be an array' });
		}

		await addBadges(userId, badges);

		res.json({ success: true, message: 'Badges added successfully' });
	} catch (error) {
		console.error('Error adding badges:', error);
		res.status(500).json({ error: 'Failed to add badges' });
	}
}

/**
 * PATCH /stats/:userId/badges/mark-viewed
 * Mark all badges as viewed for user
 */
export async function markUserBadgesViewed(req: Request, res: Response) {
	try {
		const { userId } = req.params;

		await markBadgesAsViewed(userId);

		res.json({ success: true, message: 'Badges marked as viewed' });
	} catch (error) {
		console.error('Error marking badges as viewed:', error);
		res.status(500).json({ error: 'Failed to mark badges as viewed' });
	}
}
