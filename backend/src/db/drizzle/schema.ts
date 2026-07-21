import {
  pgTable,
  index,
  uuid,
  text,
  timestamp,
  foreignKey,
  unique,
  serial,
  varchar,
  integer,
  doublePrecision,
  numeric,
  date,
  boolean,
  check,
  jsonb,
  inet,
  uniqueIndex,
  bigserial,
  primaryKey,
} from "drizzle-orm/pg-core";
import { sql } from "drizzle-orm";

export const friendNudgeLog = pgTable(
  "friend_nudge_log",
  {
    id: uuid().defaultRandom().primaryKey().notNull(),
    senderId: text("sender_id").notNull(),
    targetId: text("target_id").notNull(),
    createdAt: timestamp("created_at", {
      withTimezone: true,
      mode: "string",
    }).defaultNow(),
  },
  (table) => [
    index("idx_friend_nudge_log_lookup").using(
      "btree",
      table.senderId.asc().nullsLast(),
      table.targetId.asc().nullsLast(),
      table.createdAt.desc().nullsFirst(),
    ),
  ],
);

export const workoutSplits = pgTable(
  "workout_splits",
  {
    id: serial().primaryKey().notNull(),
    workoutId: varchar("workout_id", { length: 255 }).notNull(),
    splitNumber: integer("split_number").notNull(),
    splitDuration: doublePrecision("split_duration").notNull(),
    splitDistance: doublePrecision("split_distance"),
    splitPace: doublePrecision("split_pace"),
  },
  (table) => [
    index("idx_splits_time").using(
      "btree",
      table.splitDuration.asc().nullsLast(),
    ),
    index("idx_splits_workout").using(
      "btree",
      table.workoutId.asc().nullsLast(),
    ),
    foreignKey({
      columns: [table.workoutId],
      foreignColumns: [workouts.workoutId],
      name: "workout_splits_workout_id_fkey",
    }).onDelete("cascade"),
    unique("workout_splits_workout_id_split_number_key").on(
      table.workoutId,
      table.splitNumber,
    ),
  ],
);

export const flexLog = pgTable(
  "flex_log",
  {
    id: uuid().defaultRandom().primaryKey().notNull(),
    senderId: text("sender_id").notNull(),
    targetId: text("target_id").notNull(),
    competitionId: text("competition_id").notNull(),
    message: text(),
    createdAt: timestamp("created_at", {
      withTimezone: true,
      mode: "string",
    }).defaultNow(),
  },
  (table) => [
    index("idx_flex_log_lookup").using(
      "btree",
      table.senderId.asc().nullsLast(),
      table.targetId.asc().nullsLast(),
      table.createdAt.desc().nullsFirst(),
    ),
  ],
);

export const users = pgTable(
  "users",
  {
    userId: text("user_id").primaryKey().notNull(),
    username: varchar({ length: 30 }),
    email: varchar({ length: 255 }),
    firstName: varchar("first_name", { length: 50 }),
    lastName: varchar("last_name", { length: 50 }),
    appleSub: varchar("apple_sub", { length: 255 }).notNull(),
    profileImageUrl: text("profile_image_url"),
    bio: text(),
    role: varchar({ length: 20 }).default("user"),
    goalMiles: numeric("goal_miles").default("1.0").notNull(),
    currentStreak: integer("current_streak").default(0).notNull(),
    // One-time acceptance of the UGC terms / EULA, required before a user can
    // post photos (App Store Guideline 1.2). Null = not yet accepted.
    termsAcceptedAt: timestamp("terms_accepted_at", {
      withTimezone: true,
      mode: "string",
    }),
    // Onboarding personalization captured at signup (all optional — collected on
    // a skippable step). `referralSource` is one of a fixed catalog (app_store,
    // friend, instagram, tiktok, …); `referralDetail` is free text for the
    // "friend's username" / "other" follow-up. `signupGoal` and
    // `experienceLevel` segment users for future personalization + analytics.
    // Nullable with no default so the additive migration is safe for the live
    // table and existing rows read null.
    referralSource: varchar("referral_source", { length: 40 }),
    referralDetail: varchar("referral_detail", { length: 120 }),
    signupGoal: varchar("signup_goal", { length: 40 }),
    experienceLevel: varchar("experience_level", { length: 40 }),
    // Stamped the first time the user submits (or skips) the personalization
    // step, so we never re-show it and can measure onboarding completion.
    onboardingCompletedAt: timestamp("onboarding_completed_at", {
      withTimezone: true,
      mode: "string",
    }),
    // Signup time. Backfilled for existing users from their earliest workout's
    // upload timestamp (MIN(workouts.created_at)) — see migration 0013. New
    // rows default to now() on insert.
    createdAt: timestamp("created_at", {
      withTimezone: true,
      mode: "string",
    })
      .defaultNow()
      .notNull(),
    // Streak-features enrollment stamp (Double Down / Streak Save / Streak
    // Assist). Only the new app build calls the enable endpoint, so null =
    // legacy build → every streak feature is invisible AND inert for this user
    // (their streak math runs the exact legacy path). Mirrors terms_accepted_at.
    streakFeaturesAt: timestamp("streak_features_at", {
      withTimezone: true,
      mode: "string",
    }),
    // Token meters are DERIVED (counted from workouts since the matching
    // last-used date), never stored — these anchors are the only state.
    // Null = never used → the meter window opens at enrollment (with a
    // bounded retroactive lookback).
    doubleDownLastUsed: date("double_down_last_used"),
    streakSaveLastUsed: date("streak_save_last_used"),
    streakAssistLastUsed: date("streak_assist_last_used"),
  },
  (table) => [
    index("idx_users_current_streak_desc").using(
      "btree",
      table.currentStreak.desc().nullsFirst(),
    ),
    index("idx_users_email_trgm").using(
      "gin",
      table.email.asc().nullsLast().op("gin_trgm_ops"),
    ),
    index("idx_users_username").using(
      "btree",
      table.username.asc().nullsLast(),
    ),
    index("idx_users_username_trgm").using(
      "gin",
      table.username.asc().nullsLast().op("gin_trgm_ops"),
    ),
    unique("users_apple_id_key").on(table.email),
    unique("users_apple_sub_key").on(table.appleSub),
  ],
);

export const workouts = pgTable(
  "workouts",
  {
    workoutId: varchar("workout_id", { length: 255 }).primaryKey().notNull(),
    userId: varchar("user_id", { length: 255 }).notNull(),
    distance: doublePrecision().notNull(),
    localDate: date("local_date").notNull(),
    date: date().notNull(),
    timezoneOffset: integer("timezone_offset").notNull(),
    workoutType: varchar("workout_type", { length: 50 }).notNull(),
    deviceEndDate: timestamp("device_end_date", {
      withTimezone: true,
      mode: "string",
    }).notNull(),
    calories: doublePrecision().notNull(),
    totalDuration: doublePrecision("total_duration").notNull(),
    createdAt: timestamp("created_at", {
      withTimezone: true,
      mode: "string",
    }).defaultNow(),
    source: varchar({ length: 20 }).default("healthkit").notNull(),
    originalDistance: doublePrecision("original_distance"),
    originalDuration: doublePrecision("original_duration"),
    steps: integer(),
    // User soft-delete: a deleted workout stops counting toward streaks/miles/
    // badges/competitions but is kept (and kept tombstoned) so a HealthKit
    // re-sync can't resurrect it.
    deletedAt: timestamp("deleted_at", { withTimezone: true, mode: "string" }),
    // Auto-exclusion: set to a reason (e.g. 'vehicle_speed') when a workout's
    // average speed is physically impossible on foot. Excluded workouts don't
    // count but stay visible so the user can see why.
    exclusionReason: text("exclusion_reason"),
    // Soft flag for the suspicious-but-possible speed band — still counts, just
    // surfaced in the UI for the user to review.
    speedFlagged: boolean("speed_flagged").default(false).notNull(),
  },
  (table) => [
    index("idx_workouts_local_date_user_id").using(
      "btree",
      table.localDate.asc().nullsLast(),
      table.userId.asc().nullsLast(),
    ),
    index("idx_workouts_user_device_end").using(
      "btree",
      table.userId.asc().nullsLast(),
      table.deviceEndDate.desc().nullsFirst(),
    ),
    index("idx_workouts_user_local_date").using(
      "btree",
      table.userId.asc().nullsLast(),
      table.localDate.desc().nullsFirst(),
    ),
    unique("workouts_user_workout_unique").on(table.workoutId, table.userId),
  ],
);

// Simplified GPS trace for a workout, synced from HealthKit when available
// (outdoor walks/runs). One row per workout; re-syncs replace the trace in
// place. Points are client-downsampled ([[lat, lng], ...], ~5 decimal places).
export const workoutRoutes = pgTable(
  "workout_routes",
  {
    workoutId: varchar("workout_id", { length: 255 }).primaryKey().notNull(),
    route: jsonb().notNull(),
    pointCount: integer("point_count").notNull(),
    updatedAt: timestamp("updated_at", { withTimezone: true, mode: "string" })
      .defaultNow()
      .notNull(),
  },
  (table) => [
    foreignKey({
      columns: [table.workoutId],
      foreignColumns: [workouts.workoutId],
      name: "workout_routes_workout_id_fkey",
    }).onDelete("cascade"),
  ],
);

export const notificationSettings = pgTable(
  "notification_settings",
  {
    userId: text("user_id").primaryKey().notNull(),
    nudgesEnabled: boolean("nudges_enabled").default(true),
    flexesEnabled: boolean("flexes_enabled").default(true),
    friendActivityEnabled: boolean("friend_activity_enabled").default(true),
    competitionInvitesEnabled: boolean("competition_invites_enabled").default(
      true,
    ),
    competitionUpdatesEnabled: boolean("competition_updates_enabled").default(
      true,
    ),
    competitionMilestonesEnabled: boolean(
      "competition_milestones_enabled",
    ).default(true),
    quietHoursStart: integer("quiet_hours_start"),
    quietHoursEnd: integer("quiet_hours_end"),
    createdAt: timestamp("created_at", {
      withTimezone: true,
      mode: "string",
    }).defaultNow(),
    updatedAt: timestamp("updated_at", {
      withTimezone: true,
      mode: "string",
    }).defaultNow(),
    hypesEnabled: boolean("hypes_enabled").default(true).notNull(),
    stepGoalEnabled: boolean("step_goal_enabled").default(true).notNull(),
    friendPersonalBestEnabled: boolean("friend_personal_best_enabled").default(
      true,
    ),
    dailyReminderEnabled: boolean("daily_reminder_enabled").default(true),
    dailyReminderHour: integer("daily_reminder_hour").default(18),
    // Head-to-Head rivals drawn only from the user's close-friends list.
    // Not a notification pref, but this table is the de-facto per-user
    // preferences row (see share_workouts_to_feed / share_route_maps).
    h2hCloseFriendsOnly: boolean("h2h_close_friends_only")
      .default(false)
      .notNull(),
    timezoneOffsetMinutes: integer("timezone_offset_minutes"),
    // Social feed settings (added v2). share_workouts_to_feed: include my raw
    // walks/runs as activity cards in friends' unified feed. friend_posts_enabled:
    // notify me when a friend shares a new photo post.
    shareWorkoutsToFeed: boolean("share_workouts_to_feed").default(true),
    friendPostsEnabled: boolean("friend_posts_enabled").default(true),
    // share_route_maps: expose my GPS route maps (workout_routes traces) on my
    // feed entries/posts. Explicit consent surface — when off, friends see the
    // cards without the route slide/map.
    shareRouteMaps: boolean("share_route_maps").default(true),
    // weekly_recap_enabled: Sunday-evening "Your week" recap push + story card.
    weeklyRecapEnabled: boolean("weekly_recap_enabled").default(true),
    // workout_visibility: who may see my workout CONTENT — routes and photos.
    // 'friends' (the default, and what every user effectively has today) =
    // accepted friends only, the same circle the feed uses. 'public' = any
    // signed-in user. 'private' = nobody but me.
    //
    // This is a coarser, content-level gate that sits ABOVE share_route_maps:
    // visibility decides WHO, share_route_maps decides WHETHER routes are part
    // of what they get. Both must pass.
    workoutVisibility: text("workout_visibility").default("friends").notNull(),
  },
  (table) => [
    check(
      "notification_settings_workout_visibility_check",
      sql`workout_visibility = ANY (ARRAY['public'::text, 'friends'::text, 'private'::text])`,
    ),
  ],
);

// One row per (user, week) the recap push was sent for — the cron runs hourly
// to catch every timezone's Sunday evening, so this is what makes it fire
// exactly once per user per week. week_start = the Monday of the recapped week.
export const weeklyRecapLog = pgTable(
  "weekly_recap_log",
  {
    userId: text("user_id").notNull(),
    weekStart: date("week_start", { mode: "string" }).notNull(),
    sentAt: timestamp("sent_at", {
      withTimezone: true,
      mode: "string",
    }).defaultNow(),
  },
  (table) => [
    primaryKey({
      columns: [table.userId, table.weekStart],
      name: "weekly_recap_log_pkey",
    }),
  ],
);

export const competitions = pgTable(
  "competitions",
  {
    id: varchar({ length: 32 })
      .default(sql`replace((gen_random_uuid())::text, '-'::text, ''::text)`)
      .primaryKey()
      .notNull(),
    competitionName: varchar("competition_name", { length: 100 }),
    startDate: date("start_date"),
    endDate: date("end_date"),
    workouts: jsonb().notNull(),
    type: varchar({ length: 20 }).notNull(),
    options: jsonb().notNull(),
    ended: boolean().default(false),
    winner: text(),
    owner: text(),
    createdAt: timestamp("created_at", {
      withTimezone: true,
      mode: "string",
    }).defaultNow(),
    updatedAt: timestamp("updated_at", {
      withTimezone: true,
      mode: "string",
    }).defaultNow(),
  },
  (table) => [
    index("idx_competitions_winner")
      .using("btree", table.winner.asc().nullsLast())
      .where(sql`(winner IS NOT NULL)`),
    foreignKey({
      columns: [table.winner],
      foreignColumns: [users.userId],
      name: "competitions_winner_fkey",
    }).onDelete("set null"),
    foreignKey({
      columns: [table.owner],
      foreignColumns: [users.userId],
      name: "competitions_owner_fkey",
    }).onDelete("set null"),
    check(
      "competitions_type_check",
      sql`(type)::text = ANY ((ARRAY['streaks'::character varying, 'apex'::character varying, 'clash'::character varying, 'targets'::character varying, 'race'::character varying])::text[])`,
    ),
  ],
);

export const refreshTokens = pgTable(
  "refresh_tokens",
  {
    tokenId: uuid("token_id").defaultRandom().primaryKey().notNull(),
    userId: varchar("user_id", { length: 32 }).notNull(),
    tokenHash: varchar("token_hash", { length: 64 }).notNull(),
    tokenFamilyId: uuid("token_family_id").notNull(),
    createdAt: timestamp("created_at", { mode: "string" })
      .defaultNow()
      .notNull(),
    lastUsedAt: timestamp("last_used_at", { mode: "string" })
      .defaultNow()
      .notNull(),
    expiresAt: timestamp("expires_at", { mode: "string" }),
    revokedAt: timestamp("revoked_at", { mode: "string" }),
    revokedReason: varchar("revoked_reason", { length: 50 }),
    replacedByHash: varchar("replaced_by_hash", { length: 64 }),
    userAgent: text("user_agent"),
    ipAddress: inet("ip_address"),
    deviceInfo: jsonb("device_info"),
  },
  (table) => [
    index("idx_refresh_tokens_family_id").using(
      "btree",
      table.tokenFamilyId.asc().nullsLast(),
    ),
    index("idx_refresh_tokens_revoked_at")
      .using("btree", table.revokedAt.asc().nullsLast())
      .where(sql`(revoked_at IS NULL)`),
    index("idx_refresh_tokens_token_hash").using(
      "btree",
      table.tokenHash.asc().nullsLast(),
    ),
    index("idx_refresh_tokens_user_id").using(
      "btree",
      table.userId.asc().nullsLast(),
    ),
    foreignKey({
      columns: [table.userId],
      foreignColumns: [users.userId],
      name: "refresh_tokens_user_id_fkey",
    }).onDelete("cascade"),
    unique("refresh_tokens_token_hash_key").on(table.tokenHash),
  ],
);

export const deviceTokens = pgTable(
  "device_tokens",
  {
    id: uuid().defaultRandom().primaryKey().notNull(),
    userId: text("user_id").notNull(),
    deviceToken: text("device_token").notNull(),
    environment: text().default("production").notNull(),
    createdAt: timestamp("created_at", {
      withTimezone: true,
      mode: "string",
    }).defaultNow(),
    updatedAt: timestamp("updated_at", {
      withTimezone: true,
      mode: "string",
    }).defaultNow(),
  },
  (table) => [
    index("idx_device_tokens_user_id").using(
      "btree",
      table.userId.asc().nullsLast(),
    ),
    foreignKey({
      columns: [table.userId],
      foreignColumns: [users.userId],
      name: "device_tokens_user_id_fkey",
    }).onDelete("cascade"),
    unique("device_tokens_user_id_device_token_key").on(
      table.userId,
      table.deviceToken,
    ),
  ],
);

export const pendingNotifications = pgTable(
  "pending_notifications",
  {
    id: uuid().defaultRandom().primaryKey().notNull(),
    userId: text("user_id").notNull(),
    type: text().notNull(),
    competitionId: text("competition_id"),
    competitionName: text("competition_name"),
    createdAt: timestamp("created_at", {
      withTimezone: true,
      mode: "string",
    }).defaultNow(),
    sentAt: timestamp("sent_at", { withTimezone: true, mode: "string" }),
  },
  (table) => [
    index("idx_pending_notifications_unsent")
      .using("btree", table.userId.asc().nullsLast())
      .where(sql`(sent_at IS NULL)`),
    foreignKey({
      columns: [table.userId],
      foreignColumns: [users.userId],
      name: "pending_notifications_user_id_fkey",
    }).onDelete("cascade"),
  ],
);

export const nudgeLog = pgTable(
  "nudge_log",
  {
    id: uuid().defaultRandom().primaryKey().notNull(),
    competitionId: text("competition_id").notNull(),
    senderId: text("sender_id").notNull(),
    targetId: text("target_id").notNull(),
    createdAt: timestamp("created_at", {
      withTimezone: true,
      mode: "string",
    }).defaultNow(),
  },
  (table) => [
    index("idx_nudge_log_lookup").using(
      "btree",
      table.competitionId.asc().nullsLast(),
      table.senderId.asc().nullsLast(),
      table.targetId.asc().nullsLast(),
      table.createdAt.asc().nullsLast(),
    ),
    index("idx_nudge_log_rate_limit").using(
      "btree",
      table.competitionId.asc().nullsLast(),
      table.senderId.asc().nullsLast(),
      table.targetId.asc().nullsLast(),
      table.createdAt.asc().nullsLast(),
    ),
  ],
);

export const workoutCompletionNotifications = pgTable(
  "workout_completion_notifications",
  {
    id: uuid().defaultRandom().primaryKey().notNull(),
    userId: text("user_id").notNull(),
    notifiedDate: date("notified_date").notNull(),
    createdAt: timestamp("created_at", {
      withTimezone: true,
      mode: "string",
    }).defaultNow(),
  },
  (table) => [
    unique("workout_completion_notifications_user_id_notified_date_key").on(
      table.userId,
      table.notifiedDate,
    ),
  ],
);

export const milestoneNotifications = pgTable(
  "milestone_notifications",
  {
    id: uuid().defaultRandom().primaryKey().notNull(),
    milestoneKey: text("milestone_key").notNull(),
    competitionId: text("competition_id"),
    userId: text("user_id"),
    createdAt: timestamp("created_at", {
      withTimezone: true,
      mode: "string",
    }).defaultNow(),
  },
  (table) => [
    unique("milestone_notifications_milestone_key_key").on(table.milestoneKey),
  ],
);

export const badges = pgTable(
  "badges",
  {
    badgeId: text("badge_id").primaryKey().notNull(),
    category: text().notNull(),
    name: text().notNull(),
    description: text().notNull(),
    icon: text().notNull(),
    rarity: text().notNull(),
    requirement: numeric(),
    isHidden: boolean("is_hidden").default(false).notNull(),
    sortOrder: integer("sort_order").default(0).notNull(),
    createdAt: timestamp("created_at", { withTimezone: true, mode: "string" })
      .defaultNow()
      .notNull(),
  },
  (table) => [
    index("idx_badges_category").using(
      "btree",
      table.category.asc().nullsLast(),
    ),
    check(
      "badges_rarity_check",
      sql`rarity = ANY (ARRAY['common'::text, 'rare'::text, 'legendary'::text])`,
    ),
  ],
);

export const userBadges = pgTable(
  "user_badges",
  {
    id: bigserial({ mode: "bigint" }).primaryKey().notNull(),
    userId: text("user_id").notNull(),
    badgeId: text("badge_id").notNull(),
    earnedAt: timestamp("earned_at", { withTimezone: true, mode: "string" })
      .defaultNow()
      .notNull(),
    isNew: boolean("is_new").default(true).notNull(),
    triggeringWorkoutId: varchar("triggering_workout_id", { length: 255 }),
    progressSnapshot: jsonb("progress_snapshot"),
    pinSlot: integer("pin_slot"),
  },
  (table) => [
    index("idx_user_badges_user").using(
      "btree",
      table.userId.asc().nullsLast(),
    ),
    index("idx_user_badges_user_new")
      .using("btree", table.userId.asc().nullsLast())
      .where(sql`(is_new = true)`),
    uniqueIndex("idx_user_badges_user_pin_slot")
      .using(
        "btree",
        table.userId.asc().nullsLast(),
        table.pinSlot.asc().nullsLast(),
      )
      .where(sql`(pin_slot IS NOT NULL)`),
    index("idx_user_badges_workout").using(
      "btree",
      table.triggeringWorkoutId.asc().nullsLast(),
    ),
    foreignKey({
      columns: [table.userId],
      foreignColumns: [users.userId],
      name: "user_badges_user_id_fkey",
    }).onDelete("cascade"),
    foreignKey({
      columns: [table.badgeId],
      foreignColumns: [badges.badgeId],
      name: "user_badges_badge_id_fkey",
    }).onDelete("cascade"),
    foreignKey({
      columns: [table.triggeringWorkoutId],
      foreignColumns: [workouts.workoutId],
      name: "user_badges_triggering_workout_id_fkey",
    }).onDelete("set null"),
    unique("user_badges_user_id_badge_id_key").on(table.userId, table.badgeId),
    check(
      "user_badges_pin_slot_range",
      sql`(pin_slot IS NULL) OR ((pin_slot >= 0) AND (pin_slot <= 2))`,
    ),
  ],
);

export const inAppNotifications = pgTable(
  "in_app_notifications",
  {
    id: uuid().defaultRandom().primaryKey().notNull(),
    userId: text("user_id").notNull(),
    title: text().notNull(),
    body: text().notNull(),
    type: text().notNull(),
    data: jsonb().default({}),
    isRead: boolean("is_read").default(false),
    createdAt: timestamp("created_at", {
      withTimezone: true,
      mode: "string",
    }).defaultNow(),
  },
  (table) => [
    index("idx_in_app_notifications_unread")
      .using(
        "btree",
        table.userId.asc().nullsLast(),
        table.isRead.asc().nullsLast(),
      )
      .where(sql`(is_read = false)`),
    index("idx_in_app_notifications_user").using(
      "btree",
      table.userId.asc().nullsLast(),
      table.createdAt.desc().nullsFirst(),
    ),
    foreignKey({
      columns: [table.userId],
      foreignColumns: [users.userId],
      name: "in_app_notifications_user_id_fkey",
    }),
  ],
);

export const notificationLog = pgTable(
  "notification_log",
  {
    id: uuid().defaultRandom().primaryKey().notNull(),
    userId: text("user_id").notNull(),
    type: text().notNull(),
    createdAt: timestamp("created_at", {
      withTimezone: true,
      mode: "string",
    }).defaultNow(),
  },
  (table) => [
    index("idx_notification_log_user_date").using(
      "btree",
      table.userId.asc().nullsLast(),
      table.createdAt.asc().nullsLast(),
    ),
  ],
);

export const userChallengeCompletions = pgTable(
  "user_challenge_completions",
  {
    id: bigserial({ mode: "bigint" }).primaryKey().notNull(),
    userId: text("user_id").notNull(),
    localDate: date("local_date").notNull(),
    challengeKey: text("challenge_key").notNull(),
    completedAt: timestamp("completed_at", {
      withTimezone: true,
      mode: "string",
    })
      .defaultNow()
      .notNull(),
    completingWorkoutId: varchar("completing_workout_id", { length: 255 }),
  },
  (table) => [
    index("idx_ucc_user").using("btree", table.userId.asc().nullsLast()),
    index("idx_ucc_user_date").using(
      "btree",
      table.userId.asc().nullsLast(),
      table.localDate.desc().nullsFirst(),
    ),
    foreignKey({
      columns: [table.userId],
      foreignColumns: [users.userId],
      name: "user_challenge_completions_user_id_fkey",
    }).onDelete("cascade"),
    foreignKey({
      columns: [table.challengeKey],
      foreignColumns: [dailyChallenges.challengeKey],
      name: "user_challenge_completions_challenge_key_fkey",
    }),
    foreignKey({
      columns: [table.completingWorkoutId],
      foreignColumns: [workouts.workoutId],
      name: "user_challenge_completions_completing_workout_id_fkey",
    }).onDelete("set null"),
    unique("user_challenge_completions_user_id_local_date_key").on(
      table.userId,
      table.localDate,
    ),
  ],
);

export const h2hMatchups = pgTable(
  "h2h_matchups",
  {
    localDate: date("local_date").notNull(),
    userId: text("user_id").notNull(),
    rivalId: text("rival_id").notNull(),
    // TRUE only when this row is half of a reciprocal pair (both users see
    // each other). Fallback assignments (odd-one-out, mid-day joiners) are FALSE.
    mutual: boolean().default(false).notNull(),
    createdAt: timestamp("created_at", { withTimezone: true, mode: "string" })
      .defaultNow()
      .notNull(),
    // Stamped by the end-of-day cron once the duel outcome is final.
    // `won` is TRUE only when the user won AND the completion row was inserted.
    resolvedAt: timestamp("resolved_at", {
      withTimezone: true,
      mode: "string",
    }),
    won: boolean(),
    // Stamped when the winner push was sent (deferred to the winner's local morning).
    notifiedAt: timestamp("notified_at", {
      withTimezone: true,
      mode: "string",
    }),
  },
  (table) => [
    foreignKey({
      columns: [table.userId],
      foreignColumns: [users.userId],
      name: "h2h_matchups_user_id_fkey",
    }).onDelete("cascade"),
    foreignKey({
      columns: [table.rivalId],
      foreignColumns: [users.userId],
      name: "h2h_matchups_rival_id_fkey",
    }).onDelete("cascade"),
    primaryKey({
      columns: [table.localDate, table.userId],
      name: "h2h_matchups_pkey",
    }),
  ],
);

export const dailyChallenges = pgTable(
  "daily_challenges",
  {
    challengeKey: text("challenge_key").primaryKey().notNull(),
    title: text().notNull(),
    descriptionTemplate: text("description_template").notNull(),
    icon: text().notNull(),
    gradientStart: text("gradient_start").notNull(),
    gradientEnd: text("gradient_end").notNull(),
    type: text().notNull(),
    active: boolean().default(true).notNull(),
    rotationIndex: integer("rotation_index").notNull(),
    createdAt: timestamp("created_at", { withTimezone: true, mode: "string" })
      .defaultNow()
      .notNull(),
  },
  (table) => [
    unique("daily_challenges_rotation_index_key").on(table.rotationIndex),
    check(
      "daily_challenges_type_check",
      sql`type = ANY (ARRAY['pace'::text, 'distance'::text, 'time'::text, 'activity'::text, 'steps'::text, 'social'::text])`,
    ),
  ],
);

export const hypeLog = pgTable(
  "hype_log",
  {
    id: uuid().defaultRandom().primaryKey().notNull(),
    senderId: text("sender_id").notNull(),
    targetId: text("target_id").notNull(),
    createdAt: timestamp("created_at", {
      withTimezone: true,
      mode: "string",
    }).defaultNow(),
    contextType: text("context_type"),
    contextId: text("context_id"),
    contextLabel: text("context_label"),
  },
  (table) => [
    uniqueIndex("hype_log_context_dedupe_idx")
      .using(
        "btree",
        table.senderId.asc().nullsLast(),
        table.targetId.asc().nullsLast(),
        table.contextType.asc().nullsLast(),
        table.contextId.asc().nullsLast(),
      )
      .where(sql`(context_id IS NOT NULL)`),
    index("idx_hype_log_lookup").using(
      "btree",
      table.senderId.asc().nullsLast(),
      table.createdAt.desc().nullsFirst(),
    ),
    // Feed hype tallies count a target's hypes with NO sender filter
    // (COUNT(DISTINCT sender_id) per post/workout), so the sender-leading
    // indexes above can't serve them and every feed row fell back to a
    // hype_log scan. Lead with target_id + context, and carry sender_id as a
    // trailing covering column so the DISTINCT count stays index-only.
    index("idx_hype_log_target_context")
      .using(
        "btree",
        table.targetId.asc().nullsLast(),
        table.contextType.asc().nullsLast(),
        table.contextId.asc().nullsLast(),
        table.senderId.asc().nullsLast(),
      )
      .where(sql`(context_id IS NOT NULL)`),
  ],
);

export const pendingFriendNotifications = pgTable(
  "pending_friend_notifications",
  {
    id: bigserial({ mode: "bigint" }).primaryKey().notNull(),
    userId: text("user_id").notNull(),
    eventType: text("event_type").notNull(),
    activityType: text("activity_type").default("").notNull(),
    workoutId: text("workout_id"),
    payload: jsonb().notNull(),
    localDate: date("local_date").notNull(),
    status: text().default("pending").notNull(),
    createdAt: timestamp("created_at", { withTimezone: true, mode: "string" })
      .defaultNow()
      .notNull(),
    // When set, this row is auto-sent by the pending-send cron once NOW() passes
    // it (used to defer + merge a mile-completion push ~10 min so a photo can
    // ride along). NULL = the legacy user-confirmation ("ask") flow.
    sendAfterAt: timestamp("send_after_at", {
      withTimezone: true,
      mode: "string",
    }),
  },
  (table) => [
    index("idx_pending_friend_notif_user").using(
      "btree",
      table.userId.asc().nullsLast(),
      table.status.asc().nullsLast(),
    ),
    uniqueIndex("uq_pending_friend_notif_workout")
      .using(
        "btree",
        table.userId.asc().nullsLast(),
        table.eventType.asc().nullsLast(),
        table.workoutId.asc().nullsLast(),
      )
      .where(sql`((workout_id IS NOT NULL) AND (status = 'pending'::text))`),
    check(
      "pending_friend_notifications_status_check",
      sql`status = ANY (ARRAY['pending'::text, 'sent'::text, 'dismissed'::text, 'expired'::text])`,
    ),
  ],
);

export const friendships = pgTable(
  "friendships",
  {
    userId: text("user_id").notNull(),
    friendId: text("friend_id").notNull(),
    status: text().default("pending").notNull(),
  },
  (table) => [
    index("idx_friendships_friend_status").using(
      "btree",
      table.friendId.asc().nullsLast(),
      table.status.asc().nullsLast(),
    ),
    index("idx_friendships_user_status").using(
      "btree",
      table.userId.asc().nullsLast(),
      table.status.asc().nullsLast(),
    ),
    foreignKey({
      columns: [table.userId],
      foreignColumns: [users.userId],
      name: "friendships_user_id_fkey",
    }).onDelete("cascade"),
    foreignKey({
      columns: [table.friendId],
      foreignColumns: [users.userId],
      name: "friendships_friend_id_fkey",
    }).onDelete("cascade"),
    primaryKey({
      columns: [table.userId, table.friendId],
      name: "friendships_pkey",
    }),
    unique("unique_friendship_pair").on(table.userId, table.friendId),
  ],
);

export const closeFriends = pgTable(
  "close_friends",
  {
    userId: text("user_id").notNull(),
    closeFriendId: text("close_friend_id").notNull(),
    createdAt: timestamp("created_at", { withTimezone: true, mode: "string" })
      .defaultNow()
      .notNull(),
  },
  (table) => [
    index("idx_close_friends_friend").using(
      "btree",
      table.closeFriendId.asc().nullsLast(),
    ),
    primaryKey({
      columns: [table.userId, table.closeFriendId],
      name: "close_friends_pkey",
    }),
  ],
);

export const dailySteps = pgTable(
  "daily_steps",
  {
    userId: text("user_id").notNull(),
    localDate: date("local_date").notNull(),
    steps: integer().notNull(),
    timezoneOffset: integer("timezone_offset").notNull(),
    updatedAt: timestamp("updated_at", { withTimezone: true, mode: "string" })
      .defaultNow()
      .notNull(),
  },
  (table) => [
    index("idx_daily_steps_user_date").using(
      "btree",
      table.userId.asc().nullsLast(),
      table.localDate.desc().nullsFirst(),
    ),
    foreignKey({
      columns: [table.userId],
      foreignColumns: [users.userId],
      name: "daily_steps_user_id_fkey",
    }).onDelete("cascade"),
    primaryKey({
      columns: [table.userId, table.localDate],
      name: "daily_steps_pkey",
    }),
    check("daily_steps_steps_check", sql`steps >= 0`),
  ],
);

// One row = one missed local day that still counts toward the user's streak.
// The SINGLE substrate all three streak tokens converge on: Double Down writes
// kind 'double_down_recover', an auto-consumed Streak Save writes 'streak_save',
// and a friend's rescue writes 'streak_assist' (source_user = the giver). The
// composite PK makes every write idempotent (ON CONFLICT DO NOTHING) — the
// upload-vs-sweep race defense — and means a day can only ever be covered once.
export const streakCoverage = pgTable(
  "streak_coverage",
  {
    userId: text("user_id").notNull(),
    localDate: date("local_date").notNull(),
    kind: varchar({ length: 32 }).notNull(),
    // The local day whose activity triggered the coverage (e.g. the 2× run
    // day for a Double Down, the giver's day for an Assist).
    triggerDate: date("trigger_date"),
    // Assist only: who rescued this user. Plain text (no FK) so a deleted
    // giver never blocks the receiver's history.
    sourceUser: text("source_user"),
    createdAt: timestamp("created_at", { withTimezone: true, mode: "string" })
      .defaultNow()
      .notNull(),
  },
  (table) => [
    foreignKey({
      columns: [table.userId],
      foreignColumns: [users.userId],
      name: "streak_coverage_user_id_fkey",
    }).onDelete("cascade"),
    primaryKey({
      columns: [table.userId, table.localDate],
      name: "streak_coverage_pkey",
    }),
  ],
);

// Streak lifecycle events, currently just kind 'break': stamped once by the
// sweep when an enrolled user's streak actually breaks (no token covered it).
// Drives the "you can save your friend" flow — assist eligibility reads it,
// and the ON CONFLICT-guarded insert doubles as the push de-dupe so hourly
// sweep re-runs never re-notify.
export const streakEvents = pgTable(
  "streak_events",
  {
    userId: text("user_id").notNull(),
    localDate: date("local_date").notNull(),
    kind: varchar({ length: 24 }).notNull(),
    // Length of the streak that ended (what an assist would restore).
    priorStreak: integer("prior_streak").default(0).notNull(),
    createdAt: timestamp("created_at", { withTimezone: true, mode: "string" })
      .defaultNow()
      .notNull(),
  },
  (table) => [
    foreignKey({
      columns: [table.userId],
      foreignColumns: [users.userId],
      name: "streak_events_user_id_fkey",
    }).onDelete("cascade"),
    primaryKey({
      columns: [table.userId, table.localDate, table.kind],
      name: "streak_events_pkey",
    }),
  ],
);

export const notificationAudienceSettings = pgTable(
  "notification_audience_settings",
  {
    userId: text("user_id").notNull(),
    direction: text().notNull(),
    eventType: text("event_type").notNull(),
    activityType: text("activity_type").default("").notNull(),
    audience: text().notNull(),
    updatedAt: timestamp("updated_at", { withTimezone: true, mode: "string" })
      .defaultNow()
      .notNull(),
  },
  (table) => [
    primaryKey({
      columns: [
        table.userId,
        table.direction,
        table.eventType,
        table.activityType,
      ],
      name: "notification_audience_settings_pkey",
    }),
    check(
      "notification_audience_settings_direction_check",
      sql`direction = ANY (ARRAY['outgoing'::text, 'incoming'::text])`,
    ),
    check(
      "notification_audience_settings_audience_check",
      sql`audience = ANY (ARRAY['none'::text, 'close'::text, 'all'::text, 'ask'::text, 'match_run'::text])`,
    ),
  ],
);

export const friendNotificationSettings = pgTable(
  "friend_notification_settings",
  {
    userId: text("user_id").notNull(),
    friendId: text("friend_id").notNull(),
    muted: boolean().default(false).notNull(),
    nudgesMuted: boolean("nudges_muted").default(false).notNull(),
    activityMuted: boolean("activity_muted").default(false).notNull(),
    createdAt: timestamp("created_at", {
      withTimezone: true,
      mode: "string",
    }).defaultNow(),
    updatedAt: timestamp("updated_at", {
      withTimezone: true,
      mode: "string",
    }).defaultNow(),
  },
  (table) => [
    primaryKey({
      columns: [table.userId, table.friendId],
      name: "friend_notification_settings_pkey",
    }),
  ],
);

export const competitionUsers = pgTable(
  "competition_users",
  {
    competitionId: text("competition_id").notNull(),
    userId: text("user_id").notNull(),
    progress: jsonb(),
    inviteStatus: varchar("invite_status", { length: 20 }),
    placement: integer(),
    lastKnownRank: integer("last_known_rank"),
    lastKnownScore: doublePrecision("last_known_score"),
    lastRankUpdatedAt: timestamp("last_rank_updated_at", {
      withTimezone: true,
      mode: "string",
    }),
  },
  (table) => [
    index("idx_competition_users_comp").using(
      "btree",
      table.competitionId.asc().nullsLast(),
    ),
    index("idx_competition_users_competition").using(
      "btree",
      table.competitionId.asc().nullsLast(),
    ),
    index("idx_competition_users_rank_cache")
      .using(
        "btree",
        table.competitionId.asc().nullsLast(),
        table.lastKnownRank.asc().nullsLast(),
      )
      .where(sql`((invite_status)::text = 'accepted'::text)`),
    index("idx_competition_users_user").using(
      "btree",
      table.userId.asc().nullsLast(),
    ),
    index("idx_competition_users_user_status").using(
      "btree",
      table.userId.asc().nullsLast(),
      table.inviteStatus.asc().nullsLast(),
    ),
    foreignKey({
      columns: [table.userId],
      foreignColumns: [users.userId],
      name: "competition_users_user_id_fkey",
    }).onDelete("cascade"),
    foreignKey({
      columns: [table.competitionId],
      foreignColumns: [competitions.id],
      name: "competition_users_competition_id_fkey",
    }).onDelete("cascade"),
    primaryKey({
      columns: [table.competitionId, table.userId],
      name: "competition_users_pkey",
    }),
    check(
      "competition_users_invite_status_check",
      sql`(invite_status)::text = ANY ((ARRAY['pending'::character varying, 'accepted'::character varying, 'declined'::character varying])::text[])`,
    ),
  ],
);

// User-generated social posts. A single row is the unit of content (photo +
// optional caption + denormalized run stats) and can be surfaced as a Story
// (24h ephemeral, share_to_story) and/or in the permanent Feed (share_to_feed).
// The photo is uploaded flattened (overlay baked in) to /uploads/posts/.
export const posts = pgTable(
  "posts",
  {
    postId: uuid("post_id").defaultRandom().primaryKey().notNull(),
    userId: text("user_id").notNull(),
    mediaUrl: text("media_url").notNull(),
    caption: text(),
    workoutId: varchar("workout_id", { length: 255 }),
    // Denormalized {distance, pace, duration, streak, date} captured at post time
    // so the post survives later edits/deletes of the underlying workout.
    statsSnapshot: jsonb("stats_snapshot"),
    localDate: date("local_date").notNull(),
    shareToFeed: boolean("share_to_feed").default(true).notNull(),
    shareToStory: boolean("share_to_story").default(false).notNull(),
    // Absolute expiry (created_at + 24h) set only when shared to story.
    storyExpiresAt: timestamp("story_expires_at", {
      withTimezone: true,
      mode: "string",
    }),
    createdAt: timestamp("created_at", { withTimezone: true, mode: "string" })
      .defaultNow()
      .notNull(),
    deletedAt: timestamp("deleted_at", { withTimezone: true, mode: "string" }),
    // Auto-generated post (the route/stats card published when the user skips
    // the photo prompt) vs a deliberate user post. An auto post may be replaced
    // in place by a user post; a live user post blocks re-posting for the same
    // workout until it's deleted (one deliberate post per workout).
    isAuto: boolean("is_auto").default(false).notNull(),
    // Whether the post surfaces the workout's route map alongside the photo.
    includeRoute: boolean("include_route").default(true).notNull(),
    // Instagram-style collab post: the author invites ONE accepted friend as
    // coauthor ('pending' → 'accepted'; decline clears all three columns).
    // Once accepted the post reaches both friend circles, shows on both
    // profiles, and coauthor_workout_id (their mile that day, linked at
    // accept time) suppresses their duplicate raw-workout feed entry.
    coauthorUserId: text("coauthor_user_id"),
    coauthorStatus: text("coauthor_status"),
    coauthorWorkoutId: varchar("coauthor_workout_id", { length: 255 }),
  },
  (table) => [
    index("idx_posts_user_created").using(
      "btree",
      table.userId.asc().nullsLast(),
      table.createdAt.desc().nullsFirst(),
    ),
    index("idx_posts_feed")
      .using("btree", table.createdAt.desc().nullsFirst())
      .where(sql`(deleted_at IS NULL AND share_to_feed)`),
    index("idx_posts_story_active")
      .using(
        "btree",
        table.userId.asc().nullsLast(),
        table.storyExpiresAt.asc().nullsLast(),
      )
      .where(sql`(deleted_at IS NULL AND share_to_story)`),
    // One live FEED post per workout — lets a run's auto route/stats post be
    // replaced in place by a promoted photo (upsert by workout_id) instead of
    // creating a second feed item. Story-only posts are exempt so a run can
    // have both its feed record and an ephemeral story photo.
    uniqueIndex("uq_posts_workout_active")
      .on(table.workoutId)
      .where(
        sql`(deleted_at IS NULL AND workout_id IS NOT NULL AND share_to_feed)`,
      ),
    // ...and one live story-only photo per workout (retakes replace in place).
    uniqueIndex("uq_posts_workout_story")
      .on(table.workoutId)
      .where(
        sql`(deleted_at IS NULL AND workout_id IS NOT NULL AND share_to_story AND NOT share_to_feed)`,
      ),
    foreignKey({
      columns: [table.userId],
      foreignColumns: [users.userId],
      name: "posts_user_id_fkey",
    }).onDelete("cascade"),
    foreignKey({
      columns: [table.workoutId],
      foreignColumns: [workouts.workoutId],
      name: "posts_workout_id_fkey",
    }).onDelete("set null"),
    foreignKey({
      columns: [table.coauthorUserId],
      foreignColumns: [users.userId],
      name: "posts_coauthor_user_id_fkey",
    }).onDelete("set null"),
    foreignKey({
      columns: [table.coauthorWorkoutId],
      foreignColumns: [workouts.workoutId],
      name: "posts_coauthor_workout_id_fkey",
    }).onDelete("set null"),
    // Enum-only (no null-pairing) so the coauthor account-deletion SET NULL
    // can't violate it; queries always key on user_id + status together.
    check(
      "posts_coauthor_status_check",
      sql`coauthor_status IS NULL OR coauthor_status = ANY (ARRAY['pending'::text, 'accepted'::text])`,
    ),
  ],
);

// One row per (story, viewer) — powers the "unviewed first" ordering and the
// seen-ring state in the stories rail.
export const storyViews = pgTable(
  "story_views",
  {
    postId: uuid("post_id").notNull(),
    viewerId: text("viewer_id").notNull(),
    viewedAt: timestamp("viewed_at", { withTimezone: true, mode: "string" })
      .defaultNow()
      .notNull(),
  },
  (table) => [
    foreignKey({
      columns: [table.postId],
      foreignColumns: [posts.postId],
      name: "story_views_post_id_fkey",
    }).onDelete("cascade"),
    foreignKey({
      columns: [table.viewerId],
      foreignColumns: [users.userId],
      name: "story_views_viewer_id_fkey",
    }).onDelete("cascade"),
    primaryKey({
      columns: [table.postId, table.viewerId],
      name: "story_views_pkey",
    }),
  ],
);

// One emoji reaction per (story, user) — the ephemeral counterpart to feed
// hype. Re-reacting replaces the emoji. Shown to the author in the
// "seen by" list and pushed as a lightweight notification.
export const storyReactions = pgTable(
  "story_reactions",
  {
    postId: uuid("post_id").notNull(),
    userId: text("user_id").notNull(),
    emoji: varchar({ length: 16 }).notNull(),
    createdAt: timestamp("created_at", { withTimezone: true, mode: "string" })
      .defaultNow()
      .notNull(),
  },
  (table) => [
    foreignKey({
      columns: [table.postId],
      foreignColumns: [posts.postId],
      name: "story_reactions_post_id_fkey",
    }).onDelete("cascade"),
    foreignKey({
      columns: [table.userId],
      foreignColumns: [users.userId],
      name: "story_reactions_user_id_fkey",
    }).onDelete("cascade"),
    primaryKey({
      columns: [table.postId, table.userId],
      name: "story_reactions_pkey",
    }),
  ],
);

// Abuse reports on posts (App Store Guideline 1.2). One report per
// (post, reporter); moderators action the open queue.
export const postReports = pgTable(
  "post_reports",
  {
    id: uuid().defaultRandom().primaryKey().notNull(),
    postId: uuid("post_id").notNull(),
    reporterId: text("reporter_id").notNull(),
    reason: text().notNull(),
    details: text(),
    status: text().default("open").notNull(),
    createdAt: timestamp("created_at", { withTimezone: true, mode: "string" })
      .defaultNow()
      .notNull(),
  },
  (table) => [
    uniqueIndex("post_reports_dedupe_idx").using(
      "btree",
      table.postId.asc().nullsLast(),
      table.reporterId.asc().nullsLast(),
    ),
    index("idx_post_reports_status").using(
      "btree",
      table.status.asc().nullsLast(),
      table.createdAt.desc().nullsFirst(),
    ),
    foreignKey({
      columns: [table.postId],
      foreignColumns: [posts.postId],
      name: "post_reports_post_id_fkey",
    }).onDelete("cascade"),
    foreignKey({
      columns: [table.reporterId],
      foreignColumns: [users.userId],
      name: "post_reports_reporter_id_fkey",
    }).onDelete("cascade"),
    check(
      "post_reports_reason_check",
      sql`reason = ANY (ARRAY['spam'::text, 'nudity'::text, 'harassment'::text, 'violence'::text, 'other'::text])`,
    ),
  ],
);

// Instagram-style comments on feed posts. One level of nesting: a reply's
// parent_comment_id always points at a TOP-LEVEL comment (replies to replies
// are re-rooted at write time). Soft-deleted like posts; deleting a top-level
// comment also soft-deletes its replies.
export const postComments = pgTable(
  "post_comments",
  {
    commentId: uuid("comment_id").defaultRandom().primaryKey().notNull(),
    postId: uuid("post_id").notNull(),
    userId: text("user_id").notNull(),
    parentCommentId: uuid("parent_comment_id"),
    content: text().notNull(),
    createdAt: timestamp("created_at", { withTimezone: true, mode: "string" })
      .defaultNow()
      .notNull(),
    deletedAt: timestamp("deleted_at", { withTimezone: true, mode: "string" }),
  },
  (table) => [
    index("idx_post_comments_post")
      .using(
        "btree",
        table.postId.asc().nullsLast(),
        table.createdAt.asc().nullsLast(),
      )
      .where(sql`(deleted_at IS NULL)`),
    foreignKey({
      columns: [table.postId],
      foreignColumns: [posts.postId],
      name: "post_comments_post_id_fkey",
    }).onDelete("cascade"),
    foreignKey({
      columns: [table.userId],
      foreignColumns: [users.userId],
      name: "post_comments_user_id_fkey",
    }).onDelete("cascade"),
    foreignKey({
      columns: [table.parentCommentId],
      foreignColumns: [table.commentId],
      name: "post_comments_parent_fkey",
    }).onDelete("cascade"),
    check(
      "post_comments_content_check",
      sql`char_length(content) >= 1 AND char_length(content) <= 1000`,
    ),
  ],
);

// Abuse reports on comments (App Store Guideline 1.2) — mirrors post_reports.
// One report per (comment, reporter); moderators action the open queue.
export const commentReports = pgTable(
  "comment_reports",
  {
    id: uuid().defaultRandom().primaryKey().notNull(),
    commentId: uuid("comment_id").notNull(),
    reporterId: text("reporter_id").notNull(),
    reason: text().notNull(),
    details: text(),
    status: text().default("open").notNull(),
    createdAt: timestamp("created_at", { withTimezone: true, mode: "string" })
      .defaultNow()
      .notNull(),
  },
  (table) => [
    uniqueIndex("comment_reports_dedupe_idx").using(
      "btree",
      table.commentId.asc().nullsLast(),
      table.reporterId.asc().nullsLast(),
    ),
    index("idx_comment_reports_status").using(
      "btree",
      table.status.asc().nullsLast(),
      table.createdAt.desc().nullsFirst(),
    ),
    foreignKey({
      columns: [table.commentId],
      foreignColumns: [postComments.commentId],
      name: "comment_reports_comment_id_fkey",
    }).onDelete("cascade"),
    foreignKey({
      columns: [table.reporterId],
      foreignColumns: [users.userId],
      name: "comment_reports_reporter_id_fkey",
    }).onDelete("cascade"),
    check(
      "comment_reports_reason_check",
      sql`reason = ANY (ARRAY['spam'::text, 'nudity'::text, 'harassment'::text, 'violence'::text, 'other'::text])`,
    ),
  ],
);

// Directed user blocks. Filtering applies in BOTH directions so neither party
// sees the other's posts/stories once a block exists.
export const userBlocks = pgTable(
  "user_blocks",
  {
    blockerId: text("blocker_id").notNull(),
    blockedId: text("blocked_id").notNull(),
    createdAt: timestamp("created_at", { withTimezone: true, mode: "string" })
      .defaultNow()
      .notNull(),
  },
  (table) => [
    index("idx_user_blocks_blocked").using(
      "btree",
      table.blockedId.asc().nullsLast(),
    ),
    foreignKey({
      columns: [table.blockerId],
      foreignColumns: [users.userId],
      name: "user_blocks_blocker_id_fkey",
    }).onDelete("cascade"),
    foreignKey({
      columns: [table.blockedId],
      foreignColumns: [users.userId],
      name: "user_blocks_blocked_id_fkey",
    }).onDelete("cascade"),
    primaryKey({
      columns: [table.blockerId, table.blockedId],
      name: "user_blocks_pkey",
    }),
  ],
);

// Operational error log for the admin dashboard. Written fire-and-forget by
// logError() at failure sites (push/APNs sends, auth, cron). No FK on user_id:
// a logging insert must never fail because a referenced row is gone.
export const errorLog = pgTable(
  "error_log",
  {
    id: uuid().defaultRandom().primaryKey().notNull(),
    category: text().notNull(),
    userId: text("user_id"),
    message: text().notNull(),
    context: jsonb(),
    createdAt: timestamp("created_at", {
      withTimezone: true,
      mode: "string",
    }).defaultNow(),
  },
  (table) => [
    index("idx_error_log_created_at").using(
      "btree",
      table.createdAt.desc().nullsFirst(),
    ),
    index("idx_error_log_category").using(
      "btree",
      table.category.asc().nullsLast(),
      table.createdAt.desc().nullsFirst(),
    ),
  ],
);

export const androidWaitlist = pgTable(
  "android_waitlist",
  {
    id: uuid().defaultRandom().primaryKey().notNull(),
    // Stored normalized (trimmed + lowercased by waitlistService); the UNIQUE
    // constraint makes signups idempotent so the endpoint can't be used to
    // probe whether an address is already on the list.
    email: text().notNull(),
    source: text().default("website").notNull(),
    createdAt: timestamp("created_at", {
      withTimezone: true,
      mode: "string",
    }).defaultNow(),
  },
  (table) => [unique("android_waitlist_email_unique").on(table.email)],
);
