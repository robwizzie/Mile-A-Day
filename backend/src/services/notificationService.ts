import { PostgresService } from './DbService.js';
import { sendPush, sendOrQueueCompetitionNotification } from './pushNotificationService.js';
import { shouldSendNotification } from './notificationSettingsService.js';
import { getCompetition, getUserScores } from './competitionService.js';
import { Competition, CompetitionUser } from '../types/competitions.js';
import { getActiveStreak, getTodayMiles } from './workoutService.js';

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

// ─── Streak Broken Notifications ──────────────────────────────────

/**
 * Check if a user's streak just broke and notify their friends.
 * Only fires if the previous streak was 10+ days.
 * Called from the midnight cron (checking yesterday's state).
 */
export async function checkStreaksBroken(): Promise<void> {
	try {
		const formatter = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/New_York' });
		const yesterday = new Date(Date.now() - 24 * 60 * 60 * 1000);
		const yesterdayStr = formatter.format(yesterday);

		// Find users who had a workout yesterday-1 but NOT yesterday
		// by checking all users who had an active streak >= 10 that is now broken
		// We look for users whose last qualifying day (>= 0.95 mi) was 2+ days ago
		const brokenStreaks = await db.query(
			`WITH user_streaks AS (
				SELECT
					w.user_id,
					MAX(w.local_date) as last_active_date,
					COUNT(DISTINCT w.local_date) as streak_candidate
				FROM (
					SELECT user_id, local_date, SUM(distance) as day_total
					FROM workouts
					WHERE local_date >= (CURRENT_DATE - INTERVAL '60 days')
					GROUP BY user_id, local_date
					HAVING SUM(distance) >= 0.95
				) w
				GROUP BY w.user_id
			)
			SELECT us.user_id, u.username
			FROM user_streaks us
			JOIN users u ON u.user_id = us.user_id
			WHERE us.last_active_date < $1`,
			[yesterdayStr]
		);

		for (const { user_id, username } of brokenStreaks) {
			try {
				// Get their actual streak count before it broke
				// We need to count consecutive days ending at their last_active_date
				const streakResult = await db.query(
					`WITH daily AS (
						SELECT local_date, SUM(distance) as total
						FROM workouts
						WHERE user_id = $1 AND local_date <= $2
						GROUP BY local_date
						HAVING SUM(distance) >= 0.95
						ORDER BY local_date DESC
					),
					numbered AS (
						SELECT local_date,
							local_date - (ROW_NUMBER() OVER (ORDER BY local_date DESC))::int AS grp
						FROM daily
					)
					SELECT COUNT(*) as streak_length
					FROM numbered
					WHERE grp = (SELECT grp FROM numbered LIMIT 1)`,
					[user_id, yesterdayStr]
				);

				const streakLength = parseInt(streakResult[0]?.streak_length ?? '0');
				if (streakLength < 10) continue;

				// Check if we already sent this notification
				const milestoneKey = `streak_broken_${user_id}_${yesterdayStr}`;
				const alreadySent = await db.query(
					'SELECT id FROM milestone_notifications WHERE milestone_key = $1 LIMIT 1',
					[milestoneKey]
				);
				if (alreadySent.length > 0) continue;

				await db.query(
					'INSERT INTO milestone_notifications (milestone_key, user_id) VALUES ($1, $2)',
					[milestoneKey, user_id]
				);

				// Notify their friends
				const friends = await db.query(
					`SELECT friend_id FROM friendships WHERE user_id = $1 AND status = 'accepted'`,
					[user_id]
				);

				let sentCount = 0;
				for (const { friend_id } of friends) {
					if (sentCount >= 10) break;
					const shouldSend = await shouldSendNotification(friend_id, user_id, 'friend_activity');
					if (!shouldSend) continue;

					sendPush(friend_id, {
						title: 'Streak broken!',
						body: `${username}'s ${streakLength}-day streak just ended. Send them some encouragement!`,
						type: 'friend_activity',
						data: { user_id }
					}).catch(err => console.error('[Push] streak broken error:', err.message));
					sentCount++;
				}

				if (sentCount > 0) {
					console.log(`[Notifications] Sent streak broken (${streakLength} days) for ${username} to ${sentCount} friends`);
				}
			} catch (err: any) {
				console.error(`[Notifications] Error checking streak broken for ${user_id}:`, err.message);
			}
		}
	} catch (err: any) {
		console.error('[Notifications] Error in checkStreaksBroken:', err.message);
	}
}

// ─── Personal Best in Competition ──────────────────────────────────

/**
 * Check if a user just set a personal best single-day distance
 * in any of their active competitions. Called after workout upload.
 */
export async function checkPersonalBest(userId: string): Promise<void> {
	try {
		const formatter = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/New_York' });
		const today = formatter.format(new Date());

		// Get today's total distance
		const todayResult = await db.query(
			`SELECT SUM(distance) as total FROM workouts WHERE user_id = $1 AND local_date = $2`,
			[userId, today]
		);
		const todayDistance = parseFloat(todayResult[0]?.total ?? '0');
		if (todayDistance <= 0) return;

		// Get active competitions for user
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
				// Get user's best single-day distance in this competition (excluding today)
				const bestResult = await db.query(
					`SELECT MAX(day_total) as best
					FROM (
						SELECT SUM(distance) as day_total
						FROM workouts
						WHERE user_id = $1 AND local_date >= $2 AND local_date < $3
						GROUP BY local_date
					) daily`,
					[userId, comp.start_date, today]
				);

				const previousBest = parseFloat(bestResult[0]?.best ?? '0');
				if (previousBest <= 0 || todayDistance <= previousBest) continue;

				const milestoneKey = `pb_${comp.id}_${userId}_${today}`;
				const alreadySent = await db.query(
					'SELECT id FROM milestone_notifications WHERE milestone_key = $1 LIMIT 1',
					[milestoneKey]
				);
				if (alreadySent.length > 0) continue;

				await db.query(
					'INSERT INTO milestone_notifications (milestone_key, competition_id, user_id) VALUES ($1, $2, $3)',
					[milestoneKey, comp.id, userId]
				);

				const fullComp = await getCompetition(comp.id);
				if (!fullComp) continue;

				const acceptedUsers = fullComp.users.filter((u: CompetitionUser) => u.invite_status === 'accepted');
				for (const u of acceptedUsers) {
					if (u.user_id === userId) continue;
					const shouldSend = await shouldSendNotification(u.user_id, userId, 'competition_milestone');
					if (!shouldSend) continue;

					sendPush(u.user_id, {
						title: 'New personal best!',
						body: `${username} just set a new PB of ${todayDistance.toFixed(1)} mi in ${fullComp.competition_name}!`,
						type: 'competition_milestone',
						data: { competition_id: fullComp.id }
					}).catch(err => console.error('[Push] PB error:', err.message));
				}
			} catch (err: any) {
				console.error(`[Notifications] PB check error for comp ${comp.id}:`, err.message);
			}
		}
	} catch (err: any) {
		console.error('[Notifications] Error in checkPersonalBest:', err.message);
	}
}

// ─── Lead Change Notifications ─────────────────────────────────────

/**
 * Check if a workout upload caused a lead change in any active competition.
 * Only for clash, apex, and race modes where there's a clear leader.
 */
export async function checkLeadChanges(userId: string): Promise<void> {
	try {
		const activeComps = await db.query<Competition & { id: string }>(
			`SELECT c.*
			FROM competitions c
			JOIN competition_users cu ON cu.competition_id = c.id
			WHERE cu.user_id = $1
				AND cu.invite_status = 'accepted'
				AND c.start_date IS NOT NULL
				AND c.start_date <= NOW()
				AND c.winner IS NULL
				AND (c.end_date IS NULL OR c.end_date > NOW())
				AND c.type IN ('clash', 'apex', 'race')`,
			[userId]
		);

		if (activeComps.length === 0) return;

		const [user] = await db.query('SELECT username FROM users WHERE user_id = $1', [userId]);
		const username = user?.username || 'Someone';

		const formatter = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/New_York' });
		const today = formatter.format(new Date());

		for (const comp of activeComps) {
			try {
				const fullComp = await getCompetition(comp.id);
				if (!fullComp) continue;

				const scores = await getUserScores(fullComp);
				const acceptedUsers = fullComp.users.filter((u: CompetitionUser) => u.invite_status === 'accepted');
				if (acceptedUsers.length < 2) continue;

				// Find the current leader
				let maxScore = -1;
				let leaderId: string | null = null;
				let isTied = false;

				for (const u of acceptedUsers) {
					const score = scores[u.user_id]?.score ?? 0;
					if (score > maxScore) {
						maxScore = score;
						leaderId = u.user_id;
						isTied = false;
					} else if (score === maxScore) {
						isTied = true;
					}
				}

				// Only notify if this user just took the lead (not tied)
				if (leaderId !== userId || isTied || maxScore <= 0) continue;

				const milestoneKey = `lead_change_${comp.id}_${userId}_${today}`;
				const alreadySent = await db.query(
					'SELECT id FROM milestone_notifications WHERE milestone_key = $1 LIMIT 1',
					[milestoneKey]
				);
				if (alreadySent.length > 0) continue;

				await db.query(
					'INSERT INTO milestone_notifications (milestone_key, competition_id, user_id) VALUES ($1, $2, $3)',
					[milestoneKey, comp.id, userId]
				);

				// Notify all other participants
				for (const u of acceptedUsers) {
					if (u.user_id === userId) continue;
					const shouldSend = await shouldSendNotification(u.user_id, null, 'competition_milestone');
					if (!shouldSend) continue;

					sendPush(u.user_id, {
						title: 'Lead change!',
						body: `${username} just took the lead in ${fullComp.competition_name}!`,
						type: 'competition_milestone',
						data: { competition_id: fullComp.id }
					}).catch(err => console.error('[Push] lead change error:', err.message));
				}

				// Also notify the user who took the lead
				sendPush(userId, {
					title: "You're in first!",
					body: `You just took the lead in ${fullComp.competition_name}! Keep it up!`,
					type: 'competition_milestone',
					data: { competition_id: fullComp.id }
				}).catch(err => console.error('[Push] lead self error:', err.message));
			} catch (err: any) {
				console.error(`[Notifications] Lead change error for comp ${comp.id}:`, err.message);
			}
		}
	} catch (err: any) {
		console.error('[Notifications] Error in checkLeadChanges:', err.message);
	}
}

// ─── End-of-Day Tie Detection (Clash Mode) ─────────────────────────

/**
 * Check for ties at end of day in clash competitions.
 * Called by cron at end of day (11:55 PM ET).
 */
export async function checkClashTies(): Promise<void> {
	try {
		const activeClash = await db.query<Competition & { id: string }>(
			`SELECT c.*
			FROM competitions c
			WHERE c.type = 'clash'
				AND c.start_date IS NOT NULL
				AND c.start_date <= NOW()
				AND c.winner IS NULL
				AND (c.end_date IS NULL OR c.end_date > NOW())`
		);

		const formatter = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/New_York' });
		const today = formatter.format(new Date());

		for (const comp of activeClash) {
			try {
				const fullComp = await getCompetition(comp.id);
				if (!fullComp) continue;

				const scores = await getUserScores(fullComp);
				const acceptedUsers = fullComp.users.filter((u: CompetitionUser) => u.invite_status === 'accepted');
				if (acceptedUsers.length < 2) continue;

				// Find users tied for the lead
				let maxScore = -1;
				const leaders: string[] = [];

				for (const u of acceptedUsers) {
					const score = scores[u.user_id]?.score ?? 0;
					if (score > maxScore) {
						maxScore = score;
						leaders.length = 0;
						leaders.push(u.user_id);
					} else if (score === maxScore) {
						leaders.push(u.user_id);
					}
				}

				if (leaders.length < 2 || maxScore <= 0) continue;

				const milestoneKey = `clash_tie_${comp.id}_${today}`;
				const alreadySent = await db.query(
					'SELECT id FROM milestone_notifications WHERE milestone_key = $1 LIMIT 1',
					[milestoneKey]
				);
				if (alreadySent.length > 0) continue;

				await db.query(
					'INSERT INTO milestone_notifications (milestone_key, competition_id) VALUES ($1, $2)',
					[milestoneKey, comp.id]
				);

				// Get usernames for the tied users
				const tiedNames = await db.query(
					`SELECT username FROM users WHERE user_id = ANY($1::text[])`,
					[leaders]
				);
				const nameList = tiedNames.map((r: any) => r.username).join(' & ');

				// Notify all accepted participants
				for (const u of acceptedUsers) {
					const shouldSend = await shouldSendNotification(u.user_id, null, 'competition_milestone');
					if (!shouldSend) continue;

					sendPush(u.user_id, {
						title: "It's a tie!",
						body: `${nameList} are tied at ${maxScore} ${maxScore === 1 ? 'win' : 'wins'} in ${fullComp.competition_name}!`,
						type: 'competition_milestone',
						data: { competition_id: fullComp.id }
					}).catch(err => console.error('[Push] tie error:', err.message));
				}
			} catch (err: any) {
				console.error(`[Notifications] Tie check error for comp ${comp.id}:`, err.message);
			}
		}
	} catch (err: any) {
		console.error('[Notifications] Error in checkClashTies:', err.message);
	}
}
