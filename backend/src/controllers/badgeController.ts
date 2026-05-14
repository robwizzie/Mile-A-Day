import { Request, Response } from 'express';
import { AuthenticatedRequest } from '../middleware/auth.js';
import { getCatalog, getUserBadges, markBadgesViewed, setPinnedBadges, BadgePinError } from '../services/badgeService.js';
import { areFriends } from '../services/friendshipService.js';
import hasRequiredKeys from '../utils/hasRequiredKeys.js';

export async function getPublicCatalog(_req: Request, res: Response) {
	try {
		const badges = await getCatalog();
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

export async function setPinnedBadgesForUser(req: AuthenticatedRequest, res: Response) {
	if (!hasRequiredKeys(['userId'], req, res)) return;

	try {
		const targetUserId = req.params.userId;
		const raw = (req.body as any)?.pinnedBadgeIds;

		if (!Array.isArray(raw)) {
			return res.status(400).json({ error: 'pinnedBadgeIds must be an array of badge IDs' });
		}

		if (raw.length > 3) {
			return res.status(400).json({ error: 'At most 3 badges can be pinned' });
		}

		const ids: string[] = [];
		const seen = new Set<string>();
		for (const entry of raw) {
			if (typeof entry !== 'string' || entry.length === 0) {
				return res.status(400).json({ error: 'pinnedBadgeIds must contain non-empty strings' });
			}
			if (seen.has(entry)) {
				return res.status(400).json({ error: 'pinnedBadgeIds must be unique' });
			}
			seen.add(entry);
			ids.push(entry);
		}

		const badges = await setPinnedBadges(targetUserId, ids);
		return res.status(200).json({ userId: targetUserId, badges });
	} catch (err: any) {
		if (err instanceof BadgePinError) {
			return res.status(400).json({ error: err.message });
		}
		console.error('Error setting pinned badges:', err.message);
		return res.status(500).json({ error: 'Error setting pinned badges: ' + err.message });
	}
}
