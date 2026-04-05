import { Response } from 'express';
import { AuthenticatedRequest } from '../middleware/auth.js';
import { getCompetition, getUserScores } from '../services/competitionService.js';
import { getUser } from '../services/userService.js';
import { sendPush, canFlex, logFlex } from '../services/pushNotificationService.js';
import { shouldSendNotification } from '../services/notificationSettingsService.js';

const FLEX_PRESETS = [
	"Better luck next time",
	"Can't catch me",
	"Feeling unstoppable",
	"Is that all you got?",
	"Try to keep up",
	"Just getting started",
	"Too easy",
	"You should probably go run",
	"I woke up and chose victory",
	"Not even close"
];

export function getFlexPresets(_req: AuthenticatedRequest, res: Response) {
	res.status(200).json({ presets: FLEX_PRESETS });
}

export async function flexOnUser(req: AuthenticatedRequest, res: Response) {
	const competitionId = req.params.competitionId;
	const targetUserId = req.body.target_user_id;
	const message = req.body.message || null; // custom or preset message
	const senderId = req.userId!;

	try {
		if (!targetUserId) {
			return res.status(400).json({ error: 'target_user_id is required' });
		}

		if (senderId === targetUserId) {
			return res.status(400).json({ error: "You can't flex on yourself" });
		}

		// Validate message length
		if (message && message.length > 100) {
			return res.status(400).json({ error: 'Message must be 100 characters or less' });
		}

		const competition = await getCompetition(competitionId);
		if (!competition) {
			return res.status(404).json({ error: 'Competition not found' });
		}

		// Competition must be active
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

		// Verify sender is beating target (based on competition mode)
		const scores = await getUserScores(competition);
		const senderScore = scores[senderId]?.score ?? 0;
		const targetScore = scores[targetUserId]?.score ?? 0;

		if (senderScore <= targetScore) {
			return res.status(400).json({ error: "You can only flex when you're ahead of this user" });
		}

		// Rate limit: 1 flex per sender→target per day (across ALL competitions)
		const allowed = await canFlex(senderId, targetUserId);
		if (!allowed) {
			return res.status(429).json({ error: 'You can only flex on this person once per day' });
		}

		// Check notification preferences
		const shouldSend = await shouldSendNotification(targetUserId, senderId, 'flex');

		await logFlex(senderId, targetUserId, competitionId, message);

		if (shouldSend) {
			const sender = await getUser({ userId: senderId });
			const senderName = sender?.username || 'Someone';

			const flexBody = message
				? `${senderName} in ${competition.competition_name}: "${message}"`
				: `${senderName} is showing off in ${competition.competition_name}`;

			await sendPush(targetUserId, {
				title: 'You just got flexed on!',
				body: flexBody,
				type: 'competition_flex',
				data: {
					competition_id: competitionId,
					user_id: senderId,
					message: message || ''
				}
			});
		}

		res.status(200).json({ message: 'Flex sent' });
	} catch (error: any) {
		console.error('Error sending flex:', error.message);
		res.status(500).json({ error: 'Error sending flex' });
	}
}
