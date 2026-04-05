import { Response } from 'express';
import { AuthenticatedRequest } from '../middleware/auth.js';
import { getUser } from '../services/userService.js';
import { getFriendship } from '../services/friendshipService.js';
import { sendPush, canFriendNudge, logFriendNudge } from '../services/pushNotificationService.js';
import { shouldSendNotification } from '../services/notificationSettingsService.js';
import { getTodayMiles } from '../services/workoutService.js';

export async function nudgeFriend(req: AuthenticatedRequest, res: Response) {
	const friendId = req.params.friendId;
	const senderId = req.userId!;

	try {
		if (senderId === friendId) {
			return res.status(400).json({ error: "You can't nudge yourself" });
		}

		// Verify they are friends
		const friendship = await getFriendship(senderId, friendId);
		if (!friendship || 'error' in friendship || friendship.status !== 'accepted') {
			return res.status(400).json({ error: 'You can only nudge friends' });
		}

		// Check if friend has already completed their mile today
		const friendTodayMiles = await getTodayMiles(friendId);
		if (friendTodayMiles >= 1.0) {
			return res.status(400).json({ error: 'This friend has already completed their mile today' });
		}

		// Rate limit: 1 nudge per friend per 24h
		const allowed = await canFriendNudge(senderId, friendId);
		if (!allowed) {
			return res.status(429).json({ error: 'You can only nudge this friend once per day' });
		}

		// Check notification preferences
		const shouldSend = await shouldSendNotification(friendId, senderId, 'nudge');

		await logFriendNudge(senderId, friendId);

		if (shouldSend) {
			const sender = await getUser({ userId: senderId });
			const senderName = sender?.username || 'Someone';

			await sendPush(friendId, {
				title: 'Time to lace up!',
				body: `${senderName} is nudging you to get your mile in today`,
				type: 'friend_nudge',
				data: { user_id: senderId }
			});
		}

		res.status(200).json({ message: 'Nudge sent' });
	} catch (error: any) {
		console.error('Error sending friend nudge:', error.message);
		res.status(500).json({ error: 'Error sending nudge' });
	}
}

// Check if a friend can be nudged (for UI state)
export async function checkNudgeStatus(req: AuthenticatedRequest, res: Response) {
	const friendId = req.params.friendId;
	const senderId = req.userId!;

	try {
		const [canNudge, friendTodayMiles] = await Promise.all([
			canFriendNudge(senderId, friendId),
			getTodayMiles(friendId)
		]);

		const hasCompletedMile = friendTodayMiles >= 1.0;

		res.status(200).json({
			can_nudge: canNudge && !hasCompletedMile,
			has_completed_mile: hasCompletedMile,
			already_nudged_today: !canNudge
		});
	} catch (error: any) {
		console.error('Error checking nudge status:', error.message);
		res.status(500).json({ error: 'Error checking nudge status' });
	}
}

// Batch check nudge status for all friends
export async function checkNudgeStatusBatch(req: AuthenticatedRequest, res: Response) {
	const senderId = req.userId!;
	const friendIds = req.body.friend_ids;

	if (!Array.isArray(friendIds) || friendIds.length === 0) {
		return res.status(400).json({ error: 'friend_ids must be a non-empty array' });
	}

	try {
		const statuses: Record<string, { can_nudge: boolean; has_completed_mile: boolean; already_nudged_today: boolean }> = {};

		await Promise.all(
			friendIds.map(async (friendId: string) => {
				const [canNudge, friendTodayMiles] = await Promise.all([
					canFriendNudge(senderId, friendId),
					getTodayMiles(friendId)
				]);

				const hasCompletedMile = friendTodayMiles >= 1.0;
				statuses[friendId] = {
					can_nudge: canNudge && !hasCompletedMile,
					has_completed_mile: hasCompletedMile,
					already_nudged_today: !canNudge
				};
			})
		);

		res.status(200).json({ statuses });
	} catch (error: any) {
		console.error('Error checking nudge statuses:', error.message);
		res.status(500).json({ error: 'Error checking nudge statuses' });
	}
}
