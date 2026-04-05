import { Response } from 'express';
import { AuthenticatedRequest } from '../middleware/auth.js';
import { getCompetition } from '../services/competitionService.js';
import { getUser } from '../services/userService.js';
import { sendPush, canNudge, logNudge } from '../services/pushNotificationService.js';
import { shouldSendNotification } from '../services/notificationSettingsService.js';
import hasRequiredKeys from '../utils/hasRequiredKeys.js';

export async function nudgeUser(req: AuthenticatedRequest, res: Response) {
	if (!hasRequiredKeys(['competitionId', 'target_user_id'], req, res)) return;

	const competitionId = req.params.competitionId;
	const targetUserId = req.body.target_user_id;
	const senderId = req.userId!;

	try {
		if (senderId === targetUserId) {
			return res.status(400).json({ error: "You can't nudge yourself" });
		}

		const competition = await getCompetition(competitionId);
		if (!competition) {
			return res.status(404).json({ error: 'Competition not found' });
		}

		// Competition must be active (started, not finished)
		if (!competition.start_date || new Date(competition.start_date + ' EST') > new Date()) {
			return res.status(400).json({ error: 'Competition has not started yet' });
		}
		if (competition.end_date && new Date(competition.end_date + ' EST') <= new Date()) {
			return res.status(400).json({ error: 'Competition has already ended' });
		}

		// Both users must be accepted participants
		const senderInComp = competition.users.find(u => u.user_id === senderId && u.invite_status === 'accepted');
		const targetInComp = competition.users.find(u => u.user_id === targetUserId && u.invite_status === 'accepted');

		if (!senderInComp) {
			return res.status(403).json({ error: 'You are not a participant in this competition' });
		}
		if (!targetInComp) {
			return res.status(400).json({ error: 'Target user is not a participant in this competition' });
		}

		// Rate limit: 1 nudge per sender→target per competition per 24h
		const allowed = await canNudge(competitionId, senderId, targetUserId);
		if (!allowed) {
			return res.status(429).json({ error: 'You can only nudge this person once every 24 hours' });
		}

		await logNudge(competitionId, senderId, targetUserId);

		// Check notification preferences before sending
		const shouldSend = await shouldSendNotification(targetUserId, senderId, 'nudge');
		if (shouldSend) {
			const sender = await getUser({ userId: senderId });
			const senderName = sender?.username || 'Someone';

			await sendPush(targetUserId, {
				title: 'You got nudged!',
				body: `${senderName} nudged you in ${competition.competition_name}`,
				type: 'competition_nudge',
				data: { competition_id: competitionId, user_id: senderId }
			});
		}

		res.status(200).json({ message: 'Nudge sent' });
	} catch (error: any) {
		console.error('Error sending nudge:', error.message);
		res.status(500).json({ error: 'Error sending nudge' });
	}
}
