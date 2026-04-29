import { PostgresService } from './DbService.js';

const db = PostgresService.getInstance();

// ─── Notification Preferences (per-user global settings) ────────────

export interface NotificationPreferences {
	nudges_enabled: boolean;
	flexes_enabled: boolean;
	hypes_enabled: boolean;
	friend_activity_enabled: boolean;
	competition_invites_enabled: boolean;
	competition_updates_enabled: boolean;
	competition_milestones_enabled: boolean;
	step_goal_enabled: boolean;
	quiet_hours_start: number | null; // hour 0-23 or null for no quiet hours
	quiet_hours_end: number | null;
}

const DEFAULT_PREFERENCES: NotificationPreferences = {
	nudges_enabled: true,
	flexes_enabled: true,
	hypes_enabled: true,
	friend_activity_enabled: true,
	competition_invites_enabled: true,
	competition_updates_enabled: true,
	competition_milestones_enabled: true,
	step_goal_enabled: true,
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
		hypes_enabled: row.hypes_enabled ?? true,
		friend_activity_enabled: row.friend_activity_enabled ?? true,
		competition_invites_enabled: row.competition_invites_enabled ?? true,
		competition_updates_enabled: row.competition_updates_enabled ?? true,
		competition_milestones_enabled: row.competition_milestones_enabled ?? true,
		step_goal_enabled: row.step_goal_enabled ?? true,
		quiet_hours_start: row.quiet_hours_start ?? null,
		quiet_hours_end: row.quiet_hours_end ?? null,
	};
}

export async function updateNotificationPreferences(
	userId: string,
	prefs: Partial<NotificationPreferences>
): Promise<NotificationPreferences> {
	// Build SET clauses dynamically so we only update fields that were explicitly provided.
	// This avoids the COALESCE problem where null can't be distinguished from "not provided".
	const setClauses: string[] = [];
	const values: any[] = [userId];
	let paramIdx = 2;

	const fields: { key: keyof NotificationPreferences; value: any }[] = [
		{ key: 'nudges_enabled', value: prefs.nudges_enabled },
		{ key: 'flexes_enabled', value: prefs.flexes_enabled },
		{ key: 'hypes_enabled', value: prefs.hypes_enabled },
		{ key: 'friend_activity_enabled', value: prefs.friend_activity_enabled },
		{ key: 'competition_invites_enabled', value: prefs.competition_invites_enabled },
		{ key: 'competition_updates_enabled', value: prefs.competition_updates_enabled },
		{ key: 'competition_milestones_enabled', value: prefs.competition_milestones_enabled },
		{ key: 'step_goal_enabled', value: prefs.step_goal_enabled },
		{ key: 'quiet_hours_start', value: prefs.quiet_hours_start },
		{ key: 'quiet_hours_end', value: prefs.quiet_hours_end },
	];

	for (const field of fields) {
		if (field.value !== undefined) {
			setClauses.push(`${field.key} = $${paramIdx}`);
			values.push(field.value ?? null);
			paramIdx++;
		}
	}

	if (setClauses.length > 0) {
		// Ensure row exists with defaults, then update only the provided fields
		await db.query(
			`INSERT INTO notification_settings (user_id) VALUES ($1) ON CONFLICT DO NOTHING`,
			[userId]
		);
		await db.query(
			`UPDATE notification_settings SET ${setClauses.join(', ')}, updated_at = NOW() WHERE user_id = $1`,
			values
		);
	}

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
	// Ensure a row exists with defaults, then update only the provided fields.
	// This avoids NOT NULL violations when only one field is sent (e.g. just "muted").
	await db.query(
		`INSERT INTO friend_notification_settings (user_id, friend_id)
		VALUES ($1, $2)
		ON CONFLICT DO NOTHING`,
		[userId, friendId]
	);

	const setClauses: string[] = [];
	const values: any[] = [userId, friendId];
	let paramIdx = 3;

	if (settings.muted !== undefined) {
		setClauses.push(`muted = $${paramIdx++}`);
		values.push(settings.muted);
	}
	if (settings.nudges_muted !== undefined) {
		setClauses.push(`nudges_muted = $${paramIdx++}`);
		values.push(settings.nudges_muted);
	}
	if (settings.activity_muted !== undefined) {
		setClauses.push(`activity_muted = $${paramIdx++}`);
		values.push(settings.activity_muted);
	}

	if (setClauses.length > 0) {
		await db.query(
			`UPDATE friend_notification_settings SET ${setClauses.join(', ')}, updated_at = NOW()
			WHERE user_id = $1 AND friend_id = $2`,
			values
		);
	}

	const rows = await db.query(
		`SELECT fns.friend_id, fns.muted, fns.nudges_muted, fns.activity_muted, u.username
		FROM friend_notification_settings fns
		JOIN users u ON u.user_id = fns.friend_id
		WHERE fns.user_id = $1 AND fns.friend_id = $2`,
		[userId, friendId]
	);

	if (rows.length === 0) {
		throw new Error('Friend notification setting not found after upsert');
	}

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
	notificationType: 'nudge' | 'flex' | 'hype' | 'friend_activity' | 'competition_invite' | 'competition_update' | 'competition_milestone'
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
		case 'hype':
			if (!prefs.hypes_enabled) return false;
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
