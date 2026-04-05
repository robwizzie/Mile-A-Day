import { PostgresService } from './DbService.js';
import { sendPush, sendOrQueueCompetitionNotification } from './pushNotificationService.js';
import { shouldSendNotification } from './notificationSettingsService.js';
import { getCompetition, getUserScores } from './competitionService.js';
import { Competition, CompetitionUser } from '../types/competitions.js';

const db = PostgresService.getInstance();

// ─── Workout Completion Notifications ──────────────────────────────

/**
 * Notify friends when a user completes their mile for the day.
 * Only sends once per day per user, and respects friend notification settings.
 * Caps at 5 friend notifications to avoid spam.
 */
export async function notifyFriendsOfMileCompletion(userId: string): Promise<void> {
	try {
		// Check if we already sent completion notifications today
		const today = new Date().toISOString().split('T')[0];
		const alreadySent = await db.query(
			`SELECT id FROM workout_completion_notifications
			WHERE user_id = $1 AND notified_date = $2
			LIMIT 1`,
			[userId, today]
		);

		if (alreadySent.length > 0) return;

		// Get user info
		const [user] = await db.query('SELECT username FROM users WHERE user_id = $1', [userId]);
		if (!user) return;

		// Get friends (bidirectional accepted)
		const friends = await db.query(
			`SELECT friend_id FROM friendships
			WHERE user_id = $1 AND status = 'accepted'`,
			[userId]
		);

		if (friends.length === 0) return;

		// Log that we've sent notifications today
		await db.query(
			`INSERT INTO workout_completion_notifications (user_id, notified_date) VALUES ($1, $2)
			ON CONFLICT (user_id, notified_date) DO NOTHING`,
			[userId, today]
		);

		// Send to up to 5 friends (respect notification settings)
		let sentCount = 0;
		for (const { friend_id } of friends) {
			if (sentCount >= 5) break;

			const shouldSend = await shouldSendNotification(friend_id, userId, 'friend_activity');
			if (!shouldSend) continue;

			sendPush(friend_id, {
				title: `${user.username} got their mile in!`,
				body: 'Your friend just completed their daily mile. Time to lace up!',
				type: 'friend_activity',
				data: { user_id: userId }
			}).catch(err => console.error('[Push] Error sending friend activity:', err.message));

			sentCount++;
		}

		if (sentCount > 0) {
			console.log(`[Notifications] Sent mile completion to ${sentCount} friends of ${user.username}`);
		}
	} catch (err: any) {
		console.error('[Notifications] Error notifying friends of mile completion:', err.message);
	}
}

// ─── Competition Milestone Notifications ────────────────────────────

/**
 * Check for competition milestones after a workout upload.
 * Milestones:
 * - Race: user reaches 50% of goal
 * - Clash/Targets: user is 1 point from winning (first_to)
 * - Any type: competition ends tomorrow
 */
export async function checkCompetitionMilestones(userId: string): Promise<void> {
	try {
		// Get all active competitions for this user
		const activeComps = await db.query<Competition & { id: string }>(
			`SELECT c.*
			FROM competitions c
			JOIN competition_users cu ON cu.competition_id = c.id
			WHERE cu.user_id = $1
				AND cu.invite_status = 'accepted'
				AND c.start_date IS NOT NULL
				AND c.start_date <= NOW()
				AND c.winner IS NULL
				AND (c.end_date IS NULL OR c.end_date > NOW())`,
			[userId]
		);

		if (activeComps.length === 0) return;

		const [user] = await db.query('SELECT username FROM users WHERE user_id = $1', [userId]);
		const username = user?.username || 'Someone';

		for (const comp of activeComps) {
			try {
				await checkMilestonesForCompetition(comp, userId, username);
			} catch (err: any) {
				console.error(`[Milestones] Error checking comp ${comp.id}:`, err.message);
			}
		}
	} catch (err: any) {
		console.error('[Milestones] Error checking competition milestones:', err.message);
	}
}

async function checkMilestonesForCompetition(
	comp: Competition & { id: string },
	userId: string,
	username: string
): Promise<void> {
	const fullComp = await getCompetition(comp.id);
	if (!fullComp) return;

	const scores = await getUserScores(fullComp);
	const userScore = scores[userId]?.score ?? 0;
	const acceptedUsers = fullComp.users.filter((u: CompetitionUser) => u.invite_status === 'accepted');

	// Race: 50% milestone
	if (fullComp.type === 'race') {
		const halfGoal = fullComp.options.goal / 2;
		const milestoneKey = `milestone_race_50_${fullComp.id}_${userId}`;

		if (userScore >= halfGoal) {
			const alreadySent = await db.query(
				'SELECT id FROM milestone_notifications WHERE milestone_key = $1 LIMIT 1',
				[milestoneKey]
			);

			if (alreadySent.length === 0) {
				await db.query(
					'INSERT INTO milestone_notifications (milestone_key, competition_id, user_id) VALUES ($1, $2, $3)',
					[milestoneKey, fullComp.id, userId]
				);

				// Notify all OTHER participants
				for (const u of acceptedUsers) {
					if (u.user_id === userId) continue;
					const shouldSend = await shouldSendNotification(u.user_id, null, 'competition_milestone');
					if (!shouldSend) continue;

					sendPush(u.user_id, {
						title: 'Race update!',
						body: `${username} is halfway to the finish in ${fullComp.competition_name}!`,
						type: 'competition_milestone',
						data: { competition_id: fullComp.id }
					}).catch(err => console.error('[Push] milestone error:', err.message));
				}
			}
		}
	}

	// Clash/Targets: 1 point from winning
	if ((fullComp.type === 'clash' || fullComp.type === 'targets') && fullComp.options.first_to) {
		const threshold = fullComp.options.first_to - 1;
		const milestoneKey = `milestone_oneaway_${fullComp.id}_${userId}`;

		if (userScore === threshold) {
			const alreadySent = await db.query(
				'SELECT id FROM milestone_notifications WHERE milestone_key = $1 LIMIT 1',
				[milestoneKey]
			);

			if (alreadySent.length === 0) {
				await db.query(
					'INSERT INTO milestone_notifications (milestone_key, competition_id, user_id) VALUES ($1, $2, $3)',
					[milestoneKey, fullComp.id, userId]
				);

				const modeLabel = fullComp.type === 'clash' ? 'win' : 'point';
				for (const u of acceptedUsers) {
					if (u.user_id === userId) continue;
					const shouldSend = await shouldSendNotification(u.user_id, null, 'competition_milestone');
					if (!shouldSend) continue;

					sendPush(u.user_id, {
						title: 'Almost there!',
						body: `${username} is one ${modeLabel} away from winning ${fullComp.competition_name}!`,
						type: 'competition_milestone',
						data: { competition_id: fullComp.id }
					}).catch(err => console.error('[Push] milestone error:', err.message));
				}
			}
		}
	}
}

/**
 * Cron: Check for competitions ending tomorrow and notify participants.
 * Should be called once daily (e.g., at 6 PM ET).
 */
export async function checkCompetitionsEndingSoon(): Promise<void> {
	try {
		const formatter = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/New_York' });
		const today = new Date();
		const tomorrow = new Date(today.getTime() + 24 * 60 * 60 * 1000);
		const tomorrowStr = formatter.format(tomorrow);

		const endingSoon = await db.query<Competition & { id: string }>(
			`SELECT c.*, COALESCE(
				jsonb_agg(
					jsonb_build_object(
						'competition_id', cu.competition_id,
						'user_id', cu.user_id,
						'invite_status', cu.invite_status
					)
				) FILTER (WHERE cu.competition_id IS NOT NULL),
				'[]'::jsonb
			) as users
			FROM competitions c
			LEFT JOIN competition_users cu ON cu.competition_id = c.id
			WHERE c.end_date = $1
				AND c.winner IS NULL
				AND c.start_date IS NOT NULL
				AND c.start_date <= NOW()
			GROUP BY c.id`,
			[tomorrowStr]
		);

		for (const comp of endingSoon) {
			const milestoneKey = `milestone_ending_${comp.id}`;
			const alreadySent = await db.query(
				'SELECT id FROM milestone_notifications WHERE milestone_key = $1 LIMIT 1',
				[milestoneKey]
			);

			if (alreadySent.length > 0) continue;

			await db.query(
				'INSERT INTO milestone_notifications (milestone_key, competition_id) VALUES ($1, $2)',
				[milestoneKey, comp.id]
			);

			const acceptedUsers = comp.users.filter((u: any) => u.invite_status === 'accepted');
			for (const u of acceptedUsers) {
				const shouldSend = await shouldSendNotification(u.user_id, null, 'competition_update');
				if (!shouldSend) continue;

				sendPush(u.user_id, {
					title: 'Last chance!',
					body: `${comp.competition_name} ends tomorrow. Give it everything you've got!`,
					type: 'competition_milestone',
					data: { competition_id: comp.id }
				}).catch(err => console.error('[Push] ending soon error:', err.message));
			}
		}
	} catch (err: any) {
		console.error('[Milestones] Error checking ending soon:', err.message);
	}
}
