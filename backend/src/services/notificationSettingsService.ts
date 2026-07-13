import { PostgresService } from "./DbService.js";

const db = PostgresService.getInstance();

// ─── Notification Preferences (per-user global settings) ────────────

export interface NotificationPreferences {
  nudges_enabled: boolean;
  flexes_enabled: boolean;
  hypes_enabled: boolean;
  friend_activity_enabled: boolean;
  friend_personal_best_enabled: boolean;
  competition_invites_enabled: boolean;
  competition_updates_enabled: boolean;
  competition_milestones_enabled: boolean;
  step_goal_enabled: boolean;
  quiet_hours_start: number | null; // hour 0-23 or null for no quiet hours
  quiet_hours_end: number | null;
  daily_reminder_enabled: boolean;
  daily_reminder_hour: number; // 0-23, hour in user's local timezone
  timezone_offset_minutes: number | null; // user's current UTC offset in minutes
  share_workouts_to_feed: boolean; // include my raw walks/runs in friends' feed
  friend_posts_enabled: boolean; // notify me when a friend shares a new post
  share_route_maps: boolean; // show my GPS route maps on my feed entries/posts
  weekly_recap_enabled: boolean; // Sunday-evening weekly recap push + story card
  h2h_close_friends_only: boolean; // Head-to-Head rivals only from my close friends
}

const DEFAULT_PREFERENCES: NotificationPreferences = {
  nudges_enabled: true,
  flexes_enabled: true,
  hypes_enabled: true,
  friend_activity_enabled: true,
  friend_personal_best_enabled: true,
  competition_invites_enabled: true,
  competition_updates_enabled: true,
  competition_milestones_enabled: true,
  step_goal_enabled: true,
  quiet_hours_start: null,
  quiet_hours_end: null,
  daily_reminder_enabled: true,
  daily_reminder_hour: 18,
  timezone_offset_minutes: null,
  share_workouts_to_feed: true,
  friend_posts_enabled: true,
  share_route_maps: true,
  weekly_recap_enabled: true,
  h2h_close_friends_only: false,
};

export async function getNotificationPreferences(
  userId: string,
): Promise<NotificationPreferences> {
  const rows = await db.query(
    "SELECT * FROM notification_settings WHERE user_id = $1",
    [userId],
  );

  if (rows.length === 0) return { ...DEFAULT_PREFERENCES };

  const row = rows[0];
  return {
    nudges_enabled: row.nudges_enabled ?? true,
    flexes_enabled: row.flexes_enabled ?? true,
    hypes_enabled: row.hypes_enabled ?? true,
    friend_activity_enabled: row.friend_activity_enabled ?? true,
    friend_personal_best_enabled: row.friend_personal_best_enabled ?? true,
    competition_invites_enabled: row.competition_invites_enabled ?? true,
    competition_updates_enabled: row.competition_updates_enabled ?? true,
    competition_milestones_enabled: row.competition_milestones_enabled ?? true,
    step_goal_enabled: row.step_goal_enabled ?? true,
    quiet_hours_start: row.quiet_hours_start ?? null,
    quiet_hours_end: row.quiet_hours_end ?? null,
    daily_reminder_enabled: row.daily_reminder_enabled ?? true,
    daily_reminder_hour: row.daily_reminder_hour ?? 18,
    timezone_offset_minutes: row.timezone_offset_minutes ?? null,
    share_workouts_to_feed: row.share_workouts_to_feed ?? true,
    friend_posts_enabled: row.friend_posts_enabled ?? true,
    share_route_maps: row.share_route_maps ?? true,
    weekly_recap_enabled: row.weekly_recap_enabled ?? true,
    h2h_close_friends_only: row.h2h_close_friends_only ?? false,
  };
}

export async function updateNotificationPreferences(
  userId: string,
  prefs: Partial<NotificationPreferences>,
): Promise<NotificationPreferences> {
  // Build SET clauses dynamically so we only update fields that were explicitly provided.
  // This avoids the COALESCE problem where null can't be distinguished from "not provided".
  const setClauses: string[] = [];
  const values: any[] = [userId];
  let paramIdx = 2;

  const fields: { key: keyof NotificationPreferences; value: any }[] = [
    { key: "nudges_enabled", value: prefs.nudges_enabled },
    { key: "flexes_enabled", value: prefs.flexes_enabled },
    { key: "hypes_enabled", value: prefs.hypes_enabled },
    { key: "friend_activity_enabled", value: prefs.friend_activity_enabled },
    {
      key: "friend_personal_best_enabled",
      value: prefs.friend_personal_best_enabled,
    },
    {
      key: "competition_invites_enabled",
      value: prefs.competition_invites_enabled,
    },
    {
      key: "competition_updates_enabled",
      value: prefs.competition_updates_enabled,
    },
    {
      key: "competition_milestones_enabled",
      value: prefs.competition_milestones_enabled,
    },
    { key: "step_goal_enabled", value: prefs.step_goal_enabled },
    { key: "quiet_hours_start", value: prefs.quiet_hours_start },
    { key: "quiet_hours_end", value: prefs.quiet_hours_end },
    { key: "daily_reminder_enabled", value: prefs.daily_reminder_enabled },
    { key: "daily_reminder_hour", value: prefs.daily_reminder_hour },
    { key: "timezone_offset_minutes", value: prefs.timezone_offset_minutes },
    { key: "share_workouts_to_feed", value: prefs.share_workouts_to_feed },
    { key: "friend_posts_enabled", value: prefs.friend_posts_enabled },
    { key: "share_route_maps", value: prefs.share_route_maps },
    { key: "weekly_recap_enabled", value: prefs.weekly_recap_enabled },
    { key: "h2h_close_friends_only", value: prefs.h2h_close_friends_only },
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
      [userId],
    );
    await db.query(
      `UPDATE notification_settings SET ${setClauses.join(", ")}, updated_at = NOW() WHERE user_id = $1`,
      values,
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

export async function getFriendNotificationSettings(
  userId: string,
): Promise<FriendNotificationSettings[]> {
  const rows = await db.query(
    `SELECT fns.friend_id, fns.muted, fns.nudges_muted, fns.activity_muted, u.username
		FROM friend_notification_settings fns
		JOIN users u ON u.user_id = fns.friend_id
		WHERE fns.user_id = $1`,
    [userId],
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
  settings: {
    muted?: boolean;
    nudges_muted?: boolean;
    activity_muted?: boolean;
  },
): Promise<FriendNotificationSettings> {
  // Ensure a row exists with defaults, then update only the provided fields.
  // This avoids NOT NULL violations when only one field is sent (e.g. just "muted").
  await db.query(
    `INSERT INTO friend_notification_settings (user_id, friend_id)
		VALUES ($1, $2)
		ON CONFLICT DO NOTHING`,
    [userId, friendId],
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
      `UPDATE friend_notification_settings SET ${setClauses.join(", ")}, updated_at = NOW()
			WHERE user_id = $1 AND friend_id = $2`,
      values,
    );
  }

  const rows = await db.query(
    `SELECT fns.friend_id, fns.muted, fns.nudges_muted, fns.activity_muted, u.username
		FROM friend_notification_settings fns
		JOIN users u ON u.user_id = fns.friend_id
		WHERE fns.user_id = $1 AND fns.friend_id = $2`,
    [userId, friendId],
  );

  if (rows.length === 0) {
    throw new Error("Friend notification setting not found after upsert");
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

type NotificationType =
  | "nudge"
  | "flex"
  | "hype"
  | "friend_activity"
  | "friend_personal_best"
  | "competition_invite"
  | "competition_update"
  | "competition_milestone";

const PREF_FIELD_BY_TYPE: Record<
  NotificationType,
  keyof NotificationPreferences
> = {
  nudge: "nudges_enabled",
  flex: "flexes_enabled",
  hype: "hypes_enabled",
  friend_activity: "friend_activity_enabled",
  friend_personal_best: "friend_personal_best_enabled",
  competition_invite: "competition_invites_enabled",
  competition_update: "competition_updates_enabled",
  competition_milestone: "competition_milestones_enabled",
};

/**
 * Batched variant of shouldSendNotification — checks an array of recipients in two
 * queries instead of 2N. Returns the subset of targetUserIds that should receive
 * the notification given the senderId and notificationType.
 */
export async function filterRecipientsForNotification(
  targetUserIds: string[],
  senderId: string | null,
  notificationType: NotificationType,
): Promise<string[]> {
  if (targetUserIds.length === 0) return [];

  const prefField = PREF_FIELD_BY_TYPE[notificationType];

  // Pull global prefs for everyone in one shot. Missing rows = defaults (everything enabled).
  const prefRows = await db.query<
    { user_id: string } & Partial<NotificationPreferences>
  >(`SELECT * FROM notification_settings WHERE user_id = ANY($1::text[])`, [
    targetUserIds,
  ]);
  const prefsByUser = new Map<string, Partial<NotificationPreferences>>();
  for (const row of prefRows) {
    prefsByUser.set(row.user_id, row);
  }

  // Pull friend-specific muting for senderId across all recipients in one shot.
  const friendRows = senderId
    ? await db.query<{
        user_id: string;
        muted: boolean;
        nudges_muted: boolean;
        activity_muted: boolean;
      }>(
        `SELECT user_id, muted, nudges_muted, activity_muted
				 FROM friend_notification_settings
				 WHERE user_id = ANY($1::text[]) AND friend_id = $2`,
        [targetUserIds, senderId],
      )
    : [];
  const friendByUser = new Map<
    string,
    { muted: boolean; nudges_muted: boolean; activity_muted: boolean }
  >();
  for (const row of friendRows) {
    friendByUser.set(row.user_id, row);
  }

  return targetUserIds.filter((targetUserId) => {
    const prefs = prefsByUser.get(targetUserId);
    // Default true when the row or field is missing (matches getNotificationPreferences fallback).
    if (prefs && (prefs[prefField] as boolean | null | undefined) === false)
      return false;

    const fs = friendByUser.get(targetUserId);
    if (fs) {
      if (fs.muted) return false;
      if (notificationType === "nudge" && fs.nudges_muted) return false;
      if (
        (notificationType === "friend_activity" ||
          notificationType === "friend_personal_best") &&
        fs.activity_muted
      )
        return false;
    }
    return true;
  });
}

export async function shouldSendNotification(
  targetUserId: string,
  senderId: string | null,
  notificationType:
    | "nudge"
    | "flex"
    | "hype"
    | "friend_activity"
    | "friend_personal_best"
    | "competition_invite"
    | "competition_update"
    | "competition_milestone",
): Promise<boolean> {
  const prefs = await getNotificationPreferences(targetUserId);

  // Check global preference for this notification type
  switch (notificationType) {
    case "nudge":
      if (!prefs.nudges_enabled) return false;
      break;
    case "flex":
      if (!prefs.flexes_enabled) return false;
      break;
    case "hype":
      if (!prefs.hypes_enabled) return false;
      break;
    case "friend_activity":
      if (!prefs.friend_activity_enabled) return false;
      break;
    case "friend_personal_best":
      if (!prefs.friend_personal_best_enabled) return false;
      break;
    case "competition_invite":
      if (!prefs.competition_invites_enabled) return false;
      break;
    case "competition_update":
      if (!prefs.competition_updates_enabled) return false;
      break;
    case "competition_milestone":
      if (!prefs.competition_milestones_enabled) return false;
      break;
  }

  // Check friend-specific muting if there's a sender
  if (senderId) {
    const friendSettings = await db.query(
      "SELECT muted, nudges_muted, activity_muted FROM friend_notification_settings WHERE user_id = $1 AND friend_id = $2",
      [targetUserId, senderId],
    );

    if (friendSettings.length > 0) {
      const fs = friendSettings[0];
      if (fs.muted) return false;
      if (notificationType === "nudge" && fs.nudges_muted) return false;
      if (
        (notificationType === "friend_activity" ||
          notificationType === "friend_personal_best") &&
        fs.activity_muted
      )
        return false;
    }
  }

  return true;
}
