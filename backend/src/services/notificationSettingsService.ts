import { PostgresService } from "./DbService.js";
import {
  DEFAULT_WORKOUT_VISIBILITY,
  isWorkoutVisibility,
  type WorkoutVisibility,
} from "./visibilityService.js";

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
  share_live_presence: boolean; // friends may see I'm out on a walk RIGHT NOW (never location)
  weekly_recap_enabled: boolean; // Sunday-evening weekly recap push + story card
  // Monday "new challenge", the mid-week nudge, and the completion
  // celebration. Its OWN category rather than folded into competition_updates:
  // muting competitions must not silently mute this (Guideline 4.5.4).
  weekly_challenge_enabled: boolean;
  h2h_close_friends_only: boolean; // Head-to-Head rivals only from my close friends
  // friend_request_reminder_enabled: the weekly "N people are waiting to be
  // your friend" nudge. Separate from the friend_request push itself, so
  // muting the reminder never mutes the original request.
  friend_request_reminder_enabled: boolean;
  // buddy_invites_enabled: "X wants to walk with you" invites. buddy_invite is
  // high-priority (it bypasses quiet hours and the daily cap because the walk
  // is starting within seconds), so this toggle is the ONLY thing that can
  // silence it — Guideline 4.5.4.
  buddy_invites_enabled: boolean;
  // tagged_posts_on_profile: do collabs I'm tagged in join my profile's Posts
  // grid? Off = Tagged tab only, Instagram-style. Not a notification pref, but
  // this table is the de-facto per-user preferences row. Read through
  // posts.coauthor_on_profile, which overrides it per post.
  tagged_posts_on_profile: boolean;
  // auto_post_without_photo: when I skip the post-run photo prompt, does the
  // rendered route/stats card still go to the feed? Off = a walk reaches the
  // feed only if I attached a photo. Enforced client-side (the app is what
  // builds that card), so this is carry-across-devices storage rather than a
  // gate — the server keeps accepting `is_auto` posts from every build.
  auto_post_without_photo: boolean;
  // auto_posts_on_profile: keep photo-less auto route/stat cards in my profile
  // Posts grid? Off = those cards still reach the feed, but my grid stays
  // photo-first unless that workout also has a story/photo attached.
  auto_posts_on_profile: boolean;
  // Who may see my workout content (routes + photos): 'public' | 'friends' |
  // 'private'. Coarser than share_route_maps — that one decides WHETHER routes
  // are included, this decides WHO gets in at all. Both must pass.
  workout_visibility: WorkoutVisibility;
  // Who may launch the cinematic flyover of my routes. 'friends' | 'self'.
  // share_route_maps still gates the coords themselves; this only puts the
  // guided tour behind its own switch.
  flyover_visibility: FlyoverVisibility;
}

export type FlyoverVisibility = "friends" | "self";
export const DEFAULT_FLYOVER_VISIBILITY: FlyoverVisibility = "friends";
function isFlyoverVisibility(v: unknown): v is FlyoverVisibility {
  return v === "friends" || v === "self";
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
  share_live_presence: true,
  weekly_recap_enabled: true,
  weekly_challenge_enabled: true,
  h2h_close_friends_only: false,
  friend_request_reminder_enabled: true,
  buddy_invites_enabled: true,
  tagged_posts_on_profile: true,
  // TRUE: every installed build posts the card today, and flipping shipped
  // behaviour on deploy would read as a bug, not a preference.
  auto_post_without_photo: true,
  auto_posts_on_profile: true,
  workout_visibility: DEFAULT_WORKOUT_VISIBILITY,
  flyover_visibility: DEFAULT_FLYOVER_VISIBILITY,
};

export async function getNotificationPreferences(
  userId: string,
): Promise<NotificationPreferences> {
  const rows = await db.query(
    "SELECT * FROM notification_settings WHERE user_id = $1",
    [userId],
  );

  if (rows.length === 0) return { ...DEFAULT_PREFERENCES };

  return prefsFromRow(rows[0]);
}

/** A notification_settings row as preferences, every field defaulted. */
function prefsFromRow(row: any): NotificationPreferences {
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
    share_live_presence: row.share_live_presence ?? true,
    weekly_recap_enabled: row.weekly_recap_enabled ?? true,
    weekly_challenge_enabled: row.weekly_challenge_enabled ?? true,
    h2h_close_friends_only: row.h2h_close_friends_only ?? false,
    friend_request_reminder_enabled:
      row.friend_request_reminder_enabled ?? true,
    buddy_invites_enabled: row.buddy_invites_enabled ?? true,
    tagged_posts_on_profile: row.tagged_posts_on_profile ?? true,
    auto_post_without_photo: row.auto_post_without_photo ?? true,
    auto_posts_on_profile: row.auto_posts_on_profile ?? true,
    // Anything unrecognised reads as the safe default rather than being
    // handed to the client as-is.
    workout_visibility: isWorkoutVisibility(row.workout_visibility)
      ? row.workout_visibility
      : DEFAULT_WORKOUT_VISIBILITY,
    flyover_visibility: isFlyoverVisibility(row.flyover_visibility)
      ? row.flyover_visibility
      : DEFAULT_FLYOVER_VISIBILITY,
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
    { key: "share_live_presence", value: prefs.share_live_presence },
    { key: "weekly_recap_enabled", value: prefs.weekly_recap_enabled },
    {
      key: "weekly_challenge_enabled",
      value: prefs.weekly_challenge_enabled,
    },
    { key: "h2h_close_friends_only", value: prefs.h2h_close_friends_only },
    {
      key: "friend_request_reminder_enabled",
      value: prefs.friend_request_reminder_enabled,
    },
    { key: "buddy_invites_enabled", value: prefs.buddy_invites_enabled },
    {
      key: "tagged_posts_on_profile",
      value: prefs.tagged_posts_on_profile,
    },
    {
      key: "auto_post_without_photo",
      value: prefs.auto_post_without_photo,
    },
    {
      key: "auto_posts_on_profile",
      value: prefs.auto_posts_on_profile,
    },
    { key: "workout_visibility", value: prefs.workout_visibility },
    {
      key: "flyover_visibility",
      value: isFlyoverVisibility(prefs.flyover_visibility)
        ? prefs.flyover_visibility
        : undefined,
    },
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

/**
 * The categories a recipient can switch off. One union, shared by the
 * single-recipient check and the batched one, so a new category can't be
 * gated in one and not the other.
 */
export type NotificationCategory =
  | "nudge"
  | "flex"
  | "hype"
  | "friend_activity"
  | "friend_personal_best"
  | "competition_invite"
  | "competition_update"
  | "competition_milestone"
  // Buddy Walks. Deliberately its OWN category rather than reusing "hype"
  // (which every other social push overloads): buddy_invite is in
  // HIGH_PRIORITY_TYPES, so it bypasses quiet hours and the daily cap and
  // this pref is the only thing that can stop it. Overloading "hype" would
  // mean muting hypes to mute buddy invites — not a real toggle (4.5.4).
  | "buddy"
  // Its own category on purpose — see weekly_challenge_enabled above.
  | "weekly_challenge";

/** The recipient's own switch for this category. */
function prefsAllow(
  prefs: NotificationPreferences,
  notificationType: NotificationCategory,
): boolean {
  switch (notificationType) {
    case "nudge":
      return prefs.nudges_enabled;
    case "flex":
      return prefs.flexes_enabled;
    case "hype":
      return prefs.hypes_enabled;
    case "friend_activity":
      return prefs.friend_activity_enabled;
    case "friend_personal_best":
      return prefs.friend_personal_best_enabled;
    case "competition_invite":
      return prefs.competition_invites_enabled;
    case "weekly_challenge":
      return prefs.weekly_challenge_enabled;
    case "competition_update":
      return prefs.competition_updates_enabled;
    case "competition_milestone":
      return prefs.competition_milestones_enabled;
    case "buddy":
      return prefs.buddy_invites_enabled;
  }
}

interface FriendMuteRow {
  user_id: string;
  muted: boolean | null;
  nudges_muted: boolean | null;
  activity_muted: boolean | null;
}

/** The recipient's per-friend mute for this sender, when they set one. */
function friendMuteBlocks(
  fs: FriendMuteRow | undefined,
  notificationType: NotificationCategory,
): boolean {
  if (!fs) return false;
  if (fs.muted) return true;
  if (notificationType === "nudge" && fs.nudges_muted) return true;
  if (
    (notificationType === "friend_activity" ||
      notificationType === "friend_personal_best") &&
    fs.activity_muted
  )
    return true;
  return false;
}

/**
 * Which of `targetUserIds` may be sent this category from `senderId` — the
 * batched form of shouldSendNotification, in TWO queries however many
 * recipients there are. Fan-outs (a buddy invite to a whole crew, a session
 * start to every participant) used to ask per recipient: two round trips
 * each, so a room of eight was sixteen queries before the first push went
 * out. Order is preserved and duplicates collapse.
 */
export async function allowedRecipients(
  targetUserIds: string[],
  senderId: string | null,
  notificationType: NotificationCategory,
): Promise<string[]> {
  const targets = [...new Set(targetUserIds)];
  if (targets.length === 0) return [];

  const [settingsRows, muteRows] = await Promise.all([
    db.query(
      `SELECT * FROM notification_settings WHERE user_id = ANY($1::text[])`,
      [targets],
    ),
    senderId
      ? db.query<FriendMuteRow>(
          `SELECT user_id, muted, nudges_muted, activity_muted
             FROM friend_notification_settings
            WHERE friend_id = $2 AND user_id = ANY($1::text[])`,
          [targets, senderId],
        )
      : Promise.resolve([] as FriendMuteRow[]),
  ]);
  const prefsByUser = new Map(
    settingsRows.map((row: any) => [row.user_id as string, prefsFromRow(row)]),
  );
  const muteByUser = new Map(muteRows.map((r) => [r.user_id, r]));

  return targets.filter((id) => {
    // No settings row = every default (notification_settings is created
    // lazily on first write, so most users have no row).
    const prefs = prefsByUser.get(id) ?? DEFAULT_PREFERENCES;
    if (!prefsAllow(prefs, notificationType)) return false;
    return !friendMuteBlocks(muteByUser.get(id), notificationType);
  });
}

export async function shouldSendNotification(
  targetUserId: string,
  senderId: string | null,
  notificationType: NotificationCategory,
): Promise<boolean> {
  const allowed = await allowedRecipients(
    [targetUserId],
    senderId,
    notificationType,
  );
  return allowed.length === 1;
}
