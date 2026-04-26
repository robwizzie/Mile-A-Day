import { Response } from 'express';
import { AuthenticatedRequest } from '../middleware/auth.js';
import {
	getTodaysChallenge,
	getCompletions,
	getTodaysCompletion
} from '../services/dailyChallengeService.js';
import { areFriends } from '../services/friendshipService.js';
import { PostgresService } from '../services/DbService.js';
import hasRequiredKeys from '../utils/hasRequiredKeys.js';

const db = PostgresService.getInstance();

export async function getTodayForUser(req: AuthenticatedRequest, res: Response) {
	if (!hasRequiredKeys(['userId'], req, res)) return;

	try {
		const requesterId = req.userId;
		const targetUserId = req.params.userId;

		if (!requesterId) return res.status(401).json({ error: 'Authentication required' });

		if (requesterId !== targetUserId) {
			const allowed = await areFriends(requesterId, targetUserId);
			if (!allowed) return res.status(403).json({ error: 'Access denied — not friends with this user' });
		}

		const localDate = await resolveUserLocalDate(targetUserId);

		if (requesterId === targetUserId) {
			// Full detail including progress, challenge payload, completion timestamp.
			const response = await getTodaysChallenge(targetUserId, localDate);
			return res.status(200).json(response);
		}

		// Friend view: lightweight completion status only.
		const completion = await getTodaysCompletion(targetUserId, localDate);
		return res.status(200).json(completion);
	} catch (err: any) {
		console.error("Error getting today's challenge:", err.message);
		return res.status(500).json({ error: "Error getting today's challenge: " + err.message });
	}
}

export async function getCompletionsForUser(req: AuthenticatedRequest, res: Response) {
	if (!hasRequiredKeys(['userId'], req, res)) return;

	try {
		const completions = await getCompletions(req.params.userId);
		return res.status(200).json(completions);
	} catch (err: any) {
		console.error('Error getting challenge completions:', err.message);
		return res.status(500).json({ error: 'Error getting challenge completions: ' + err.message });
	}
}

async function resolveUserLocalDate(userId: string): Promise<string> {
	// Match existing pattern in workoutService.getTodayMiles: today in user's last-known timezone.
	const rows = await db.query<{ local_date: string }>(
		`SELECT (NOW() + (
			COALESCE(
				(SELECT timezone_offset FROM workouts WHERE user_id = $1 ORDER BY device_end_date DESC LIMIT 1),
				0
			) || ' minutes'
		)::interval)::date::text AS local_date`,
		[userId]
	);
	return rows[0]?.local_date ?? new Date().toISOString().slice(0, 10);
}
