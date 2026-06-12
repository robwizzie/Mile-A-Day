import { PostgresService } from './DbService.js';
import { sendPush, NotificationType } from './pushNotificationService.js';
import { filterRecipientsForNotification } from './notificationSettingsService.js';
import {
	filterByIncomingAudience,
	resolveAudience,
	restrictToCloseFriends,
	AudienceEventType,
	AudienceActivity
} from './audienceSettingsService.js';
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

// Global notification-preference type passed to filterRecipientsForNotification
// for non-workout events. Must mirror what the live fan-outs check:
// personal_best → 'friend_personal_best' (fanOutFriendPersonalBestPush's
// per-recipient shouldSendNotification), streak_broken → 'friend_activity'
// (checkStreaksBroken). badge_earned and challenge_completed are deliberately
// ABSENT — notification_settings has no global pref field for them and the
// live fan-outs (fanOutFriendBadgePush / fanOutFriendChallengePush) apply no
// per-recipient pref check, so those events skip filterRecipientsForNotification.
const PREF_FILTER_TYPE: Record<string, 'friend_personal_best' | 'friend_activity'> = {
	personal_best: 'friend_personal_best',
	streak_broken: 'friend_activity'
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
	| { ok: false; reason: 'not_found' | 'not_owner' | 'already_processed' | 'expired' | 'audience_blocked' };

/**
 * Confirm and send a pending notification.
 *
 * Order of operations (race-safe):
 * 1. Read the row for diagnosis + event metadata (no state change).
 * 2. Re-check the sender's CURRENT outgoing audience — settings may have
 *    changed since the row was queued. 'none' refuses without touching the
 *    row; 'close' caps the effective audience regardless of the request.
 * 3. Atomic claim: UPDATE ... SET status='sent' WHERE status='pending'.
 *    Concurrent sends race on this single statement — exactly one wins.
 * 4. Same-day check AFTER claiming: a stale claimed row is flipped to
 *    'expired' (claim-then-expire is race-safe; nothing was sent yet).
 * 5. Build recipients exactly as the live senders do, then send.
 */
export async function sendPending(userId: string, id: string, audience: 'close' | 'all' = 'all'): Promise<SendPendingResult> {
	interface FullRow {
		id: string;
		user_id: string;
		event_type: string;
		activity_type: string;
		workout_id: string | null;
		payload: Record<string, any>;
		local_date: string;
		status: string;
	}

	// 1. Read-only fetch for diagnosis + audience metadata.
	const rows = await db.query<FullRow>(
		`SELECT id, user_id, event_type, activity_type, workout_id, payload, local_date, status
		 FROM pending_friend_notifications
		 WHERE id = $1`,
		[id]
	);

	if (rows.length === 0) return { ok: false, reason: 'not_found' };
	const preview = rows[0];

	if (preview.user_id !== userId) return { ok: false, reason: 'not_owner' };
	if (preview.status !== 'pending') return { ok: false, reason: 'already_processed' };

	const eventType = preview.event_type as AudienceEventType;
	const activity = (preview.activity_type ?? '') as AudienceActivity;

	// 2. Re-check the sender's CURRENT outgoing audience. The row was queued
	// under an 'ask' setting that may since have changed.
	const currentOutgoing = await resolveAudience(userId, 'outgoing', eventType, activity);
	if (currentOutgoing === 'none') {
		// Refuse without touching the row — the user can re-enable and retry.
		return { ok: false, reason: 'audience_blocked' };
	}
	// The request can never widen beyond the current setting: current 'close'
	// forces 'close'; current 'all'/'ask' honors the requested audience.
	const effectiveAudience: 'close' | 'all' = currentOutgoing === 'close' ? 'close' : audience;

	// 3. Atomic claim — exactly one concurrent send can flip pending → sent.
	const claimedRows = await db.query<FullRow>(
		`UPDATE pending_friend_notifications
		 SET status = 'sent'
		 WHERE id = $1 AND user_id = $2 AND status = 'pending'
		 RETURNING id, user_id, event_type, activity_type, workout_id, payload, local_date, status`,
		[id, userId]
	);

	if (claimedRows.length === 0) {
		// Claim failed — re-read for a precise diagnosis (read-only is fine here).
		const lost = await db.query<{ user_id: string; status: string }>(
			`SELECT user_id, status FROM pending_friend_notifications WHERE id = $1`,
			[id]
		);
		if (lost.length === 0) return { ok: false, reason: 'not_found' };
		if (lost[0].user_id !== userId) return { ok: false, reason: 'not_owner' };
		return { ok: false, reason: 'already_processed' };
	}
	const row = claimedRows[0];

	// 4. Same-day check AFTER claiming. Stale claimed row → flip to expired.
	const localDate = await getUserLocalDate(userId);
	if (row.local_date !== localDate) {
		await db.query(`UPDATE pending_friend_notifications SET status = 'expired' WHERE id = $1`, [id]);
		return { ok: false, reason: 'expired' };
	}

	// 5. Build recipients exactly as the live senders do.
	let allowedRecipients: string[];

	if (WORKOUT_EVENT_TYPES.has(row.event_type)) {
		// Full pool: friends + active-competition co-participants (same as live senders).
		allowedRecipients = await getFriendActivityRecipientPool(userId, effectiveAudience, eventType, activity);
	} else {
		// Non-workout events: friends only (no comp participants).
		// This mirrors pushNotificationService.ts resolveFriendFanOutRecipients.
		const friendRows = await db.query<{ friend_id: string }>(
			`SELECT friend_id FROM friendships WHERE user_id = $1 AND status = 'accepted'`,
			[userId]
		);
		let friendIds = friendRows.map(r => r.friend_id);

		if (effectiveAudience === 'close') {
			friendIds = await restrictToCloseFriends(userId, friendIds);
		}

		if (friendIds.length === 0) {
			allowedRecipients = [];
		} else {
			// Global-pref filter only for events the live fan-outs actually check
			// (see PREF_FILTER_TYPE). badge_earned / challenge_completed skip it.
			const prefType = PREF_FILTER_TYPE[row.event_type];
			const prefAllowed = prefType ? await filterRecipientsForNotification(friendIds, userId, prefType) : friendIds;
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

	// Status was already flipped to 'sent' by the atomic claim above.
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
