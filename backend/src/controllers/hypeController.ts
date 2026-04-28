import { Response } from 'express';
import { AuthenticatedRequest } from '../middleware/auth.js';
import { PostgresService } from '../services/DbService.js';
import { getFriendship } from '../services/friendshipService.js';
import { getTodayMiles } from '../services/workoutService.js';
import { getUser } from '../services/userService.js';
import { sendPush } from '../services/pushNotificationService.js';
import { shouldSendNotification } from '../services/notificationSettingsService.js';
import {
	logHypeIfUnderLimit,
	getDailyHypeCount,
	getHypeResetsAt,
	HYPE_DAILY_LIMIT,
} from '../services/hypeService.js';

const db = PostgresService.getInstance();

/**
 * True if sender and target are accepted participants in at least one
 * currently-active competition.
 */
async function shareActiveCompetition(senderId: string, targetId: string): Promise<boolean> {
	const rows = await db.query<{ exists: boolean }>(
		`SELECT EXISTS (
			SELECT 1
			FROM competition_users cu_sender
			JOIN competition_users cu_target ON cu_target.competition_id = cu_sender.competition_id
			JOIN competitions c ON c.id = cu_sender.competition_id
			WHERE cu_sender.user_id = $1
				AND cu_target.user_id = $2
				AND cu_sender.invite_status = 'accepted'
				AND cu_target.invite_status = 'accepted'
				AND c.start_date IS NOT NULL
				AND c.start_date <= NOW()
				AND c.winner IS NULL
				AND (c.end_date IS NULL OR c.end_date > NOW())
		) AS exists`,
		[senderId, targetId]
	);
	return rows[0]?.exists === true;
}

async function isFriendOrCoParticipant(senderId: string, targetId: string): Promise<boolean> {
	const friendship = await getFriendship(senderId, targetId);
	const friendsAccepted = !!friendship && !('error' in friendship) && friendship.status === 'accepted';
	if (friendsAccepted) return true;
	return shareActiveCompetition(senderId, targetId);
}

export async function sendHype(req: AuthenticatedRequest, res: Response) {
	const senderId = req.userId!;
	const targetUserId = req.body?.target_user_id;

	try {
		if (!targetUserId || typeof targetUserId !== 'string') {
			return res.status(400).json({ error: 'target_user_id is required' });
		}
		if (senderId === targetUserId) {
			return res.status(400).json({ error: "You can't hype yourself" });
		}

		const allowed = await isFriendOrCoParticipant(senderId, targetUserId);
		if (!allowed) {
			return res.status(403).json({
				error: 'You can only hype friends or people in your active competitions',
			});
		}

		const todayMiles = await getTodayMiles(targetUserId);
		if (todayMiles < 1.0) {
			return res.status(400).json({ error: "This user hasn't completed their mile today" });
		}

		// Atomic: insert iff still under the limit. Closes the concurrent-sender race.
		const inserted = await logHypeIfUnderLimit(senderId, targetUserId);
		if (!inserted) {
			return res.status(429).json({
				error: `You've used all ${HYPE_DAILY_LIMIT} hypes for the day`,
				hypes_remaining: 0,
				resets_at: await getHypeResetsAt(senderId),
			});
		}

		const countAfter = await getDailyHypeCount(senderId);

		const shouldSend = await shouldSendNotification(targetUserId, senderId, 'hype');
		if (shouldSend) {
			const sender = await getUser({ userId: senderId });
			const senderName = sender?.username ?? 'Someone';
			await sendPush(targetUserId, {
				title: '🔥 You got hyped!',
				body: `@${senderName} just hyped up your recent workout!`,
				type: 'hype_received',
				data: { user_id: senderId },
			});
		}

		res.status(200).json({
			message: 'Hype sent',
			hypes_remaining: Math.max(0, HYPE_DAILY_LIMIT - countAfter),
		});
	} catch (error: any) {
		console.error('Error sending hype:', error.message);
		res.status(500).json({ error: 'Error sending hype' });
	}
}

export async function getHypeStatus(req: AuthenticatedRequest, res: Response) {
	const senderId = req.userId!;
	try {
		const [count, resetsAt] = await Promise.all([
			getDailyHypeCount(senderId),
			getHypeResetsAt(senderId),
		]);
		res.status(200).json({
			hypes_remaining: Math.max(0, HYPE_DAILY_LIMIT - count),
			resets_at: resetsAt,
		});
	} catch (error: any) {
		console.error('Error getting hype status:', error.message);
		res.status(500).json({ error: 'Error getting hype status' });
	}
}
