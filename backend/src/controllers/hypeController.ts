import { Response } from 'express';
import { AuthenticatedRequest } from '../middleware/auth.js';
import { PostgresService } from '../services/DbService.js';
import { getFriendship } from '../services/friendshipService.js';
import { getTodayMiles, getMilesOnLocalDate } from '../services/workoutService.js';
import { getUser } from '../services/userService.js';
import { sendPush } from '../services/pushNotificationService.js';
import { shouldSendNotification } from '../services/notificationSettingsService.js';
import {
	logHypeIfUnderLimit,
	getDailyHypeCount,
	getHypeResetsAt,
	hasHypedContext,
	HYPE_DAILY_LIMIT,
	HypeContext
} from '../services/hypeService.js';
import { hasChallengeCompletion } from '../services/dailyChallengeService.js';

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

/**
 * Formats an ISO timestamp as a human-readable "in X" string (e.g. "in 2 hours",
 * "in 45 minutes"). Returns null if the timestamp is missing or already past.
 */
function formatTimeUntil(isoTimestamp: string | null): string | null {
	if (!isoTimestamp) return null;
	const target = new Date(isoTimestamp).getTime();
	if (Number.isNaN(target)) return null;
	const deltaMs = target - Date.now();
	if (deltaMs <= 0) return null;
	const minutes = Math.round(deltaMs / 60_000);
	if (minutes < 60) return `${minutes} ${minutes === 1 ? 'minute' : 'minutes'}`;
	const hours = Math.round(minutes / 60);
	if (hours < 24) return `${hours} ${hours === 1 ? 'hour' : 'hours'}`;
	const days = Math.round(hours / 24);
	return `${days} ${days === 1 ? 'day' : 'days'}`;
}

function buildHypeBackBody(senderName: string, context: HypeContext | undefined): string {
	if (!context) {
		return `@${senderName} just hyped up your recent workout!`;
	}
	switch (context.contextType) {
		case 'mile':
			return `${senderName} hyped your daily mile 🔥`;
		case 'badge':
			return `${senderName} hyped you earning '${context.contextLabel}' 🔥`;
		case 'pr':
			return `${senderName} hyped your new ${context.contextLabel} 🔥`;
		case 'challenge':
			return `${senderName} hyped your '${context.contextLabel}' challenge 🔥`;
	}
}

export async function sendHype(req: AuthenticatedRequest, res: Response) {
	const senderId = req.userId!;
	const targetUserId = req.body?.target_user_id;
	const rawContextType = req.body?.context_type;
	const rawContextId = req.body?.context_id;
	const rawContextLabel = req.body?.context_label;

	try {
		if (!targetUserId || typeof targetUserId !== 'string') {
			return res.status(400).json({ error: 'target_user_id is required' });
		}
		if (senderId === targetUserId) {
			return res.status(400).json({ error: "You can't hype yourself" });
		}

		// Parse optional context. All three must be present together, or all absent.
		let context: HypeContext | undefined;
		const anyCtx = rawContextType || rawContextId || rawContextLabel;
		const allCtx = rawContextType && rawContextId && rawContextLabel;
		if (anyCtx && !allCtx) {
			return res.status(400).json({
				error: 'context_type, context_id, and context_label must be provided together'
			});
		}
		if (allCtx) {
			if (!['mile', 'badge', 'pr', 'challenge'].includes(rawContextType)) {
				return res.status(400).json({
					error: "context_type must be one of 'mile' | 'badge' | 'pr' | 'challenge'"
				});
			}
			context = {
				contextType: rawContextType,
				contextId: String(rawContextId),
				contextLabel: String(rawContextLabel)
			};
		}

		const allowed = await isFriendOrCoParticipant(senderId, targetUserId);
		if (!allowed) {
			return res.status(403).json({
				error: 'You can only hype friends or people in your active competitions'
			});
		}

		// Validate the target actually completed the event being hyped.
		// - No context (legacy): require they ran today.
		// - mile context: contextId is "userId:YYYY-MM-DD" — require ≥1 mile on
		//   that local date. Lets users hype old mile-completion notifications.
		// - badge / pr: the event reference + dedupe handles it; no mile gate.
		if (!context) {
			const todayMiles = await getTodayMiles(targetUserId);
			if (todayMiles < 1.0) {
				return res.status(400).json({ error: "This user hasn't completed their mile today" });
			}
		} else if (context.contextType === 'mile') {
			const dateMatch = context.contextId.match(/:(\d{4}-\d{2}-\d{2})$/);
			if (!dateMatch) {
				return res.status(400).json({ error: 'Invalid mile context_id; expected "<userId>:YYYY-MM-DD"' });
			}
			const milesOnDate = await getMilesOnLocalDate(targetUserId, dateMatch[1]);
			if (milesOnDate < 1.0) {
				return res.status(400).json({ error: "This user didn't complete a mile that day" });
			}
		} else if (context.contextType === 'challenge') {
			const dateMatch = context.contextId.match(/:(\d{4}-\d{2}-\d{2})$/);
			if (!dateMatch) {
				return res.status(400).json({ error: 'Invalid challenge context_id; expected "<userId>:YYYY-MM-DD"' });
			}
			const completed = await hasChallengeCompletion(targetUserId, dateMatch[1]);
			if (!completed) {
				return res.status(400).json({ error: "This user didn't complete a challenge that day" });
			}
		}

		// Context-aware dedupe pre-check (legacy no-context hypes skip this).
		if (context) {
			const alreadyHyped = await hasHypedContext(senderId, targetUserId, context.contextType, context.contextId);
			if (alreadyHyped) {
				return res.status(409).json({ error: 'already_hyped' });
			}
		}

		// Atomic: insert iff still under the limit. Closes the concurrent-sender race.
		const inserted = await logHypeIfUnderLimit(senderId, targetUserId, context);
		if (!inserted) {
			const resetsAt = await getHypeResetsAt(senderId);
			const resetIn = formatTimeUntil(resetsAt);
			const error = resetIn
				? `You're out of hypes — you've used all ${HYPE_DAILY_LIMIT} today. Try again in ${resetIn}.`
				: `You're out of hypes — you've used all ${HYPE_DAILY_LIMIT} today. Come back tomorrow.`;
			return res.status(429).json({
				error,
				hypes_remaining: 0,
				resets_at: resetsAt
			});
		}

		const countAfter = await getDailyHypeCount(senderId);

		const shouldSend = await shouldSendNotification(targetUserId, senderId, 'hype');
		if (shouldSend) {
			const sender = await getUser({ userId: senderId });
			const senderName = sender?.username ?? 'Someone';
			const body = buildHypeBackBody(senderName, context);
			const pushData: Record<string, string> = { user_id: senderId };
			if (context) {
				pushData.context_type = context.contextType;
				pushData.context_label = context.contextLabel;
			}
			await sendPush(targetUserId, {
				title: '🔥 You got hyped!',
				body,
				type: 'hype_received',
				data: pushData
			});
		}

		res.status(200).json({
			message: 'Hype sent',
			hypes_remaining: Math.max(0, HYPE_DAILY_LIMIT - countAfter)
		});
	} catch (error: any) {
		console.error('Error sending hype:', error.message);
		res.status(500).json({ error: 'Error sending hype' });
	}
}

export async function getHypeStatus(req: AuthenticatedRequest, res: Response) {
	const senderId = req.userId!;
	try {
		const [count, resetsAt] = await Promise.all([getDailyHypeCount(senderId), getHypeResetsAt(senderId)]);
		res.status(200).json({
			hypes_remaining: Math.max(0, HYPE_DAILY_LIMIT - count),
			resets_at: resetsAt
		});
	} catch (error: any) {
		console.error('Error getting hype status:', error.message);
		res.status(500).json({ error: 'Error getting hype status' });
	}
}
