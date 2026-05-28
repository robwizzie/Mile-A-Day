import { PostgresService } from './DbService.js';
import { sendPush, sendOrQueueCompetitionNotification } from './pushNotificationService.js';
import { shouldSendNotification, filterRecipientsForNotification } from './notificationSettingsService.js';
import { getCompetition, getCurrentInterval, getUserScores } from './competitionService.js';
import { Competition, CompetitionUser } from '../types/competitions.js';
import { getActiveStreak, getTodayMiles, getTodayStats } from './workoutService.js';

const db = PostgresService.getInstance();

// ─── Format helpers (file-local) ───────────────────────────────────

function formatMiles(miles: number): string {
	return `${miles.toFixed(2)} mi`;
}

function formatDuration(seconds: number): string {
	const s = Math.max(0, Math.round(seconds));
	const h = Math.floor(s / 3600);
	const m = Math.floor((s % 3600) / 60);
	const sec = s % 60;
	const pad = (n: number) => n.toString().padStart(2, '0');
	if (h > 0) return `${h}:${pad(m)}:${pad(sec)}`;
	return `${m}:${pad(sec)}`;
}

function formatPace(secondsPerMile: number): string {
	const s = Math.max(0, Math.round(secondsPerMile));
	const m = Math.floor(s / 60);
	const sec = s % 60;
	return `${m}:${sec.toString().padStart(2, '0')}/mi`;
}

// ─── Workout Completion Notifications ──────────────────────────────

/**
 * Notify friends when a user completes their mile for the day.
 * Only sends once per day per user, and respects friend notification settings.
 * Caps at 5 friend notifications to avoid spam.
 */
export async function notifyFriendsOfMileCompletion(userId: string): Promise<boolean> {
	try {
		// Atomically claim this notification slot (prevents race condition duplicates)
		const today = new Date().toISOString().split('T')[0];
		const claimed = await db.query(
			`INSERT INTO workout_completion_notifications (user_id, notified_date) VALUES ($1, $2)
			ON CONFLICT (user_id, notified_date) DO NOTHING
			RETURNING id`,
			[userId, today]
		);

		if (claimed.length === 0) return false; // Already sent today

		// Get user info
		const [user] = await db.query('SELECT username FROM users WHERE user_id = $1', [userId]);
		if (!user) return false;

		// Friends (bidirectional accepted)
		const friendRows = await db.query<{ friend_id: string }>(
			`SELECT friend_id FROM friendships
			WHERE user_id = $1 AND status = 'accepted'`,
			[userId]
		);

		// Active-competition co-participants (other accepted users in the runner's active comps)
		const compRows = await db.query<{ user_id: string }>(
			`SELECT DISTINCT cu_other.user_id
			FROM competition_users cu_self
			JOIN competition_users cu_other ON cu_other.competition_id = cu_self.competition_id
			JOIN competitions c ON c.id = cu_self.competition_id
			WHERE cu_self.user_id = $1
				AND cu_other.user_id <> $1
				AND cu_self.invite_status = 'accepted'
				AND cu_other.invite_status = 'accepted'
				AND c.start_date IS NOT NULL
				AND c.start_date <= NOW()
				AND c.winner IS NULL
				AND (c.end_date IS NULL OR c.end_date > NOW())`,
			[userId]
		);

		const friendIds = friendRows.map(r => r.friend_id);
		const friendSet = new Set(friendIds);
		const coParticipantIds = compRows.map(r => r.user_id).filter(id => !friendSet.has(id));

		// Cap: up to 5 friends + up to 5 unique co-participants = max 10 recipients
		const recipients = [...friendIds.slice(0, 5), ...coParticipantIds.slice(0, 5)];

		if (recipients.length === 0) return true;

		const title = `${user.username} got their mile in!`;

		// Build a stat-line body. If stats fail or are degenerate, fall back to
		// the generic body so the notification still goes out.
		const FALLBACK_BODY = 'Your friend just completed their daily mile. Time to lace up!';
		let body = FALLBACK_BODY;
		try {
			const stats = await getTodayStats(userId);
			if (stats.miles > 0) {
				const parts = [formatMiles(stats.miles), formatDuration(stats.durationSeconds)];
				if (stats.bestSplitPaceSecMi != null && stats.bestSplitPaceSecMi > 0) {
					parts.push(`best pace ${formatPace(stats.bestSplitPaceSecMi)}`);
				}
				body = parts.join(' · ');
			}
		} catch (err: any) {
			console.error('[Notifications] Error building mile completion stats body, using fallback:', err.message);
		}

		// Pre-filter all recipients in 2 queries instead of 2 per recipient.
		const allowedRecipients = await filterRecipientsForNotification(recipients, userId, 'friend_activity');

		for (const recipientId of allowedRecipients) {
			sendPush(recipientId, {
				title,
				body,
				type: 'friend_activity',
				category: 'FRIEND_ACTIVITY',
				data: { user_id: userId, kind: 'mile_completed' }
			}).catch(err => console.error('[Push] Error sending friend activity:', err.message));
		}

		if (allowedRecipients.length > 0) {
			console.log(`[Notifications] Sent mile completion to ${allowedRecipients.length} recipients of ${user.username}`);
		}
		return true;
	} catch (err: any) {
		console.error('[Notifications] Error notifying friends of mile completion:', err.message);
		return false;
	}
}

/**
 * Notify friends when a user logs an additional run/walk after they've already
 * completed their daily mile. Dedup'd per workout via milestone_notifications.
 */
export async function notifyFriendsOfExtraWorkout(userId: string, workoutId: string): Promise<void> {
	try {
		const [workout] = await db.query<{
			workout_type: string;
			distance: number | string;
			total_duration: number | string;
		}>(
			`SELECT workout_type, distance, total_duration
			FROM workouts
			WHERE user_id = $1 AND workout_id = $2`,
			[userId, workoutId]
		);
		if (!workout) return;

		const type = workout.workout_type;
		if (type !== 'running' && type !== 'walking') return;

		const distance = Number(workout.distance);
		const duration = Number(workout.total_duration);
		if (!(distance > 0)) return;

		// Atomically claim per-workout slot to avoid re-firing on re-upload.
		const milestoneKey = `extra_workout:${workoutId}`;
		const claimed = await db.query(
			`INSERT INTO milestone_notifications (milestone_key, user_id) VALUES ($1, $2)
			ON CONFLICT (milestone_key) DO NOTHING
			RETURNING id`,
			[milestoneKey, userId]
		);
		if (claimed.length === 0) return;

		const [user] = await db.query('SELECT username FROM users WHERE user_id = $1', [userId]);
		if (!user) return;

		// Same recipient pool as mile-completion: friends + active-competition co-participants.
		const friendRows = await db.query<{ friend_id: string }>(
			`SELECT friend_id FROM friendships
			WHERE user_id = $1 AND status = 'accepted'`,
			[userId]
		);
		const compRows = await db.query<{ user_id: string }>(
			`SELECT DISTINCT cu_other.user_id
			FROM competition_users cu_self
			JOIN competition_users cu_other ON cu_other.competition_id = cu_self.competition_id
			JOIN competitions c ON c.id = cu_self.competition_id
			WHERE cu_self.user_id = $1
				AND cu_other.user_id <> $1
				AND cu_self.invite_status = 'accepted'
				AND cu_other.invite_status = 'accepted'
				AND c.start_date IS NOT NULL
				AND c.start_date <= NOW()
				AND c.winner IS NULL
				AND (c.end_date IS NULL OR c.end_date > NOW())`,
			[userId]
		);
		const friendIds = friendRows.map(r => r.friend_id);
		const friendSet = new Set(friendIds);
		const coParticipantIds = compRows.map(r => r.user_id).filter(id => !friendSet.has(id));
		const recipients = [...friendIds.slice(0, 5), ...coParticipantIds.slice(0, 5)];
		if (recipients.length === 0) return;

		// Best pace for THIS workout: min split pace where split is ~full mile,
		// else workout average if the workout itself is ~full mile.
		let bestPace: number | null = null;
		const [paceRow] = await db.query<{ pace: number | string | null }>(
			`SELECT MIN(split_pace) AS pace
			FROM workout_splits
			WHERE workout_id = $1 AND split_distance >= 0.95 AND split_pace > 0`,
			[workoutId]
		);
		if (paceRow?.pace != null) bestPace = Number(paceRow.pace);
		if (bestPace == null && distance >= 0.95 && duration > 0) {
			bestPace = duration / distance;
		}

		const todayMiles = await getTodayMiles(userId);

		const activity = type === 'running' ? 'run' : 'walk';
		const title = `${user.username} completed a ${activity}`;
		const parts = [formatMiles(distance), formatDuration(duration)];
		if (bestPace != null && bestPace > 0) parts.push(`best pace ${formatPace(bestPace)}`);
		if (todayMiles > 0) parts.push(`${formatMiles(Number(todayMiles))} today`);
		const body = parts.join(' · ');

		const allowedRecipients = await filterRecipientsForNotification(recipients, userId, 'friend_activity');
		for (const recipientId of allowedRecipients) {
			sendPush(recipientId, {
				title,
				body,
				type: 'friend_activity',
				category: 'FRIEND_ACTIVITY',
				data: { user_id: userId, kind: 'extra_workout', workout_id: workoutId }
			}).catch(err => console.error('[Push] Error sending extra workout:', err.message));
		}

		if (allowedRecipients.length > 0) {
			console.log(
				`[Notifications] Sent extra workout (${activity}) to ${allowedRecipients.length} recipients of ${user.username}`
			);
		}
	} catch (err: any) {
		console.error('[Notifications] Error notifying friends of extra workout:', err.message);
	}
}

// ─── Competition Milestone Notifications ────────────────────────────

const MAX_MILESTONE_PUSHES_PER_RECIPIENT_PER_TRIGGER = 2;

function tryReserveRecipientSlot(notifiedRecipients: Map<string, number> | undefined, recipientId: string): boolean {
	if (!notifiedRecipients) return true;
	const count = notifiedRecipients.get(recipientId) ?? 0;
	if (count >= MAX_MILESTONE_PUSHES_PER_RECIPIENT_PER_TRIGGER) return false;
	notifiedRecipients.set(recipientId, count + 1);
	return true;
}

/**
 * Check for competition milestones after a workout upload.
 * Milestones:
 * - Race: user reaches 50% of goal
 * - Clash/Targets: user is 1 point from winning (first_to)
 * - Any type: competition ends tomorrow
 *
 * `notifiedRecipients` is shared with sibling checks (e.g. checkLeadChanges) for
 * a single workout-upload trigger so the same recipient is not spammed across
 * multiple shared competitions. Each recipient is capped at
 * MAX_MILESTONE_PUSHES_PER_RECIPIENT_PER_TRIGGER pushes per trigger.
 */
export async function checkCompetitionMilestones(userId: string, notifiedRecipients?: Map<string, number>): Promise<void> {
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
				await checkMilestonesForCompetition(comp, userId, username, notifiedRecipients);
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
	username: string,
	notifiedRecipients?: Map<string, number>
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
			const claimed = await db.query(
				`INSERT INTO milestone_notifications (milestone_key, competition_id, user_id) VALUES ($1, $2, $3)
				ON CONFLICT (milestone_key) DO NOTHING RETURNING id`,
				[milestoneKey, fullComp.id, userId]
			);

			if (claimed.length > 0) {
				for (const u of acceptedUsers) {
					if (u.user_id === userId) continue;
					const shouldSend = await shouldSendNotification(u.user_id, null, 'competition_milestone');
					if (!shouldSend) continue;
					if (!tryReserveRecipientSlot(notifiedRecipients, u.user_id)) continue;

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
			const claimed = await db.query(
				`INSERT INTO milestone_notifications (milestone_key, competition_id, user_id) VALUES ($1, $2, $3)
				ON CONFLICT (milestone_key) DO NOTHING RETURNING id`,
				[milestoneKey, fullComp.id, userId]
			);

			if (claimed.length > 0) {
				const modeLabel = fullComp.type === 'clash' ? 'win' : 'point';
				for (const u of acceptedUsers) {
					if (u.user_id === userId) continue;
					const shouldSend = await shouldSendNotification(u.user_id, null, 'competition_milestone');
					if (!shouldSend) continue;
					if (!tryReserveRecipientSlot(notifiedRecipients, u.user_id)) continue;

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
			const claimed = await db.query(
				`INSERT INTO milestone_notifications (milestone_key, competition_id) VALUES ($1, $2)
				ON CONFLICT (milestone_key) DO NOTHING RETURNING id`,
				[milestoneKey, comp.id]
			);

			if (claimed.length === 0) continue;

			const acceptedUsers = comp.users.filter((u: any) => u.invite_status === 'accepted');
			for (const u of acceptedUsers) {
				const shouldSend = await shouldSendNotification(u.user_id, null, 'competition_milestone');
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

				const milestoneKey = `streak_broken_${user_id}_${yesterdayStr}`;
				const claimed = await db.query(
					`INSERT INTO milestone_notifications (milestone_key, user_id) VALUES ($1, $2)
					ON CONFLICT (milestone_key) DO NOTHING RETURNING id`,
					[milestoneKey, user_id]
				);
				if (claimed.length === 0) continue;

				// Notify their friends
				const friends = await db.query(`SELECT friend_id FROM friendships WHERE user_id = $1 AND status = 'accepted'`, [
					user_id
				]);

				let sentCount = 0;
				for (const { friend_id } of friends) {
					if (sentCount >= 10) break;
					const shouldSend = await shouldSendNotification(friend_id, user_id, 'friend_activity');
					if (!shouldSend) continue;

					sendPush(friend_id, {
						title: 'Streak broken!',
						body: `${username}'s ${streakLength}-day streak just ended. Send them some encouragement!`,
						type: 'friend_activity',
						data: { user_id, kind: 'streak_broken' }
					}).catch(err => console.error('[Push] streak broken error:', err.message));
					sentCount++;
				}

				if (sentCount > 0) {
					console.log(
						`[Notifications] Sent streak broken (${streakLength} days) for ${username} to ${sentCount} friends`
					);
				}
			} catch (err: any) {
				console.error(`[Notifications] Error checking streak broken for ${user_id}:`, err.message);
			}
		}
	} catch (err: any) {
		console.error('[Notifications] Error in checkStreaksBroken:', err.message);
	}
}

// ─── Lead Change Notifications ─────────────────────────────────────

/**
 * Check if a workout upload caused a lead change in any active competition.
 * Only for clash, apex, and race modes where there's a clear leader.
 *
 * Three notification paths fire from this function:
 *   1. Uploader took 1st → "You're in first!" (self) + "X took the lead" (others)
 *   2. Previous 1st-place holder was dethroned by this upload → "X passed you
 *      for 1st" sent to them with the gap distance.
 *   3. (Future) Any user whose rank dropped due to this upload.
 *
 * Path 2 reads each user's previous rank from `competition_users.last_known_rank`,
 * compares to the freshly-computed rank, and notifies any user who went from
 * 1st to anywhere else. Ranks are then written back so the next upload's
 * comparison is fresh.
 *
 * `notifiedRecipients` is shared with sibling checks (e.g. checkCompetitionMilestones)
 * for a single workout-upload trigger so the same recipient is not spammed across
 * multiple shared competitions.
 */
export async function checkLeadChanges(userId: string, notifiedRecipients?: Map<string, number>): Promise<void> {
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
				AND c.type IN ('clash', 'apex', 'race', 'targets')`,
			[userId]
		);

		if (activeComps.length === 0) return;

		const [user] = await db.query('SELECT username FROM users WHERE user_id = $1', [userId]);
		const username = user?.username || 'Someone';

		for (const comp of activeComps) {
			try {
				const fullComp = await getCompetition(comp.id);
				if (!fullComp) continue;

				const acceptedUsers = fullComp.users.filter((u: CompetitionUser) => u.invite_status === 'accepted');
				if (acceptedUsers.length < 2) continue;

				// Snapshot previous (cached) ranks BEFORE we recompute. Users
				// with NULL cache values are treated as "no known prior" — we
				// won't fire dethrone notifications until they've been
				// indexed at least once.
				const cachedRows = await db.query<{
					user_id: string;
					last_known_rank: number | null;
					last_known_score: number | null;
				}>(
					`SELECT user_id, last_known_rank, last_known_score
					FROM competition_users
					WHERE competition_id = $1 AND invite_status = 'accepted'`,
					[comp.id]
				);
				const previousRank = new Map<string, number | null>();
				for (const row of cachedRows) {
					previousRank.set(row.user_id, row.last_known_rank);
				}

				// Compute current scores + ranks.
				const scores = await getUserScores(fullComp);
				const ranked = [...acceptedUsers]
					.map(u => ({
						user_id: u.user_id,
						displayName: (u as any).username || u.user_id,
						score: scores[u.user_id]?.score ?? 0
					}))
					.sort((a, b) => b.score - a.score);

				const newRankByUser = new Map<string, number>();
				const newScoreByUser = new Map<string, number>();
				ranked.forEach((r, idx) => {
					newRankByUser.set(r.user_id, idx + 1);
					newScoreByUser.set(r.user_id, r.score);
				});

				const newLeader = ranked[0];
				const isTied = ranked.length >= 2 && ranked[0].score === ranked[1].score;
				const leaderId = isTied ? null : (newLeader?.user_id ?? null);
				const maxScore = newLeader?.score ?? 0;

				// Per-interval dedup key. For race/apex (no interval option),
				// getCurrentInterval falls through to a daily key — fine, since
				// those comps don't reset and the previousRank guard below
				// prevents re-firing once you're already leading.
				const intervalKey = getCurrentInterval(new Date(), fullComp.options.interval, fullComp.start_date);

				// ── Path 1: uploader just took the lead.
				// Only fire if they weren't already the leader going into this
				// upload — otherwise "you just took the lead" is a lie. NULL
				// prior (never indexed) counts as "not previously leader" so
				// the very first upload can still notify.
				const uploaderPrevRank = previousRank.get(userId);
				const uploaderWasAlreadyLeader = uploaderPrevRank === 1;
				if (leaderId === userId && !isTied && maxScore > 0 && !uploaderWasAlreadyLeader) {
					const milestoneKey = `lead_change_${comp.id}_${userId}_${intervalKey}`;
					const claimed = await db.query(
						`INSERT INTO milestone_notifications (milestone_key, competition_id, user_id) VALUES ($1, $2, $3)
						ON CONFLICT (milestone_key) DO NOTHING RETURNING id`,
						[milestoneKey, comp.id, userId]
					);
					if (claimed.length > 0) {
						for (const u of acceptedUsers) {
							if (u.user_id === userId) continue;
							const shouldSend = await shouldSendNotification(u.user_id, null, 'competition_milestone');
							if (!shouldSend) continue;
							if (!tryReserveRecipientSlot(notifiedRecipients, u.user_id)) continue;

							sendPush(u.user_id, {
								title: 'Lead change!',
								body: `${username} just took the lead in ${fullComp.competition_name}!`,
								type: 'competition_milestone',
								data: { competition_id: fullComp.id }
							}).catch(err => console.error('[Push] lead change error:', err.message));
						}

						sendPush(userId, {
							title: "You're in first!",
							body: `You just took the lead in ${fullComp.competition_name}! Keep it up!`,
							type: 'competition_milestone',
							data: { competition_id: fullComp.id }
						}).catch(err => console.error('[Push] lead self error:', err.message));
					}
				}

				// ── Path 2: someone WAS the leader and isn't anymore.
				// Find users whose cached rank was 1 and whose new rank > 1.
				// In most cases this is exactly one user; we still loop to be
				// safe against odd cached state from a prior tie.
				for (const u of acceptedUsers) {
					const prior = previousRank.get(u.user_id);
					const fresh = newRankByUser.get(u.user_id) ?? acceptedUsers.length;
					if (prior !== 1 || fresh <= 1) continue;
					// Don't notify the user who took the lead themselves.
					if (u.user_id === userId) continue;

					const dethroneKey = `lead_lost_${comp.id}_${u.user_id}_${intervalKey}`;
					const claimed = await db.query(
						`INSERT INTO milestone_notifications (milestone_key, competition_id, user_id) VALUES ($1, $2, $3)
						ON CONFLICT (milestone_key) DO NOTHING RETURNING id`,
						[dethroneKey, comp.id, u.user_id]
					);
					if (claimed.length === 0) continue;

					const shouldSend = await shouldSendNotification(u.user_id, null, 'competition_milestone');
					if (!shouldSend) continue;
					if (!tryReserveRecipientSlot(notifiedRecipients, u.user_id)) continue;

					const newLeaderScore = newScoreByUser.get(leaderId ?? '') ?? 0;
					const myScore = newScoreByUser.get(u.user_id) ?? 0;
					const gap = newLeaderScore - myScore;
					const unitText = formatGapForType(fullComp.type, gap);

					sendPush(u.user_id, {
						title: 'You lost 1st!',
						body: `${username} passed you in ${fullComp.competition_name}. They're ${unitText} ahead — go take it back!`,
						type: 'competition_milestone',
						data: { competition_id: fullComp.id, kind: 'lead_lost' }
					}).catch(err => console.error('[Push] lead lost error:', err.message));
				}

				// ── Persist the new ranks so the next upload's comparison
				// has fresh values. One UPDATE per user; could be batched
				// later if the row count grows.
				for (const [uid, rank] of newRankByUser.entries()) {
					const score = newScoreByUser.get(uid) ?? 0;
					await db.query(
						`UPDATE competition_users
						SET last_known_rank = $1, last_known_score = $2, last_rank_updated_at = NOW()
						WHERE competition_id = $3 AND user_id = $4`,
						[rank, score, comp.id, uid]
					);
				}
			} catch (err: any) {
				console.error(`[Notifications] Lead change error for comp ${comp.id}:`, err.message);
			}
		}
	} catch (err: any) {
		console.error('[Notifications] Error in checkLeadChanges:', err.message);
	}
}

/** Format a score gap for user-facing notification text, mode-aware. */
function formatGapForType(type: string, gap: number): string {
	if (gap <= 0) return '0';
	switch (type) {
		case 'clash':
		case 'targets': {
			const pts = Math.max(1, Math.round(gap));
			return `${pts} ${pts === 1 ? 'pt' : 'pts'}`;
		}
		case 'apex':
		case 'race':
		default:
			return `${gap.toFixed(2)} mi`;
	}
}

// ─── End-of-Interval Per-User Recap Notifications ─────────────────
// These run from the midnight cron. Each function targets one kind of
// per-user event (streak life lost, target missed, interval recap), and
// all use the same `milestone_notifications` table for idempotency.

/** ISO date string for yesterday in America/New_York (matches workouts.local_date format). */
function yesterdayLocalDate(): string {
	const formatter = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/New_York' });
	const y = new Date(Date.now() - 24 * 60 * 60 * 1000);
	return formatter.format(y);
}

/** ISO date string for today in America/New_York. */
function todayLocalDate(): string {
	const formatter = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/New_York' });
	return formatter.format(new Date());
}

/**
 * Cron: detect users in streak competitions who missed yesterday's goal and
 * therefore just lost a life. Sends each affected user a single push per
 * (competition, day) pair. Skipped for users who are already eliminated
 * (remaining_lives <= 0 before yesterday) so we don't keep nagging them.
 *
 * Streaks are independent per user, so no "leader" comparison is needed —
 * we just look at each accepted user's yesterday miles vs the comp goal.
 */
export async function checkStreakLifeLoss(): Promise<void> {
	try {
		const activeStreaks = await db.query<Competition & { id: string }>(
			`SELECT c.*
			FROM competitions c
			WHERE c.type = 'streaks'
				AND c.start_date IS NOT NULL
				AND c.start_date <= NOW()
				AND c.winner IS NULL
				AND (c.end_date IS NULL OR c.end_date > NOW())`
		);

		if (activeStreaks.length === 0) return;
		const yesterday = yesterdayLocalDate();

		for (const comp of activeStreaks) {
			try {
				const fullComp = await getCompetition(comp.id);
				if (!fullComp) continue;
				const goal = fullComp.options.goal ?? 1.0;
				const totalLives = fullComp.options.lives ?? (fullComp.options.first_to > 0 ? fullComp.options.first_to : 0);
				if (totalLives === 0) continue;

				const accepted = fullComp.users.filter((u: CompetitionUser) => u.invite_status === 'accepted');
				if (accepted.length === 0) continue;

				// Per-user yesterday miles via the comp's interval window. For
				// streaks the interval is almost always daily; if not, we map
				// to yesterday's day key directly since getUserScores already
				// includes per-interval breakdowns.
				const scores = await getUserScores(fullComp);

				for (const u of accepted) {
					const remaining = scores[u.user_id]?.remaining_lives ?? totalLives;
					// Skip users who were already out — they don't lose another life.
					if (remaining <= 0) continue;

					const yesterdayMiles = scores[u.user_id]?.intervals?.[yesterday] ?? 0;
					if (yesterdayMiles >= goal) continue; // hit the goal — streak safe

					const livesAfter = Math.max(0, remaining - 1);
					const milestoneKey = `streak_life_lost_${comp.id}_${u.user_id}_${yesterday}`;
					const claimed = await db.query(
						`INSERT INTO milestone_notifications (milestone_key, competition_id, user_id) VALUES ($1, $2, $3)
						ON CONFLICT (milestone_key) DO NOTHING RETURNING id`,
						[milestoneKey, comp.id, u.user_id]
					);
					if (claimed.length === 0) continue;

					const shouldSend = await shouldSendNotification(u.user_id, null, 'competition_milestone');
					if (!shouldSend) continue;

					const title = livesAfter === 0 ? "You're out!" : 'Life lost';
					const body =
						livesAfter === 0
							? `You missed yesterday's mile in ${fullComp.competition_name} and are out of lives.`
							: `You missed yesterday's mile in ${fullComp.competition_name} — ${livesAfter} ${livesAfter === 1 ? 'life' : 'lives'} left.`;

					sendPush(u.user_id, {
						title,
						body,
						type: 'competition_milestone',
						data: { competition_id: comp.id, kind: 'streak_life_lost', lives_remaining: String(livesAfter) }
					}).catch(err => console.error('[Push] streak life lost error:', err.message));
				}
			} catch (err: any) {
				console.error(`[Notifications] Streak life check error for comp ${comp.id}:`, err.message);
			}
		}
	} catch (err: any) {
		console.error('[Notifications] Error in checkStreakLifeLoss:', err.message);
	}
}

/**
 * Cron: detect users in targets competitions who missed the just-ended
 * interval's goal. One push per (user, comp, interval) pair. Daily-interval
 * comps are the primary use case — weekly/monthly fire on their respective
 * rollover days (detected in `intervalJustEnded`).
 */
export async function checkTargetMissed(): Promise<void> {
	try {
		const activeTargets = await db.query<Competition & { id: string }>(
			`SELECT c.*
			FROM competitions c
			WHERE c.type = 'targets'
				AND c.start_date IS NOT NULL
				AND c.start_date <= NOW()
				AND c.winner IS NULL
				AND (c.end_date IS NULL OR c.end_date > NOW())`
		);

		if (activeTargets.length === 0) return;

		for (const comp of activeTargets) {
			try {
				const fullComp = await getCompetition(comp.id);
				if (!fullComp) continue;
				const intervalSetting = fullComp.options.interval ?? 'day';
				if (!intervalJustEnded(intervalSetting, fullComp.start_date)) continue;

				const goal = fullComp.options.goal ?? 1.0;
				const accepted = fullComp.users.filter((u: CompetitionUser) => u.invite_status === 'accepted');
				if (accepted.length === 0) continue;

				const scores = await getUserScores(fullComp);
				const recentKey = lastIntervalKey(intervalSetting, fullComp.start_date);

				// Build the "who hit" list for inclusion in the notification body.
				const hitNames: string[] = [];
				const userMiles: Record<string, number> = {};
				for (const u of accepted) {
					const m = scores[u.user_id]?.intervals?.[recentKey] ?? 0;
					userMiles[u.user_id] = m;
					if (m >= goal) hitNames.push((u as any).username || 'Someone');
				}

				for (const u of accepted) {
					if (userMiles[u.user_id] >= goal) continue;
					const milestoneKey = `target_missed_${comp.id}_${u.user_id}_${recentKey}`;
					const claimed = await db.query(
						`INSERT INTO milestone_notifications (milestone_key, competition_id, user_id) VALUES ($1, $2, $3)
						ON CONFLICT (milestone_key) DO NOTHING RETURNING id`,
						[milestoneKey, comp.id, u.user_id]
					);
					if (claimed.length === 0) continue;

					const shouldSend = await shouldSendNotification(u.user_id, null, 'competition_milestone');
					if (!shouldSend) continue;

					const periodLabel =
						intervalSetting === 'day' ? "yesterday's" : intervalSetting === 'week' ? "last week's" : "last month's";
					const hitBody =
						hitNames.length > 0
							? `${hitNames.slice(0, 3).join(', ')}${hitNames.length > 3 ? ` and ${hitNames.length - 3} more` : ''} hit the target.`
							: 'No one hit the target.';

					sendPush(u.user_id, {
						title: `🎯 Missed ${periodLabel} target`,
						body: `You didn't hit the goal in ${fullComp.competition_name}. ${hitBody}`,
						type: 'competition_milestone',
						data: { competition_id: comp.id, kind: 'target_missed' }
					}).catch(err => console.error('[Push] target missed error:', err.message));
				}
			} catch (err: any) {
				console.error(`[Notifications] Target missed check error for comp ${comp.id}:`, err.message);
			}
		}
	} catch (err: any) {
		console.error('[Notifications] Error in checkTargetMissed:', err.message);
	}
}

/**
 * Cron: end-of-interval recap. Tells each user "yesterday's results are in
 * for X of your competitions" — single grouped push per user covering every
 * comp whose interval just ended.
 *
 * Avoids spam by:
 *   - One milestone_notifications row per (user, day) — never sends twice.
 *   - Only fires for comps where the interval ACTUALLY just ended (daily on
 *     every midnight; weekly on the day after the last day of a week of
 *     comp; monthly on the 1st).
 *
 * Should run AFTER streak/target/lead checks so the user opens the app to
 * a single recap rather than a stream of individual updates.
 */
export async function notifyIntervalResults(): Promise<void> {
	try {
		const activeComps = await db.query<Competition & { id: string }>(
			`SELECT c.*
			FROM competitions c
			WHERE c.start_date IS NOT NULL
				AND c.start_date <= NOW()
				AND c.winner IS NULL
				AND (c.end_date IS NULL OR c.end_date > NOW())`
		);
		if (activeComps.length === 0) return;

		const today = todayLocalDate();
		// Map user_id → list of comp names whose interval just ended for them.
		const recapsByUser = new Map<string, string[]>();
		// Map user_id → first comp_id so the push can deep-link sensibly.
		const firstCompByUser = new Map<string, string>();

		for (const comp of activeComps) {
			const intervalSetting = comp.options?.interval ?? 'day';
			if (!intervalJustEnded(intervalSetting, comp.start_date)) continue;

			const accepted = await db.query<{ user_id: string }>(
				`SELECT user_id FROM competition_users
				WHERE competition_id = $1 AND invite_status = 'accepted'`,
				[comp.id]
			);

			for (const { user_id } of accepted) {
				const list = recapsByUser.get(user_id) ?? [];
				list.push(comp.competition_name);
				recapsByUser.set(user_id, list);
				if (!firstCompByUser.has(user_id)) firstCompByUser.set(user_id, comp.id);
			}
		}

		for (const [userId, compNames] of recapsByUser.entries()) {
			const milestoneKey = `interval_recap_${userId}_${today}`;
			const claimed = await db.query(
				`INSERT INTO milestone_notifications (milestone_key, user_id) VALUES ($1, $2)
				ON CONFLICT (milestone_key) DO NOTHING RETURNING id`,
				[milestoneKey, userId]
			);
			if (claimed.length === 0) continue;

			const shouldSend = await shouldSendNotification(userId, null, 'competition_milestone');
			if (!shouldSend) continue;

			const title = "📊 Yesterday's results are in";
			const body =
				compNames.length === 1
					? `Open ${compNames[0]} to see how everyone finished.`
					: `Results are in for ${compNames.length} of your competitions — see who won.`;

			sendPush(userId, {
				title,
				body,
				type: 'competition_milestone',
				data: {
					kind: 'interval_recap',
					comp_count: String(compNames.length),
					competition_id: firstCompByUser.get(userId) ?? ''
				}
			}).catch(err => console.error('[Push] interval recap error:', err.message));
		}
	} catch (err: any) {
		console.error('[Notifications] Error in notifyIntervalResults:', err.message);
	}
}

/**
 * True when the given interval setting just rolled over between yesterday
 * and today in America/New_York. Daily comps roll every night; weekly comps
 * roll only when yesterday was the last day of a comp-anchored week; monthly
 * comps roll only on the 1st of a calendar month.
 */
function intervalJustEnded(interval: string | undefined, startDate: string | null | undefined): boolean {
	if (interval === 'day' || !interval) return true;

	const formatter = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/New_York' });
	const todayStr = formatter.format(new Date());
	const today = new Date(todayStr + 'T00:00:00Z');

	if (interval === 'month') {
		// today.getUTCDate() reads the day-of-month of an ISO date — for the
		// midnight-ET date string we just built that's the local day-of-month.
		return today.getUTCDate() === 1;
	}

	if (interval === 'week') {
		if (!startDate) return false;
		const start = new Date(startDate);
		const startMs = Date.UTC(start.getUTCFullYear(), start.getUTCMonth(), start.getUTCDate());
		const todayMs = today.getTime();
		const daysSinceStart = Math.round((todayMs - startMs) / (24 * 60 * 60 * 1000));
		// A new week begins every 7 days after the anchor day.
		return daysSinceStart > 0 && daysSinceStart % 7 === 0;
	}

	return false;
}

/**
 * ISO date string for the interval that JUST ended. For daily comps that's
 * yesterday; for weekly/monthly it's the start date of the prior window so
 * it can be looked up in `intervals[]`.
 */
function lastIntervalKey(interval: string | undefined, startDate: string | null | undefined): string {
	if (interval === 'day' || !interval) return yesterdayLocalDate();

	const formatter = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/New_York' });

	if (interval === 'month') {
		const now = new Date();
		const prior = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - 1, 1));
		return formatter.format(prior);
	}

	if (interval === 'week' && startDate) {
		const start = new Date(startDate);
		const startMs = Date.UTC(start.getUTCFullYear(), start.getUTCMonth(), start.getUTCDate());
		const todayStr = formatter.format(new Date());
		const todayMs = new Date(todayStr + 'T00:00:00Z').getTime();
		const daysSinceStart = Math.round((todayMs - startMs) / (24 * 60 * 60 * 1000));
		const priorWeekStartDays = daysSinceStart - 7;
		const priorWeekStartMs = startMs + priorWeekStartDays * 24 * 60 * 60 * 1000;
		return formatter.format(new Date(priorWeekStartMs));
	}

	return yesterdayLocalDate();
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
				const claimed = await db.query(
					`INSERT INTO milestone_notifications (milestone_key, competition_id) VALUES ($1, $2)
					ON CONFLICT (milestone_key) DO NOTHING RETURNING id`,
					[milestoneKey, comp.id]
				);
				if (claimed.length === 0) continue;

				// Get usernames for the tied users
				const tiedNames = await db.query(`SELECT username FROM users WHERE user_id = ANY($1::text[])`, [leaders]);
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
