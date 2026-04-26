import { Request, Response } from 'express';
import { AuthenticatedRequest } from '../middleware/auth.js';
import { getCatalog, getUserBadges, markBadgesViewed } from '../services/badgeService.js';
import { areFriends } from '../services/friendshipService.js';
import hasRequiredKeys from '../utils/hasRequiredKeys.js';

export async function getPublicCatalog(_req: Request, res: Response) {
	try {
		const badges = await getCatalog(false);
		return res.status(200).json({ badges });
	} catch (err: any) {
		console.error('Error getting badge catalog:', err.message);
		return res.status(500).json({ error: 'Error getting badge catalog: ' + err.message });
	}
}

export async function getBadgesForUser(req: AuthenticatedRequest, res: Response) {
	if (!hasRequiredKeys(['userId'], req, res)) return;

	try {
		const requesterId = req.userId;
		const targetUserId = req.params.userId;

		if (!requesterId) {
			return res.status(401).json({ error: 'Authentication required' });
		}

		if (requesterId !== targetUserId) {
			const allowed = await areFriends(requesterId, targetUserId);
			if (!allowed) {
				return res.status(403).json({ error: 'Access denied — not friends with this user' });
			}
		}

		const badges = await getUserBadges(targetUserId);
		return res.status(200).json({ userId: targetUserId, badges });
	} catch (err: any) {
		console.error('Error getting user badges:', err.message);
		return res.status(500).json({ error: 'Error getting user badges: ' + err.message });
	}
}

export async function markViewed(req: AuthenticatedRequest, res: Response) {
	if (!hasRequiredKeys(['userId'], req, res)) return;

	try {
		const updated = await markBadgesViewed(req.params.userId);
		return res.status(200).json({ updated });
	} catch (err: any) {
		console.error('Error marking badges viewed:', err.message);
		return res.status(500).json({ error: 'Error marking badges viewed: ' + err.message });
	}
}
