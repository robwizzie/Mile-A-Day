import { PostgresService } from './DbService.js';
import { sendPush, NotificationType } from './pushNotificationService.js';
import { filterRecipientsForNotification } from './notificationSettingsService.js';
import { filterByIncomingAudience, AudienceEventType, AudienceActivity } from './audienceSettingsService.js';
import { getFriendActivityRecipientPool } from './notificationService.js';
import { getUserLocalDate } from './workoutService.js';

const db = PostgresService.getInstance();

// ─── Types ────────────────────────────────────────────────────────────

export interface PendingRow {
	id: string;
	event_type: string;
	activity_type: string;
	workout_id: string | null;
	payload: Record<string, any>;
	local_date: string;
	created_at: string;
}

// Map from pending event_type → the NotificationType string the live senders
// pass to shouldSendNotification / filterRecipientsForNotification. Must mirror
// what the live fan-outs use exactly.
const EVENT_TYPE_TO_NOTIFICATION_TYPE: Record<string, NotificationType> = {
	mile_completed: 'friend_activity',
	extra_workout: 'friend_activity',
	workout: 'friend_activity',
	streak_broken: 'friend_activity',
	personal_best: 'friend_personal_best',
	badge_earned: 'friend_badge_earned',
	challenge_completed: 'friend_challenge_completed'
};

// Workout-type events use the full friend+competition-participant pool.
const WORKOUT_EVENT_TYPES = new Set(['mile_completed', 'extra_workout', 'workout']);

// ─── listPending ──────────────────────────────────────────────────────

/**
 * Return all pending rows for the user that are still valid today.
 * As a side effect, marks any stale pending rows (created on an earlier local
 * date) as 'expired' so they don't pile up.
 */
export async function listPending(userId: string): Promise<PendingRow[]> {
	const localDate = await getUserLocalDate(userId);

	// Lazy expiry: mark stale rows expired before fetching active ones.
	await db.query(
		`UPDATE pending_friend_notifications
		 SET status = 'expired'
		 WHERE user_id = $1 AND status = 'pending' AND local_date < $2`,
		[userId, localDate]
	);

	return db.query<PendingRow>(
		`SELECT id, event_type, activity_type, workout_id, payload, local_date, created_at
		 FROM pending_friend_notifications
		 WHERE user_id = $1 AND status = 'pending' AND local_date >= $2
		 ORDER BY created_at DESC`,
		[userId, localDate]
	);
}

// ─── sendPending ──────────────────────────────────────────────────────

export type SendPendingResult =
	| { ok: true; sent: number }
	| { ok: false; reason: 'not_found' | 'not_owner' | 'already_processed' | 'expired' };

/**
 * Confirm and send a pending notification. Validates ownership, checks the
 * row is still valid for today, builds the recipient pool exactly as the live
 * senders do, and sends.
 */
export async function sendPending(userId: string, id: string, audience: 'close' | 'all' = 'all'): Promise<SendPendingResult> {
	// Fetch the row (ownership + status check).
	const rows = await db.query<{
		id: string;
		user_id: string;
		event_type: string;
		activity_type: string;
		workout_id: string | null;
		payload: Record<string, any>;
		local_date: string;
		status: string;
	}>(
		`SELECT id, user_id, event_type, activity_type, workout_id, payload, local_date, status
		 FROM pending_friend_notifications
		 WHERE id = $1`,
		[id]
	);

	if (rows.length === 0) return { ok: false, reason: 'not_found' };
	const row = rows[0];

	if (row.user_id !== userId) return { ok: false, reason: 'not_owner' };

	if (row.status !== 'pending') return { ok: false, reason: 'already_processed' };

	// Check same-day validity.
	const localDate = await getUserLocalDate(userId);
	if (row.local_date !== localDate) {
		// Mark expired.
		await db.query(`UPDATE pending_friend_notifications SET status = 'expired' WHERE id = $1`, [id]);
		return { ok: false, reason: 'expired' };
	}

	const eventType = row.event_type as AudienceEventType;
	const activity = (row.activity_type ?? '') as AudienceActivity;
	const notifType = EVENT_TYPE_TO_NOTIFICATION_TYPE[row.event_type] ?? 'friend_activity';

	let allowedRecipients: string[];

	if (WORKOUT_EVENT_TYPES.has(row.event_type)) {
		// Full pool: friends + active-competition co-participants (same as live senders).
		allowedRecipients = await getFriendActivityRecipientPool(userId, audience, eventType, activity);
	} else {
		// Non-workout events: friends only (no comp participants).
		// This mirrors pushNotificationService.ts resolveFriendFanOutRecipients.
		const friendRows = await db.query<{ friend_id: string }>(
			`SELECT friend_id FROM friendships WHERE user_id = $1 AND status = 'accepted'`,
			[userId]
		);
		let friendIds = friendRows.map(r => r.friend_id);

		if (audience === 'close') {
			const closeRows = await db.query<{ close_friend_id: string }>(
				`SELECT close_friend_id FROM close_friends WHERE user_id = $1`,
				[userId]
			);
			const closeSet = new Set(closeRows.map(r => r.close_friend_id));
			friendIds = friendIds.filter(id => closeSet.has(id));
		}

		if (friendIds.length === 0) {
			allowedRecipients = [];
		} else {
			const prefAllowed = await filterRecipientsForNotification(friendIds, userId, notifType as any);
			allowedRecipients = await filterByIncomingAudience(prefAllowed, userId, eventType, activity);
		}
	}

	// Build push payload from stored JSONB. Cast type to NotificationType so
	// sendPush's type signature is satisfied — the stored value was written by
	// the live sender so it's already a valid NotificationType string.
	const payload = {
		title: row.payload.title as string,
		body: row.payload.body as string,
		type: row.payload.type as NotificationType,
		category: row.payload.category as string | undefined,
		data: row.payload.data as Record<string, string> | undefined
	};

	for (const recipientId of allowedRecipients) {
		sendPush(recipientId, payload).catch(err =>
			console.error(`[Push] Error sending pending ${row.event_type} notification:`, err.message)
		);
	}

	// Mark sent.
	await db.query(`UPDATE pending_friend_notifications SET status = 'sent' WHERE id = $1`, [id]);

	console.log(`[PendingNotif] Sent pending ${row.event_type} for user ${userId} to ${allowedRecipients.length} recipients`);

	return { ok: true, sent: allowedRecipients.length };
}

// ─── dismissPending ───────────────────────────────────────────────────

export type DismissPendingResult = { ok: true } | { ok: false; reason: 'not_found' | 'not_owner' | 'already_processed' };

export async function dismissPending(userId: string, id: string): Promise<DismissPendingResult> {
	const rows = await db.query<{ user_id: string; status: string }>(
		`SELECT user_id, status FROM pending_friend_notifications WHERE id = $1`,
		[id]
	);
	if (rows.length === 0) return { ok: false, reason: 'not_found' };
	if (rows[0].user_id !== userId) return { ok: false, reason: 'not_owner' };
	if (rows[0].status !== 'pending') return { ok: false, reason: 'already_processed' };

	await db.query(`UPDATE pending_friend_notifications SET status = 'dismissed' WHERE id = $1`, [id]);
	return { ok: true };
}

// ─── dismissAllPending ────────────────────────────────────────────────

export async function dismissAllPending(userId: string): Promise<{ dismissed: number }> {
	const result = await db.query<{ count: string }>(
		`WITH updated AS (
			UPDATE pending_friend_notifications
			SET status = 'dismissed'
			WHERE user_id = $1 AND status = 'pending'
			RETURNING id
		) SELECT COUNT(*)::text AS count FROM updated`,
		[userId]
	);
	return { dismissed: parseInt(result[0]?.count ?? '0', 10) };
}

// ─── expireStale (for cron) ───────────────────────────────────────────

/**
 * Expire all pending rows whose local_date is before the current date in the
 * user's timezone. Uses the same timezone_offset source as getUserLocalDate
 * (most recent workout's timezone_offset, default UTC when unknown).
 *
 * Safe to call repeatedly — only touches rows that are genuinely stale.
 */
export async function expireStalePendingNotifications(): Promise<number> {
	const result = await db.query<{ count: string }>(
		`WITH user_local AS (
			-- Compute each user's current local date using their most recent workout
			-- timezone_offset (minutes), defaulting to UTC when unknown. Mirrors
			-- getUserLocalDate exactly.
			SELECT DISTINCT pfn.user_id,
				(NOW() + (COALESCE(
					(SELECT w.timezone_offset
					 FROM workouts w
					 WHERE w.user_id = pfn.user_id
					 ORDER BY w.device_end_date DESC
					 LIMIT 1),
					0
				) || ' minutes')::interval)::date AS local_today
			FROM pending_friend_notifications pfn
			WHERE pfn.status = 'pending'
		),
		expired AS (
			UPDATE pending_friend_notifications pfn
			SET status = 'expired'
			FROM user_local ul
			WHERE pfn.user_id = ul.user_id
				AND pfn.status = 'pending'
				AND pfn.local_date < ul.local_today
			RETURNING pfn.id
		)
		SELECT COUNT(*)::text AS count FROM expired`,
		[]
	);
	const count = parseInt(result[0]?.count ?? '0', 10);
	if (count > 0) {
		console.log(`[PendingNotif] Expired ${count} stale pending notifications`);
	}
	return count;
}
