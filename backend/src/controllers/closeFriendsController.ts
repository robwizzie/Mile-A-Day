import { Response } from 'express';
import { getCloseFriends, addCloseFriend, removeCloseFriend } from '../services/closeFriendsService.js';
import { AuthenticatedRequest } from '../middleware/auth.js';

export async function listCloseFriends(req: AuthenticatedRequest, res: Response) {
	const userId = req.userId!;

	try {
		const friends = await getCloseFriends(userId);
		res.send(friends);
	} catch (err: any) {
		res.status(500).json({ error: err.message });
	}
}

export async function addCloseFriendHandler(req: AuthenticatedRequest, res: Response) {
	const userId = req.userId!;
	const { friendId } = req.params;

	if (!friendId) {
		return res.status(400).json({ error: 'friendId is required' });
	}

	if (userId === friendId) {
		return res.status(400).json({ error: 'You cannot add yourself to close friends' });
	}

	try {
		const result = await addCloseFriend(userId, friendId);
		if ('error' in result) {
			return res.status(400).json(result);
		}
		res.json(result);
	} catch (err: any) {
		res.status(500).json({ error: err.message });
	}
}

export async function removeCloseFriendHandler(req: AuthenticatedRequest, res: Response) {
	const userId = req.userId!;
	const { friendId } = req.params;

	if (!friendId) {
		return res.status(400).json({ error: 'friendId is required' });
	}

	try {
		const result = await removeCloseFriend(userId, friendId);
		if ('error' in result) {
			return res.status(400).json(result);
		}
		res.json(result);
	} catch (err: any) {
		res.status(500).json({ error: err.message });
	}
}
