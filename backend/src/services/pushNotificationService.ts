import { PostgresService } from './DbService.js';
import { getNotificationPreferences, shouldSendNotification } from './notificationSettingsService.js';
import { hasUnlimitedActions } from './privilegedUsers.js';
import { START_OF_TODAY_ET_SQL } from './dailyResetTime.js';
import fs from 'fs';
import path from 'path';
import http2 from 'http2';
import jwt from 'jsonwebtoken';

const db = PostgresService.getInstance();

// APNs Configuration
const APNS_KEY_PATH = process.env.APNS_KEY_PATH;
const APNS_KEY = process.env.APNS_KEY; // Key contents directly (for Coolify/cloud)
const APNS_KEY_ID = process.env.APNS_KEY_ID;
const APNS_TEAM_ID = process.env.APNS_TEAM_ID;
const APNS_BUNDLE_ID = process.env.APNS_BUNDLE_ID;
const APNS_PRODUCTION = process.env.APNS_PRODUCTION === 'true';
const APNS_HOST = APNS_PRODUCTION ? 'https://api.push.apple.com' : 'https://api.sandbox.push.apple.com';

let apnsKey: string | null = null;
let apnsToken: string | null = null;
let apnsTokenExpiry = 0;

function loadApnsKey(): string | null {
	if (apnsKey) return apnsKey;

	// Option 1: Key contents passed directly via env var (for Coolify/cloud)
	if (APNS_KEY) {
		let raw = APNS_KEY.replace(/\\n/g, '').replace(/\s/g, '');
		// Strip PEM headers if present, then re-add them
		raw = raw.replace(/-----BEGIN PRIVATE KEY-----/g, '').replace(/-----END PRIVATE KEY-----/g, '');
		apnsKey = `-----BEGIN PRIVATE KEY-----\n${raw}\n-----END PRIVATE KEY-----\n`;
		return apnsKey;
	}

	// Option 2: Key file path (for local dev)
	if (!APNS_KEY_PATH) {
		console.warn('[Push] APNS_KEY or APNS_KEY_PATH not configured — push notifications disabled');
		return null;
	}
	try {
		const keyPath = path.isAbsolute(APNS_KEY_PATH) ? APNS_KEY_PATH : path.join(process.cwd(), APNS_KEY_PATH);
		apnsKey = fs.readFileSync(keyPath, 'utf8');
		return apnsKey;
	} catch (err: any) {
		console.error('[Push] Failed to load APNs key:', err.message);
		return null;
	}
}

function getApnsToken(): string | null {
	const key = loadApnsKey();
	if (!key || !APNS_KEY_ID || !APNS_TEAM_ID) return null;

	const now = Math.floor(Date.now() / 1000);
	// Refresh token every 50 minutes (APNs tokens valid for 60 min)
	if (apnsToken && now < apnsTokenExpiry) return apnsToken;

	apnsToken = jwt.sign({}, key, {
		algorithm: 'ES256',
		keyid: APNS_KEY_ID,
		issuer: APNS_TEAM_ID,
		expiresIn: '1h'
	});
	apnsTokenExpiry = now + 50 * 60;
	return apnsToken;
}

export type NotificationType =
	| 'friend_request'
	| 'friend_request_accepted'
	| 'friend_nudge'
	| 'friend_activity'
	| 'competition_invite'
	| 'competition_accepted'
	| 'competition_started'
	| 'competition_finished'
	| 'competition_updates'
	| 'competition_nudge'
	| 'competition_flex'
	| 'competition_milestone'
	| 'streak_broken'
	| 'personal_best'
	| 'friend_personal_best'
	| 'lead_change'
	| 'clash_tie'
	| 'badge_earned'
	| 'friend_badge_earned'
	| 'friend_challenge_completed'
	| 'hype_received';

interface PushPayload {
	title: string;
	body: string;
	type: NotificationType;
	data?: Record<string, string>;
	category?: string;
}

// Send a push notification to a single device token via HTTP/2
function sendToDevice(deviceToken: string, payload: PushPayload): Promise<boolean> {
	return new Promise(resolve => {
		const token = getApnsToken();
		if (!token || !APNS_BUNDLE_ID) {
			console.warn('[Push] APNs not configured, skipping push');
			resolve(false);
			return;
		}

		const aps: Record<string, any> = {
			'alert': { title: payload.title, body: payload.body },
			'sound': 'default',
			'mutable-content': 1
		};
		if (payload.category) aps.category = payload.category;

		const apnsPayload = JSON.stringify({
			aps,
			type: payload.type,
			data: payload.data ?? {}
		});

		const client = http2.connect(APNS_HOST);

		client.on('error', err => {
			console.error('[Push] HTTP/2 connection error:', err.message);
			client.close();
			resolve(false);
		});

		const req = client.request({
			':method': 'POST',
			':path': `/3/device/${deviceToken}`,
			'authorization': `bearer ${token}`,
			'apns-topic': APNS_BUNDLE_ID,
			'apns-push-type': 'alert',
			'apns-priority': '10',
			'content-type': 'application/json'
		});

		let responseData = '';
		let statusCode = 0;

		req.on('response', headers => {
			statusCode = headers[':status'] as number;
		});

		req.on('data', chunk => {
			responseData += chunk;
		});

		req.on('end', () => {
			client.close();
			if (statusCode === 200) {
				resolve(true);
			} else {
				console.error(`[Push] APNs error ${statusCode}: ${responseData}`);
				// If token is invalid, remove it
				if (statusCode === 410 || (statusCode === 400 && responseData.includes('BadDeviceToken'))) {
					removeInvalidToken(deviceToken).catch(() => {});
				}
				resolve(false);
			}
		});

		req.on('error', err => {
			console.error('[Push] Request error:', err.message);
			client.close();
			resolve(false);
		});

		req.write(apnsPayload);
		req.end();
	});
}

async function removeInvalidToken(deviceToken: string): Promise<void> {
	await db.query('DELETE FROM device_tokens WHERE device_token = $1', [deviceToken]);
	console.log(`[Push] Removed invalid device token: ${deviceToken.substring(0, 8)}...`);
}

// ─── Smart Throttling ───────────────────────────────────────────────

const DAILY_NOTIFICATION_CAP = 18;

// High-priority types bypass throttling
const HIGH_PRIORITY_TYPES: NotificationType[] = [
	'friend_request',
	'competition_invite',
	'competition_started',
	'competition_finished',
	// Flexes are time-of-day specific (you flexed because you're winning *now*);
	// queueing them past quiet hours / daily cap delivers stale taunts.
	'competition_flex'
];

async function getDailyNotificationCount(userId: string): Promise<number> {
	const result = await db.query(
		`SELECT COUNT(*) as count FROM notification_log
		WHERE user_id = $1 AND created_at > CURRENT_DATE`,
		[userId]
	);
	return parseInt(result[0]?.count ?? '0');
}

async function logNotificationSent(userId: string, type: NotificationType): Promise<void> {
	await db.query('INSERT INTO notification_log (user_id, type) VALUES ($1, $2)', [userId, type]);
}

async function isUserInQuietHours(userId: string): Promise<boolean> {
	const prefs = await getNotificationPreferences(userId);
	if (prefs.quiet_hours_start === null || prefs.quiet_hours_end === null) return false;

	const now = new Date();
	const etHour = parseInt(
		new Intl.DateTimeFormat('en-US', { timeZone: 'America/New_York', hour: 'numeric', hour12: false }).format(now)
	);

	if (prefs.quiet_hours_start > prefs.quiet_hours_end) {
		// Spans midnight (e.g., 22 to 8)
		return etHour >= prefs.quiet_hours_start || etHour < prefs.quiet_hours_end;
	}
	return etHour >= prefs.quiet_hours_start && etHour < prefs.quiet_hours_end;
}

// ─── Public API ──────────────────────────────────────────────────────

export async function sendPush(userId: string, payload: PushPayload): Promise<void> {
	// Check user's custom quiet hours
	if (!HIGH_PRIORITY_TYPES.includes(payload.type)) {
		const inQuiet = await isUserInQuietHours(userId);
		if (inQuiet) {
			console.log(`[Push] Quiet hours for user ${userId}, queueing "${payload.type}"`);
			await db.query(
				`INSERT INTO pending_notifications (user_id, type, competition_id, competition_name)
				VALUES ($1, $2, $3, $4)`,
				[userId, payload.type, payload.data?.competition_id ?? null, payload.title]
			);
			await logNotificationSent(userId, payload.type);
			// Still store in inbox so user can see it later
			storeInAppNotification(userId, payload).catch(err =>
				console.error('[Push] Error storing in-app notification:', err.message)
			);
			return;
		}

		// Smart throttling: check daily cap
		const dailyCount = await getDailyNotificationCount(userId);
		if (dailyCount >= DAILY_NOTIFICATION_CAP) {
			console.log(`[Push] Throttled "${payload.type}" for user ${userId} (${dailyCount}/${DAILY_NOTIFICATION_CAP} today)`);
			await db.query(
				`INSERT INTO pending_notifications (user_id, type, competition_id, competition_name)
				VALUES ($1, $2, $3, $4)`,
				[userId, payload.type, payload.data?.competition_id ?? null, payload.title]
			);
			await logNotificationSent(userId, payload.type);
			// Still store in inbox
			storeInAppNotification(userId, payload).catch(err =>
				console.error('[Push] Error storing in-app notification:', err.message)
			);
			return;
		}
	}

	const tokens = await db.query<{ device_token: string }>('SELECT device_token FROM device_tokens WHERE user_id = $1', [
		userId
	]);

	if (tokens.length === 0) {
		console.log(`[Push] No device tokens found for user ${userId}`);
		// Still store in inbox even without device tokens
		storeInAppNotification(userId, payload).catch(err =>
			console.error('[Push] Error storing in-app notification:', err.message)
		);
		return;
	}

	const results = await Promise.all(tokens.map(({ device_token }) => sendToDevice(device_token, payload)));

	const sent = results.filter(Boolean).length;
	if (sent > 0) {
		await logNotificationSent(userId, payload.type);
		console.log(`[Push] Sent "${payload.type}" to user ${userId} (${sent}/${tokens.length} devices)`);
	}

	// Always store in-app notification regardless of push delivery
	storeInAppNotification(userId, payload).catch(err => console.error('[Push] Error storing in-app notification:', err.message));
}

async function storeInAppNotification(userId: string, payload: PushPayload): Promise<void> {
	await db.query(
		`INSERT INTO in_app_notifications (user_id, title, body, type, data)
		VALUES ($1, $2, $3, $4, $5)`,
		[userId, payload.title, payload.body, payload.type, JSON.stringify(payload.data ?? {})]
	);
}

export async function registerDeviceToken(userId: string, deviceToken: string): Promise<void> {
	await db.query(
		`INSERT INTO device_tokens (user_id, device_token)
		VALUES ($1, $2)
		ON CONFLICT (user_id, device_token)
		DO UPDATE SET updated_at = NOW()`,
		[userId, deviceToken]
	);
}

export async function unregisterDeviceToken(userId: string, deviceToken: string): Promise<void> {
	await db.query('DELETE FROM device_tokens WHERE user_id = $1 AND device_token = $2', [userId, deviceToken]);
}

// ─── Silent (background) pushes ─────────────────────────────────────

/**
 * APNs silent push. Wakes the app to do background work; renders nothing.
 * Do not call directly — use sendSilentPushToUser.
 */
function sendSilentPushToDevice(deviceToken: string, type: string, data: Record<string, string> = {}): Promise<boolean> {
	return new Promise(resolve => {
		const token = getApnsToken();
		if (!token || !APNS_BUNDLE_ID) {
			console.warn('[Push] APNs not configured, skipping silent push');
			resolve(false);
			return;
		}

		const apnsPayload = JSON.stringify({
			aps: { 'content-available': 1 },
			type,
			data
		});

		const client = http2.connect(APNS_HOST);

		client.on('error', err => {
			console.error('[Push] Silent HTTP/2 connection error:', err.message);
			client.close();
			resolve(false);
		});

		const req = client.request({
			':method': 'POST',
			':path': `/3/device/${deviceToken}`,
			'authorization': `bearer ${token}`,
			'apns-topic': APNS_BUNDLE_ID,
			'apns-push-type': 'background',
			'apns-priority': '5',
			'content-type': 'application/json'
		});

		let responseData = '';
		let statusCode = 0;

		req.on('response', headers => {
			statusCode = headers[':status'] as number;
		});

		req.on('data', chunk => {
			responseData += chunk;
		});

		req.on('end', () => {
			client.close();
			if (statusCode === 200) {
				resolve(true);
			} else {
				console.error(`[Push] Silent APNs error ${statusCode}: ${responseData}`);
				if (statusCode === 410 || (statusCode === 400 && responseData.includes('BadDeviceToken'))) {
					removeInvalidToken(deviceToken).catch(() => {});
				}
				resolve(false);
			}
		});

		req.on('error', err => {
			console.error('[Push] Silent request error:', err.message);
			client.close();
			resolve(false);
		});

		req.write(apnsPayload);
		req.end();
	});
}

/**
 * Send a silent (content-available) push to every registered device of a user.
 * Skips throttling, quiet hours, in-app inbox storage, and notification_log writes.
 * These pushes are invisible to the user and have no per-day cap concern.
 */
export async function sendSilentPushToUser(userId: string, type: string, data: Record<string, string> = {}): Promise<number> {
	const tokens = await db.query<{ device_token: string }>('SELECT device_token FROM device_tokens WHERE user_id = $1', [
		userId
	]);
	if (tokens.length === 0) return 0;

	const results = await Promise.all(tokens.map(({ device_token }) => sendSilentPushToDevice(device_token, type, data)));
	return results.filter(Boolean).length;
}

// ─── Quiet Hours & Batching ──────────────────────────────────────────

function isQuietHours(): boolean {
	const now = new Date();
	const etHour = parseInt(
		new Intl.DateTimeFormat('en-US', { timeZone: 'America/New_York', hour: 'numeric', hour12: false }).format(now)
	);
	// Quiet hours: 10 PM (22) through 9:59 AM (9)
	return etHour >= 22 || etHour < 10;
}

export async function sendOrQueueCompetitionNotification(
	userId: string,
	type: 'competition_started' | 'competition_finished',
	competitionId: string,
	competitionName: string
): Promise<void> {
	if (isQuietHours()) {
		await db.query(
			`INSERT INTO pending_notifications (user_id, type, competition_id, competition_name)
			VALUES ($1, $2, $3, $4)`,
			[userId, type, competitionId, competitionName]
		);
	} else {
		const title = type === 'competition_started' ? 'Competition started' : 'Competition finished';
		const body = type === 'competition_started' ? `${competitionName} has begun!` : `${competitionName} has finished!`;
		await sendPush(userId, { title, body, type, data: { competition_id: competitionId } });
	}
}

interface PendingNotification {
	id: string;
	user_id: string;
	type: string;
	competition_id: string;
	competition_name: string;
}

export async function flushBatchedNotifications(): Promise<void> {
	const pending = await db.query<PendingNotification>(
		`SELECT id, user_id, type, competition_id, competition_name
		FROM pending_notifications
		WHERE sent_at IS NULL
		ORDER BY user_id, created_at`
	);

	if (pending.length === 0) return;

	// Group by user
	const byUser: Record<string, PendingNotification[]> = {};
	for (const row of pending) {
		if (!byUser[row.user_id]) byUser[row.user_id] = [];
		byUser[row.user_id].push(row);
	}

	for (const [userId, notifications] of Object.entries(byUser)) {
		const compNotifs = notifications.filter(n => n.type === 'competition_started' || n.type === 'competition_finished');
		const otherNotifs = notifications.filter(n => n.type !== 'competition_started' && n.type !== 'competition_finished');

		// Handle competition start/finish notifications (batch into digest)
		if (compNotifs.length > 0) {
			const starts = compNotifs.filter(n => n.type === 'competition_started');
			const finishes = compNotifs.filter(n => n.type === 'competition_finished');

			let title: string;
			let body: string;
			let type: NotificationType;

			if (starts.length > 0 && finishes.length > 0) {
				title = 'Competition updates';
				body = 'You have several updates to your competitions — open to check in';
				type = 'competition_updates';
			} else if (starts.length === 1) {
				title = 'Competition started';
				body = `${starts[0].competition_name} has begun!`;
				type = 'competition_started';
			} else if (starts.length > 1) {
				title = 'Competitions started';
				body = 'Multiple competitions have started — open to check in';
				type = 'competition_started';
			} else if (finishes.length === 1) {
				title = 'Competition finished';
				body = `${finishes[0].competition_name} has finished!`;
				type = 'competition_finished';
			} else {
				title = 'Competitions finished';
				body = 'Multiple competitions have finished — open to check in';
				type = 'competition_finished';
			}

			await sendPush(userId, { title, body, type });
		}

		// Handle other throttled notifications (send digest summary)
		if (otherNotifs.length > 0) {
			if (otherNotifs.length === 1) {
				// Single throttled notification: send it directly
				const n = otherNotifs[0];
				await sendPush(userId, {
					title: n.competition_name || 'Notification', // competition_name stores the original title
					body: `You have a notification you missed`,
					type: (n.type as NotificationType) || 'competition_updates'
				});
			} else {
				// Multiple: send digest
				await sendPush(userId, {
					title: 'Catch up on activity',
					body: `You have ${otherNotifs.length} notifications from while you were away`,
					type: 'competition_updates'
				});
			}
		}
	}

	// Mark all as sent
	const ids = pending.map(n => n.id);
	await db.query(`UPDATE pending_notifications SET sent_at = NOW() WHERE id = ANY($1::uuid[])`, [ids]);

	console.log(`[Push] Flushed ${pending.length} batched notifications for ${Object.keys(byUser).length} users`);
}

// ─── Nudge Rate Limiting ─────────────────────────────────────────────

export async function canNudge(competitionId: string, senderId: string, targetId: string): Promise<boolean> {
	if (hasUnlimitedActions(senderId)) return true;
	const result = await db.query(
		`SELECT id FROM nudge_log
		WHERE competition_id = $1 AND sender_id = $2 AND target_id = $3
			AND created_at >= ${START_OF_TODAY_ET_SQL}
		LIMIT 1`,
		[competitionId, senderId, targetId]
	);
	return result.length === 0;
}

export async function logNudge(competitionId: string, senderId: string, targetId: string): Promise<void> {
	await db.query(`INSERT INTO nudge_log (competition_id, sender_id, target_id) VALUES ($1, $2, $3)`, [
		competitionId,
		senderId,
		targetId
	]);
}

// ─── Friend Nudge Rate Limiting ─────────────────────────────────────

export async function canFriendNudge(senderId: string, targetId: string): Promise<boolean> {
	if (hasUnlimitedActions(senderId)) return true;
	const result = await db.query(
		`SELECT id FROM friend_nudge_log
		WHERE sender_id = $1 AND target_id = $2
			AND created_at >= ${START_OF_TODAY_ET_SQL}
		LIMIT 1`,
		[senderId, targetId]
	);
	return result.length === 0;
}

export async function logFriendNudge(senderId: string, targetId: string): Promise<void> {
	await db.query(`INSERT INTO friend_nudge_log (sender_id, target_id) VALUES ($1, $2)`, [senderId, targetId]);
}

// ─── Flex Rate Limiting (per sender→target per day, across all competitions) ──

export async function canFlex(senderId: string, targetId: string): Promise<boolean> {
	if (hasUnlimitedActions(senderId)) return true;
	const result = await db.query(
		`SELECT id FROM flex_log
		WHERE sender_id = $1 AND target_id = $2
			AND created_at >= ${START_OF_TODAY_ET_SQL}
		LIMIT 1`,
		[senderId, targetId]
	);
	return result.length === 0;
}

export async function logFlex(senderId: string, targetId: string, competitionId: string, message: string | null): Promise<void> {
	await db.query(`INSERT INTO flex_log (sender_id, target_id, competition_id, message) VALUES ($1, $2, $3, $4)`, [
		senderId,
		targetId,
		competitionId,
		message
	]);
}

// ─── Badges & Challenges ────────────────────────────────────────────

interface BadgeEarnedPayload {
	badgeId: string;
	name: string;
	description: string;
	rarity: 'common' | 'rare' | 'legendary';
	icon: string;
}

interface ChallengeCompletedPayload {
	localDate: string;
	challengeKey: string;
	challengeTitle: string;
}

/**
 * Push the user themselves when they earn a new badge.
 */
export async function fireBadgeEarnedPush(userId: string, badge: BadgeEarnedPayload): Promise<void> {
	await sendPush(userId, {
		title: '🏅 Medal Unlocked',
		body: `${badge.name} — ${badge.description}`,
		type: 'badge_earned',
		data: {
			badge_id: badge.badgeId,
			rarity: badge.rarity,
			icon: badge.icon
		}
	});
}

/**
 * Fan out a rare+ badge to every accepted friend. Throttled 1/hour per (sender, recipient).
 */
export async function fanOutFriendBadgePush(senderId: string, badge: BadgeEarnedPayload): Promise<void> {
	const friendIds = await getAcceptedFriendIds(senderId);
	if (friendIds.length === 0) return;
	const sender = await getSenderDisplayName(senderId);

	for (const friendId of friendIds) {
		const okToPush = await passesFriendBadgeThrottle(senderId, friendId);
		if (!okToPush) continue;

		sendPush(friendId, {
			title: `${sender} earned a medal`,
			body: `${badge.name} — ${badge.rarity}`,
			type: 'friend_badge_earned',
			data: {
				sender_id: senderId,
				badge_id: badge.badgeId,
				badge_name: badge.name,
				rarity: badge.rarity
			}
		}).catch(err => console.error('[Push] friend_badge_earned send failed:', err.message));
	}
}

function formatPersonalBestBody(prType: 'fastest_mile' | 'most_miles_day', newValue: number): string {
	if (prType === 'fastest_mile') {
		const totalSeconds = Math.round(newValue);
		const minutes = Math.floor(totalSeconds / 60);
		const seconds = totalSeconds % 60;
		const paceStr = `${minutes}:${seconds.toString().padStart(2, '0')}`;
		return `Fastest mile — ${paceStr} pace`;
	}
	const milesStr = newValue >= 10 ? newValue.toFixed(1) : newValue.toFixed(2);
	return `Most miles in a day — ${milesStr} mi`;
}

function personalBestLabel(prType: 'fastest_mile' | 'most_miles_day', newValue: number): string {
	if (prType === 'fastest_mile') {
		const totalSeconds = Math.round(newValue);
		const minutes = Math.floor(totalSeconds / 60);
		const seconds = totalSeconds % 60;
		return `fastest mile (${minutes}:${seconds.toString().padStart(2, '0')})`;
	}
	const milesStr = newValue >= 10 ? newValue.toFixed(1) : newValue.toFixed(2);
	return `most miles in a day (${milesStr} mi)`;
}

/**
 * Fan out a personal-best to every accepted friend. No throttle — each PR
 * dimension is its own event, and a single workout breaking both PRs should
 * produce two distinct inbox rows so the viewer can hype each independently.
 */
export async function fanOutFriendPersonalBestPush(
	senderId: string,
	prType: 'fastest_mile' | 'most_miles_day',
	newValue: number,
	workoutId: string
): Promise<void> {
	const friendIds = await getAcceptedFriendIds(senderId);
	if (friendIds.length === 0) return;
	const sender = await getSenderDisplayName(senderId);

	const title = `${sender} set a new personal best`;
	const body = formatPersonalBestBody(prType, newValue);
	const label = personalBestLabel(prType, newValue);

	for (const friendId of friendIds) {
		const allowed = await shouldSendNotification(friendId, senderId, 'friend_personal_best');
		if (!allowed) continue;

		sendPush(friendId, {
			title,
			body,
			type: 'friend_personal_best',
			data: {
				sender_id: senderId,
				pr_type: prType,
				pr_label: label,
				new_value: String(newValue),
				workout_id: workoutId
			}
		}).catch(err => console.error('[Push] friend_personal_best send failed:', err.message));
	}
}

/**
 * Fan out a daily-challenge completion to every accepted friend.
 */
export async function fanOutFriendChallengePush(senderId: string, completion: ChallengeCompletedPayload): Promise<void> {
	const friendIds = await getAcceptedFriendIds(senderId);
	if (friendIds.length === 0) return;
	const sender = await getSenderDisplayName(senderId);

	for (const friendId of friendIds) {
		sendPush(friendId, {
			title: `${sender} finished today's challenge`,
			body: completion.challengeTitle,
			type: 'friend_challenge_completed',
			data: {
				sender_id: senderId,
				challenge_key: completion.challengeKey,
				challenge_title: completion.challengeTitle,
				local_date: completion.localDate
			}
		}).catch(err => console.error('[Push] friend_challenge_completed send failed:', err.message));
	}
}

async function getAcceptedFriendIds(userId: string): Promise<string[]> {
	const rows = await db.query<{ friend_id: string }>(
		`SELECT friend_id FROM friendships WHERE user_id = $1 AND status = 'accepted'`,
		[userId]
	);
	return rows.map(r => r.friend_id);
}

async function getSenderDisplayName(userId: string): Promise<string> {
	const rows = await db.query<{ first_name: string | null; username: string | null }>(
		`SELECT first_name, username FROM users WHERE user_id = $1`,
		[userId]
	);
	const row = rows[0];
	return row?.first_name || row?.username || 'A friend';
}

// Throttle friend_badge_earned to at most 1 per sender→recipient per hour to avoid multi-badge-day spam.
async function passesFriendBadgeThrottle(senderId: string, recipientId: string): Promise<boolean> {
	const rows = await db.query<{ count: string }>(
		`SELECT COUNT(*)::text AS count FROM in_app_notifications
		WHERE user_id = $1 AND type = 'friend_badge_earned'
		  AND (data->>'sender_id') = $2
		  AND created_at > NOW() - INTERVAL '1 hour'`,
		[recipientId, senderId]
	);
	return parseInt(rows[0]?.count ?? '0', 10) === 0;
}

// ─── Cleanup ────────────────────────────────────────────────────────

/**
 * Clean up old log entries to prevent unbounded table growth.
 * Should be called daily via cron.
 */
export async function cleanupNotificationLogs(): Promise<void> {
	const results = await Promise.all([
		db.query(`DELETE FROM notification_log WHERE created_at < NOW() - INTERVAL '30 days'`),
		db.query(`DELETE FROM pending_notifications WHERE sent_at IS NOT NULL AND sent_at < NOW() - INTERVAL '7 days'`),
		db.query(`DELETE FROM nudge_log WHERE created_at < NOW() - INTERVAL '7 days'`),
		db.query(`DELETE FROM friend_nudge_log WHERE created_at < NOW() - INTERVAL '7 days'`),
		db.query(`DELETE FROM flex_log WHERE created_at < NOW() - INTERVAL '30 days'`)
	]);
	console.log('[Cleanup] Cleaned up old notification logs');
}
