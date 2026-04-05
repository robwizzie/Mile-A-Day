import { PostgresService } from './DbService.js';
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
const APNS_HOST = APNS_PRODUCTION
	? 'https://api.push.apple.com'
	: 'https://api.sandbox.push.apple.com';

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
		const keyPath = path.isAbsolute(APNS_KEY_PATH)
			? APNS_KEY_PATH
			: path.join(process.cwd(), APNS_KEY_PATH);
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
	| 'competition_milestone';

interface PushPayload {
	title: string;
	body: string;
	type: NotificationType;
	data?: Record<string, string>;
}

// Send a push notification to a single device token via HTTP/2
function sendToDevice(deviceToken: string, payload: PushPayload): Promise<boolean> {
	return new Promise((resolve) => {
		const token = getApnsToken();
		if (!token || !APNS_BUNDLE_ID) {
			console.warn('[Push] APNs not configured, skipping push');
			resolve(false);
			return;
		}

		const apnsPayload = JSON.stringify({
			aps: {
				alert: { title: payload.title, body: payload.body },
				sound: 'default',
				'mutable-content': 1
			},
			type: payload.type,
			data: payload.data ?? {}
		});

		const client = http2.connect(APNS_HOST);

		client.on('error', (err) => {
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

		req.on('response', (headers) => {
			statusCode = headers[':status'] as number;
		});

		req.on('data', (chunk) => {
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

		req.on('error', (err) => {
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

// ─── Public API ──────────────────────────────────────────────────────

export async function sendPush(userId: string, payload: PushPayload): Promise<void> {
	const tokens = await db.query<{ device_token: string }>(
		'SELECT device_token FROM device_tokens WHERE user_id = $1',
		[userId]
	);

	if (tokens.length === 0) {
		console.log(`[Push] No device tokens found for user ${userId}`);
		return;
	}

	const results = await Promise.all(
		tokens.map(({ device_token }) => sendToDevice(device_token, payload))
	);

	const sent = results.filter(Boolean).length;
	if (sent > 0) {
		console.log(`[Push] Sent "${payload.type}" to user ${userId} (${sent}/${tokens.length} devices)`);
	}
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
	await db.query(
		'DELETE FROM device_tokens WHERE user_id = $1 AND device_token = $2',
		[userId, deviceToken]
	);
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
		const body = type === 'competition_started'
			? `${competitionName} has begun!`
			: `${competitionName} has finished!`;
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
		const starts = notifications.filter(n => n.type === 'competition_started');
		const finishes = notifications.filter(n => n.type === 'competition_finished');

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

	// Mark all as sent
	const ids = pending.map(n => n.id);
	await db.query(
		`UPDATE pending_notifications SET sent_at = NOW() WHERE id = ANY($1::uuid[])`,
		[ids]
	);

	console.log(`[Push] Flushed ${pending.length} batched notifications for ${Object.keys(byUser).length} users`);
}

// ─── Nudge Rate Limiting ─────────────────────────────────────────────

export async function canNudge(competitionId: string, senderId: string, targetId: string): Promise<boolean> {
	const result = await db.query(
		`SELECT id FROM nudge_log
		WHERE competition_id = $1 AND sender_id = $2 AND target_id = $3
			AND created_at > NOW() - INTERVAL '24 hours'
		LIMIT 1`,
		[competitionId, senderId, targetId]
	);
	return result.length === 0;
}

export async function logNudge(competitionId: string, senderId: string, targetId: string): Promise<void> {
	await db.query(
		`INSERT INTO nudge_log (competition_id, sender_id, target_id) VALUES ($1, $2, $3)`,
		[competitionId, senderId, targetId]
	);
}

// ─── Friend Nudge Rate Limiting ─────────────────────────────────────

export async function canFriendNudge(senderId: string, targetId: string): Promise<boolean> {
	const result = await db.query(
		`SELECT id FROM friend_nudge_log
		WHERE sender_id = $1 AND target_id = $2
			AND created_at > NOW() - INTERVAL '24 hours'
		LIMIT 1`,
		[senderId, targetId]
	);
	return result.length === 0;
}

export async function logFriendNudge(senderId: string, targetId: string): Promise<void> {
	await db.query(
		`INSERT INTO friend_nudge_log (sender_id, target_id) VALUES ($1, $2)`,
		[senderId, targetId]
	);
}

// ─── Flex Rate Limiting (per sender→target per day, across all competitions) ──

export async function canFlex(senderId: string, targetId: string): Promise<boolean> {
	const result = await db.query(
		`SELECT id FROM flex_log
		WHERE sender_id = $1 AND target_id = $2
			AND created_at > NOW() - INTERVAL '24 hours'
		LIMIT 1`,
		[senderId, targetId]
	);
	return result.length === 0;
}

export async function logFlex(senderId: string, targetId: string, competitionId: string, message: string | null): Promise<void> {
	await db.query(
		`INSERT INTO flex_log (sender_id, target_id, competition_id, message) VALUES ($1, $2, $3, $4)`,
		[senderId, targetId, competitionId, message]
	);
}
