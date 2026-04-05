import { PostgresService } from './DbService.js';

const db = PostgresService.getInstance();

// ─── Notification Preferences (per-user global settings) ────────────

export interface NotificationPreferences {
	nudges_enabled: boolean;
	flexes_enabled: boolean;
	friend_activity_enabled: boolean;
	competition_invites_enabled: boolean;
	competition_updates_enabled: boolean;
	competition_milestones_enabled: boolean;
	quiet_hours_start: number | null; // hour 0-23 or null for no quiet hours
	quiet_hours_end: number | null;
}

const DEFAULT_PREFERENCES: NotificationPreferences = {
	nudges_enabled: true,
	flexes_enabled: true,
	friend_activity_enabled: true,
	competition_invites_enabled: true,
	competition_updates_enabled: true,
	competition_milestones_enabled: true,
	quiet_hours_start: null,
	quiet_hours_end: null,
};

export async function getNotificationPreferences(userId: string): Promise<NotificationPreferences> {
	const rows = await db.query(
		'SELECT * FROM notification_settings WHERE user_id = $1',
		[userId]
	);

	if (rows.length === 0) return { ...DEFAULT_PREFERENCES };

	const row = rows[0];
	return {
		nudges_enabled: row.nudges_enabled ?? true,
		flexes_enabled: row.flexes_enabled ?? true,
		friend_activity_enabled: row.friend_activity_enabled ?? true,
		competition_invites_enabled: row.competition_invites_enabled ?? true,
		competition_updates_enabled: row.competition_updates_enabled ?? true,
		competition_milestones_enabled: row.competition_milestones_enabled ?? true,
		quiet_hours_start: row.quiet_hours_start ?? null,
		quiet_hours_end: row.quiet_hours_end ?? null,
	};
}

export async function updateNotificationPreferences(
	userId: string,
	prefs: Partial<NotificationPreferences>
): Promise<NotificationPreferences> {
	await db.query(
		`INSERT INTO notification_settings (
			user_id, nudges_enabled, flexes_enabled, friend_activity_enabled,
			competition_invites_enabled, competition_updates_enabled,
			competition_milestones_enabled, quiet_hours_start, quiet_hours_end
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
		ON CONFLICT (user_id) DO UPDATE SET
			nudges_enabled = COALESCE($2, notification_settings.nudges_enabled),
			flexes_enabled = COALESCE($3, notification_settings.flexes_enabled),
			friend_activity_enabled = COALESCE($4, notification_settings.friend_activity_enabled),
			competition_invites_enabled = COALESCE($5, notification_settings.competition_invites_enabled),
			competition_updates_enabled = COALESCE($6, notification_settings.competition_updates_enabled),
			competition_milestones_enabled = COALESCE($7, notification_settings.competition_milestones_enabled),
			quiet_hours_start = COALESCE($8, notification_settings.quiet_hours_start),
			quiet_hours_end = COALESCE($9, notification_settings.quiet_hours_end),
			updated_at = NOW()`,
		[
			userId,
			prefs.nudges_enabled ?? null,
			prefs.flexes_enabled ?? null,
			prefs.friend_activity_enabled ?? null,
			prefs.competition_invites_enabled ?? null,
			prefs.competition_updates_enabled ?? null,
			prefs.competition_milestones_enabled ?? null,
			prefs.quiet_hours_start ?? null,
			prefs.quiet_hours_end ?? null,
		]
	);

	return getNotificationPreferences(userId);
}

// ─── Friend-specific notification settings ──────────────────────────

export interface FriendNotificationSettings {
	friend_id: string;
	username?: string;
	muted: boolean;
	nudges_muted: boolean;
	activity_muted: boolean;
}

export async function getFriendNotificationSettings(userId: string): Promise<FriendNotificationSettings[]> {
	const rows = await db.query(
		`SELECT fns.friend_id, fns.muted, fns.nudges_muted, fns.activity_muted, u.username
		FROM friend_notification_settings fns
		JOIN users u ON u.user_id = fns.friend_id
		WHERE fns.user_id = $1`,
		[userId]
	);

	return rows.map((row: any) => ({
		friend_id: row.friend_id,
		username: row.username,
		muted: row.muted,
		nudges_muted: row.nudges_muted,
		activity_muted: row.activity_muted,
	}));
}

export async function updateFriendNotificationSettings(
	userId: string,
	friendId: string,
	settings: { muted?: boolean; nudges_muted?: boolean; activity_muted?: boolean }
): Promise<FriendNotificationSettings> {
	await db.query(
		`INSERT INTO friend_notification_settings (user_id, friend_id, muted, nudges_muted, activity_muted)
		VALUES ($1, $2, $3, $4, $5)
		ON CONFLICT (user_id, friend_id) DO UPDATE SET
			muted = COALESCE($3, friend_notification_settings.muted),
			nudges_muted = COALESCE($4, friend_notification_settings.nudges_muted),
			activity_muted = COALESCE($5, friend_notification_settings.activity_muted),
			updated_at = NOW()`,
		[
			userId,
			friendId,
			settings.muted ?? null,
			settings.nudges_muted ?? null,
			settings.activity_muted ?? null,
		]
	);

	const rows = await db.query(
		`SELECT fns.friend_id, fns.muted, fns.nudges_muted, fns.activity_muted, u.username
		FROM friend_notification_settings fns
		JOIN users u ON u.user_id = fns.friend_id
		WHERE fns.user_id = $1 AND fns.friend_id = $2`,
		[userId, friendId]
	);

	return {
		friend_id: rows[0].friend_id,
		username: rows[0].username,
		muted: rows[0].muted,
		nudges_muted: rows[0].nudges_muted,
		activity_muted: rows[0].activity_muted,
	};
}

// ─── Helper: Check if a notification should be sent to a user ───────

export async function shouldSendNotification(
	targetUserId: string,
	senderId: string | null,
	notificationType: 'nudge' | 'flex' | 'friend_activity' | 'competition_invite' | 'competition_update' | 'competition_milestone'
): Promise<boolean> {
	const prefs = await getNotificationPreferences(targetUserId);

	// Check global preference for this notification type
	switch (notificationType) {
		case 'nudge':
			if (!prefs.nudges_enabled) return false;
			break;
		case 'flex':
			if (!prefs.flexes_enabled) return false;
			break;
		case 'friend_activity':
			if (!prefs.friend_activity_enabled) return false;
			break;
		case 'competition_invite':
			if (!prefs.competition_invites_enabled) return false;
			break;
		case 'competition_update':
			if (!prefs.competition_updates_enabled) return false;
			break;
		case 'competition_milestone':
			if (!prefs.competition_milestones_enabled) return false;
			break;
	}

	// Check friend-specific muting if there's a sender
	if (senderId) {
		const friendSettings = await db.query(
			'SELECT muted, nudges_muted, activity_muted FROM friend_notification_settings WHERE user_id = $1 AND friend_id = $2',
			[targetUserId, senderId]
		);

		if (friendSettings.length > 0) {
			const fs = friendSettings[0];
			if (fs.muted) return false;
			if (notificationType === 'nudge' && fs.nudges_muted) return false;
			if (notificationType === 'friend_activity' && fs.activity_muted) return false;
		}
	}

	return true;
}
