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

// One row per friend_request push actually SENT. Deliberately not derived from
// `friendships`: decline and cancel DELETE the row, so counting friendships
// would let a send/cancel/send loop re-trigger pushes for free and would
// under-count a mass-add sweep. Mirrors friend_nudge_log.
export const friendRequestLog = pgTable(
  "friend_request_log",
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
    index("idx_friend_request_log_lookup").using(
      "btree",
      table.senderId.asc().nullsLast(),
      table.targetId.asc().nullsLast(),
      table.createdAt.desc().nullsFirst(),
    ),
  ],
);

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
    // All-time longest streak. RATCHETED: only ever raised, via
    // GREATEST(longest_streak, …) at the current_streak write sites
    // (refreshCurrentStreak) and the streak-eras read path. Historical values
    // are filled by db/backfillLongestStreaks.ts after boot; until it lands a
    // row reads 0 and API responses degrade to max(0, current streak).
    longestStreak: integer("longest_streak").default(0).notNull(),
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
    // The grandfather line for cross-app duplicate exclusion: a workout is only
    // ever auto-excluded as a duplicate when its `created_at >= dedupe_since`.
    //
    // DEFAULT now() IS DELIBERATE HERE, and it is the one case where the
    // "ADD COLUMN ts DEFAULT now() stamps every existing row with one DDL-time
    // value" gotcha is the FEATURE, not the bug: that single deploy-instant
    // value is exactly the grandfather line we want. Every workout a user had
    // already uploaded pre-dates it, so nobody's mile totals or streaks move
    // when dedup turns on — only newly-synced workouts are deduped. New users
    // get their real insert time, which is also correct (they have no history).
    // Costs no table rewrite. Do NOT "fix" this to a backfill.
    //
    // Moved backwards (to the user's earliest workout) only by an explicit
    // opt-in through POST /workouts/:userId/duplicates/resolve.
    dedupeSince: timestamp("dedupe_since", {
      withTimezone: true,
      mode: "string",
    }).defaultNow(),
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
    // Buddy-sessions enrollment stamp. Only the app build that ships the Buddy
    // Walks UI calls POST /buddy/enroll, so null = legacy build → this user is
    // never offered as an invite candidate and never receives a buddy push.
    // Without this gate you can invite someone whose installed app has no buddy
    // UI at all: the server deploys weeks ahead of the App Store release.
    // Mirrors streak_features_at / terms_accepted_at.
    buddyEnrolledAt: timestamp("buddy_enrolled_at", {
      withTimezone: true,
      mode: "string",
    }),
  },
  (table) => [
    index("idx_users_current_streak_desc").using(
      "btree",
      table.currentStreak.desc().nullsFirst(),
    ),
    // Built CONCURRENTLY by backfillLongestStreaks as its completion marker —
    // stripped from the generated migration (0035), 0029 precedent.
    index("idx_users_longest_streak_desc").using(
      "btree",
      table.longestStreak.desc().nullsFirst(),
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
    // Seconds the tracker saw actual movement (in-app workouts only; null for
    // Watch/third-party syncs). DISPLAY pace divides by this so stop-heavy
    // walks don't read 82:47/mi — while total_duration stays the elapsed
    // truth for PRs, races, and recaps (a race clock doesn't pause).
    movingSeconds: doublePrecision("moving_seconds"),
    // Ghost race, written ONLY when the ghost was beaten (in-app tracker
    // stamps it as HKWorkout metadata at finish, the sync carries it here).
    // Presence therefore means "won" — which is exactly what the ghost medal
    // family counts. Null on every other workout, including raced-and-lost.
    ghostMarginSeconds: doublePrecision("ghost_margin_seconds"),
    ghostTargetSeconds: doublePrecision("ghost_target_seconds"),
    // Whose ghost it was, when the target was a FRIEND's mile rather than the
    // user's own best/PR/typed time. Null for a solo ghost — the margin and
    // target columns above stay set either way, so this only ever answers
    // "is there someone to tell about this?".
    ghostFriendUserId: varchar("ghost_friend_user_id", { length: 255 }),
    // Claim stamp for the "your ghost was beaten" push. Nullable with NO
    // default on purpose: `ADD COLUMN ts timestamptz DEFAULT now()` stores one
    // DDL-time missing-value for every pre-existing row, so a cron gating on
    // it fires on the whole backlog at once. Claim-then-send (h2h_matchups
    // pattern) is what stops the constant re-uploads of a workout — fullSync,
    // recalibrate — from re-pushing.
    ghostNotifiedAt: timestamp("ghost_notified_at", {
      withTimezone: true,
      mode: "string",
    }),
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
    // How this workout shows up in the FEED — never whether it counts. A tiny
    // accidental walk still adds to today's miles and can still complete a
    // streak day (that's what `exclusion_reason` is for, and why this is a
    // separate column); it just doesn't get to spam a card.
    //   'hidden'     — under the feed floor, or its day never reached the mile
    //   'rolled_up'  — a pre-mile segment, folded into the anchor's card
    //   'daily_mile' — the workout that crossed the mile; the ANCHOR whose card
    //                  represents the whole day's rollup
    //   'extra'      — logged after the mile was done; gets its own card
    // Recomputed for the whole (user, local_date) on every workout mutation by
    // recomputeFeedRolesForDay (workoutService). Defaults to 'extra' so an
    // unclassified row stays VISIBLE — failing open beats silently swallowing
    // someone's run.
    feedRole: text("feed_role").default("extra").notNull(),
    // Bundle id of the app that WROTE this workout into HealthKit
    // (com.strava.stravaride, com.garmin.connect.mobile, …). Distinct from
    // `source`, which is varchar(20) and answers healthkit/manual/edited — a
    // bundle id doesn't fit there and means something different. Null on every
    // pre-existing row and on any client too old to send it; the dedup pass
    // treats null as "unknown app", never as a match.
    sourceBundleId: varchar("source_bundle_id", { length: 255 }),
    // The workout this one duplicates — set when two apps (say Garmin Connect
    // and Strava) both wrote the same real-world run, which HealthKit hands us
    // as two different UUIDs. ALWAYS populated by detection, independent of
    // whether the row is actually excluded: the exclusion is gated separately
    // on the user's `dedupe_since` grandfather line, so this column stays a
    // pure observation that the review endpoints can report on.
    duplicateOf: varchar("duplicate_of", { length: 255 }),
    /// The USER's explicit answer to "is this a duplicate?", which outranks
    /// detection.
    ///
    /// 'count'   — count it, whatever detection thinks.
    /// 'exclude' — don't count it, whatever detection thinks.
    /// NULL      — no opinion; detection decides.
    ///
    /// This exists because the exclusion pass re-runs on EVERY sync of the day.
    /// Without somewhere durable to record intent, a user who said "no, that
    /// really was a second walk" would have their choice silently reversed by
    /// the next heartbeat, which is exactly the surprise the feature is meant
    /// to prevent.
    duplicateDecision: text("duplicate_decision"),
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
    // The unified feed's workout candidates, in the order it reads them. The
    // predicate mirrors that query's WHERE exactly so the planner can prove the
    // partial index applies; keep the two in sync if either changes.
    index("idx_workouts_feed_candidates")
      .on(
        table.userId.asc().nullsLast(),
        table.deviceEndDate.desc().nullsFirst(),
      )
      .where(
        sql`(deleted_at IS NULL AND exclusion_reason IS NULL AND feed_role IN ('daily_mile', 'extra'))`,
      ),
    unique("workouts_user_workout_unique").on(table.workoutId, table.userId),
    // A typo in any writer would silently hide someone's whole feed, and the
    // column is only ever written by one function — cheap insurance.
    check(
      "workouts_feed_role_check",
      sql`${table.feedRole} IN ('hidden', 'rolled_up', 'daily_mile', 'extra')`,
    ),
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
    // Live presence: friends may see "out on a walk right now" while this
    // user tracks in-app (never location — just the fact). Gates being SEEN,
    // not seeing others. Default true; the app asks explicitly on the first
    // tracked workout of the supporting build.
    shareLivePresence: boolean("share_live_presence").default(true),
    // weekly_recap_enabled: Sunday-evening "Your week" recap push + story card.
    weeklyRecapEnabled: boolean("weekly_recap_enabled").default(true),
    // weekly_challenge_enabled: the Monday "new challenge" push, the mid-week
    // nudge, and the completion celebration. Its OWN category rather than
    // folded into competition_updates — otherwise muting competitions mutes
    // this too, which isn't a real toggle (Guideline 4.5.4).
    weeklyChallengeEnabled: boolean("weekly_challenge_enabled").default(true),
    // workout_visibility: who may see my workout CONTENT — routes and photos.
    // 'friends' (the default, and what every user effectively has today) =
    // accepted friends only, the same circle the feed uses. 'public' = any
    // signed-in user. 'private' = nobody but me.
    //
    // This is a coarser, content-level gate that sits ABOVE share_route_maps:
    // visibility decides WHO, share_route_maps decides WHETHER routes are part
    // of what they get. Both must pass.
    workoutVisibility: text("workout_visibility").default("friends").notNull(),
    // friend_request_reminder_enabled: the once-per-week "N people are waiting
    // to be your friend" nudge for requests left unanswered >24h. Separate from
    // the friend_request push itself so muting the reminder never mutes the
    // original request.
    friendRequestReminderEnabled: boolean(
      "friend_request_reminder_enabled",
    ).default(true),
    // buddy_invites_enabled: the "X invited you to a Buddy Walk" push.
    // buddy_invite is in HIGH_PRIORITY_TYPES (it is time-sensitive — the walk is
    // starting now), which bypasses quiet hours and the daily cap, so this
    // toggle is the ONLY thing standing between a user and an unmutable push.
    // Guideline 4.5.4 requires it, and it must ship WITH the feature, not after.
    buddyInvitesEnabled: boolean("buddy_invites_enabled").default(true),
    // tagged_posts_on_profile: do collabs I'm tagged in land on my profile's
    // Posts grid? Off = they live in the Tagged tab only (Instagram's model).
    // The default stays ON so nothing moves for existing users. Read through
    // posts.coauthor_on_profile, which overrides it per post.
    taggedPostsOnProfile: boolean("tagged_posts_on_profile").default(true),
    // auto_post_without_photo: when I skip the post-run photo prompt, still put
    // the rendered route/stats card on the feed. Off = a walk only reaches the
    // feed if I actually attached a photo to it.
    //
    // Enforced CLIENT-side (RunPostService.autoPostMile is what builds that
    // card), so this column is storage and cross-device carry, not a gate — the
    // server must keep accepting `is_auto` posts from builds that don't read it.
    // Default TRUE: every installed build posts the card today, and a preference
    // that changed shipped behaviour on deploy would look like a bug.
    autoPostWithoutPhoto: boolean("auto_post_without_photo").default(true),
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
    // Optional team play: { member_pick: boolean, teams: [{ id, name }] }.
    // Deliberately NOT inside options — clients PATCH options wholesale and
    // would silently erase teams. NULL = no teams for this competition.
    teams: jsonb(),
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
    // What the app build behind this token can handle, self-declared at
    // registration (see clientFeatures.ts). Empty for every client that
    // predates the field, which is the whole point: a server deploy lands
    // weeks before an App Store release, so "is this feature safe to send
    // to this device" is a per-device question, not an env var.
    clientFeatures: text("client_features")
      .array()
      .notNull()
      .default(sql`'{}'::text[]`),
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

/**
 * Which daily challenge a user was actually SERVED on a date.
 *
 * Selection is otherwise a pure function of the date and the user's
 * eligibility, re-derived on every read — which means history stops being
 * reproducible the moment the rotation changes (head_to_head moving to twice
 * per cycle already did). Stamped on the user's own first read of a day, so a
 * missed day can name what they saw rather than what the rotation would pick
 * for that date today. Absent for days they never opened the app: they saw no
 * challenge then, so there is nothing to contradict and the reader falls back
 * to re-derivation.
 */
export const userDailyChallenges = pgTable(
  "user_daily_challenges",
  {
    userId: text("user_id").notNull(),
    localDate: date("local_date").notNull(),
    challengeKey: text("challenge_key").notNull(),
    createdAt: timestamp("created_at", {
      withTimezone: true,
      mode: "string",
    })
      .defaultNow()
      .notNull(),
  },
  (table) => [
    foreignKey({
      columns: [table.userId],
      foreignColumns: [users.userId],
      name: "user_daily_challenges_user_id_fkey",
    }).onDelete("cascade"),
    foreignKey({
      columns: [table.challengeKey],
      foreignColumns: [dailyChallenges.challengeKey],
      name: "user_daily_challenges_challenge_key_fkey",
    }),
    primaryKey({
      columns: [table.userId, table.localDate],
      name: "user_daily_challenges_pkey",
    }),
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
    // Live lead-change pushes: the standing THIS ROW'S USER was last told
    // about ('ahead' | 'behind'). The duel is scored end-of-day, so without a
    // record of what was already announced every sync by either side would
    // re-push the same "you're behind". A flip only notifies when the new
    // standing differs from what's stored here.
    leadNotifiedState: text("lead_notified_state"),
    leadNotifiedAt: timestamp("lead_notified_at", {
      withTimezone: true,
      mode: "string",
    }),
  },
  (table) => [
    // Matchup-history reads walk one user's duels newest-first; the PK leads
    // with local_date so it can't serve a user-only filter.
    index("idx_h2h_matchups_user_date").using(
      "btree",
      table.userId.asc().nullsLast(),
      table.localDate.desc().nullsFirst(),
    ),
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
    // Nullable on purpose: ADD COLUMN without NOT NULL stays a metadata-only
    // operation on a live table. Note Postgres evaluates the DEFAULT once at
    // DDL time, so every pre-existing row shares the deploy timestamp — which
    // is why migration 0026 pre-claims legacy rows via reminder_sent_at.
    createdAt: timestamp("created_at", {
      withTimezone: true,
      mode: "string",
    }).defaultNow(),
    // Atomic claim column for the pending-request reminder, mirroring
    // h2h_matchups.notified_at. Claim-then-send keeps the nudge exactly-once.
    reminderSentAt: timestamp("reminder_sent_at", {
      withTimezone: true,
      mode: "string",
    }),
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

/**
 * A pending Streak Assist between two friends. Coverage costs TWO things now:
 * the recipient's own Assist token and one mile the donor ran past their goal
 * that day — so neither side can spend it alone, and both have to say yes.
 *
 * `initiator` says who has to answer: 'donor' means the mile was offered and
 * the recipient responds; 'recipient' means help was requested and the donor
 * responds. `donor_date` is the donor's local day the mile came from, which is
 * also the budget bucket (one donation per mile past goal, per day) — NULL on
 * an unanswered request because the donor hasn't committed a mile to it yet.
 *
 * Nothing expires these rows: an offer is dead the moment its target_date
 * falls out of the recipient's rescue window, which every read re-derives.
 */
export const streakAssistOffers = pgTable(
  "streak_assist_offers",
  {
    id: uuid().defaultRandom().primaryKey().notNull(),
    donorId: text("donor_id").notNull(),
    recipientId: text("recipient_id").notNull(),
    initiator: varchar({ length: 12 }).notNull(),
    donorDate: date("donor_date"),
    targetDate: date("target_date").notNull(),
    status: varchar({ length: 12 }).default("pending").notNull(),
    createdAt: timestamp("created_at", { withTimezone: true, mode: "string" })
      .defaultNow()
      .notNull(),
    resolvedAt: timestamp("resolved_at", {
      withTimezone: true,
      mode: "string",
    }),
  },
  (table) => [
    foreignKey({
      columns: [table.donorId],
      foreignColumns: [users.userId],
      name: "streak_assist_offers_donor_id_fkey",
    }).onDelete("cascade"),
    foreignKey({
      columns: [table.recipientId],
      foreignColumns: [users.userId],
      name: "streak_assist_offers_recipient_id_fkey",
    }).onDelete("cascade"),
    uniqueIndex("streak_assist_offers_pending_key")
      .on(table.donorId, table.recipientId, table.targetDate)
      .where(sql`((status)::text = 'pending'::text)`),
    index("streak_assist_offers_recipient_idx").on(
      table.recipientId,
      table.status,
    ),
    index("streak_assist_offers_donor_idx").on(table.donorId, table.donorDate),
  ],
);

// One row per injury pause. A pause ELIDES local dates from the streak walk
// rather than covering them (see streakFeatureCore.makePausePredicate): the run
// either side joins up, so the streak is frozen at its pre-injury length and
// cannot grow while paused, even on days the user does log a walk.
//
// The interval is HALF-OPEN — paused = [started_on, resumed_on) — so the day a
// user resumes counts for them immediately. An active pause has resumed_on
// NULL and runs to today. `frozen_streak` is the snapshot at started_on - 1,
// kept for display and audit; the walk re-derives the number rather than
// trusting it.
export const streakPauses = pgTable(
  "streak_pauses",
  {
    id: uuid().defaultRandom().primaryKey().notNull(),
    userId: text("user_id").notNull(),
    startedOn: date("started_on").notNull(),
    resumedOn: date("resumed_on"),
    frozenStreak: integer("frozen_streak").default(0).notNull(),
    // Set when the pause ran past the 180-day cap. An expired pause stops
    // bridging, so its days revert to ordinary misses and the streak ends —
    // longest_streak has already ratcheted to the frozen value by then.
    expiredAt: timestamp("expired_at", { withTimezone: true, mode: "string" }),
    createdAt: timestamp("created_at", { withTimezone: true, mode: "string" })
      .defaultNow()
      .notNull(),
  },
  (table) => [
    foreignKey({
      columns: [table.userId],
      foreignColumns: [users.userId],
      name: "streak_pauses_user_id_fkey",
    }).onDelete("cascade"),
    // One active pause per user, enforced by the DB so two racing devices
    // can't open two.
    uniqueIndex("streak_pauses_one_active_key")
      .on(table.userId)
      .where(sql`(resumed_on IS NULL)`),
    index("streak_pauses_user_idx").on(table.userId, table.startedOn),
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
    // Team membership within the competition (id from competitions.teams).
    // NULL = unassigned; cleared when the team is deleted.
    teamId: text("team_id"),
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
    // Does this collab show on the COAUTHOR's own profile grid? Instagram
    // keeps tags off your grid; here they landed on both. Tri-state on
    // purpose: NULL = "follow my `tagged_posts_on_profile` setting", so
    // flipping that switch retroactively covers every tag the user already
    // has, while an explicit true/false is a per-post override that survives
    // later setting changes. Grid ONLY — the Tagged tab, the author's own
    // profile and both circles' feeds are deliberately untouched.
    coauthorOnProfile: boolean("coauthor_on_profile"),
    // Does this collab reach the COAUTHOR's own friend circle?
    //
    // Sibling of coauthor_on_profile and deliberately a SEPARATE switch: being
    // credited on a walk and broadcasting it to your friends are two different
    // consents. "Keep it off my grid" is curation; "keep it out of my friends'
    // feeds" is reach, and a user who wants the second almost never wants to
    // give up the tag itself.
    //
    // Tri-state for the same reason as coauthor_on_profile, except the middle
    // state is a constant rather than a preference: NULL = TRUE, which is what
    // every pre-existing collab already does. Only an explicit FALSE withholds
    // reach, and it withholds NOTHING else — the post stays on the author's
    // feed, the tag stays visible, and the coauthor still sees it themselves.
    coauthorOnFeed: boolean("coauthor_on_feed"),
    // Pinned to the top of the author's own profile grid (Instagram's 3-pin
    // model). Timestamp rather than a boolean so the pins have a stable order
    // of their own — most recently pinned first — independent of post date.
    // The cap (POST_PIN_LIMIT) is enforced in the service, not the schema: it
    // is a product number, and a CHECK constraint over a windowed count is not
    // expressible anyway.
    pinnedAt: timestamp("pinned_at", { withTimezone: true, mode: "string" }),
    // "Posted live": the author shared this inside the 10-minute fresh window
    // after finishing the run. Client-claimed at create time (the client owns
    // the window — it's anchored to when the app SAW the finished workout);
    // legacy builds that don't send it get a server-side derivation in the
    // feed query. Cosmetic only: drives the FRESH chip every viewer sees.
    postedFresh: boolean("posted_fresh").default(false).notNull(),
    // The buddy walk this post stands for, when it came from a recap.
    //
    // Already recorded per participant on post_coauthors, but that row does not
    // exist for the AUTHOR — so a walk whose crew all dropped out had a post
    // nothing could find by session. The recap asks "has this walk been posted
    // yet" on every open, for every participant, and that question is what
    // stops two people opening two posts for one walk.
    buddySessionId: varchar("buddy_session_id", { length: 32 }),
  },
  (table) => [
    // "Has this session been posted?" — asked on every recap open. Partial
    // because buddy posts are a small slice of the table and the lookup always
    // states `IS NOT NULL` (a partial index is only usable when the planner can
    // prove the query implies its predicate).
    index("idx_posts_buddy_session")
      .using(
        "btree",
        table.buddySessionId.asc().nullsLast(),
        table.createdAt.desc().nullsFirst(),
      )
      .where(sql`(buddy_session_id IS NOT NULL AND deleted_at IS NULL)`),
    index("idx_posts_user_created").using(
      "btree",
      table.userId.asc().nullsLast(),
      table.createdAt.desc().nullsFirst(),
    ),
    // The grid asks for "this author's pins" as its own small query before the
    // paged body. Partial because pinned posts are a handful of rows across the
    // whole table and the query always states `pinned_at IS NOT NULL`.
    index("idx_posts_user_pinned")
      .using(
        "btree",
        table.userId.asc().nullsLast(),
        table.pinnedAt.desc().nullsFirst(),
      )
      .where(sql`(pinned_at IS NOT NULL AND deleted_at IS NULL)`),
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
    // Collab lookups: the unified feed's "does a collab post stand in for this
    // workout" NOT EXISTS probes coauthor_workout_id per candidate row, and the
    // profile grid / Tagged tab filter on coauthor_user_id — both were
    // unindexed (sequential scans that grow with the posts table). Partial:
    // the overwhelming majority of posts carry no coauthor.
    index("idx_posts_coauthor_workout")
      .using("btree", table.coauthorWorkoutId.asc().nullsLast())
      .where(sql`(coauthor_workout_id IS NOT NULL)`),
    index("idx_posts_coauthor_user")
      .using("btree", table.coauthorUserId.asc().nullsLast())
      .where(sql`(coauthor_user_id IS NOT NULL)`),
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
    postId: uuid("post_id"),
    workoutId: varchar("workout_id", { length: 255 }),
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
      .where(sql`(deleted_at IS NULL AND post_id IS NOT NULL)`),
    index("idx_post_comments_workout")
      .using(
        "btree",
        table.workoutId.asc().nullsLast(),
        table.createdAt.asc().nullsLast(),
      )
      .where(sql`(deleted_at IS NULL AND workout_id IS NOT NULL)`),
    foreignKey({
      columns: [table.postId],
      foreignColumns: [posts.postId],
      name: "post_comments_post_id_fkey",
    }).onDelete("cascade"),
    foreignKey({
      columns: [table.workoutId],
      foreignColumns: [workouts.workoutId],
      name: "post_comments_workout_id_fkey",
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
    check(
      "post_comments_one_target_check",
      sql`((post_id IS NOT NULL)::int + (workout_id IS NOT NULL)::int) = 1`,
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

// Live tracking presence: one row per user (PK), replaced by upsert on every
// session start — the table is bounded by user count, so there is no growth
// and no sweep. "Currently out" is a query-time predicate: ended_at IS NULL
// AND last_seen_at within LIVE_PRESENCE_WINDOW_SECONDS (liveTrackingService).
// session_id rotates per start so a zombie second device's heartbeats are
// rejectable instead of resurrecting an ended session.
export const liveTrackingSessions = pgTable(
  "live_tracking_sessions",
  {
    userId: text("user_id").primaryKey().notNull(),
    sessionId: uuid("session_id").defaultRandom().notNull(),
    workoutType: varchar("workout_type", { length: 50 }).notNull(),
    startedAt: timestamp("started_at", { withTimezone: true, mode: "string" })
      .defaultNow()
      .notNull(),
    /// Live distance, in miles, as of the last heartbeat.
    ///
    /// Presence answered "they are out" and nothing else, so a friend's card
    /// could say someone was walking but never how it was going — which is the
    /// part anyone watching actually wants. Clamped MONOTONIC on write: a
    /// heartbeat that arrives out of order, or from a device whose GPS burped,
    /// must never make a friend's number go backwards in front of an audience.
    distanceMiles: doublePrecision("distance_miles").default(0).notNull(),
    lastSeenAt: timestamp("last_seen_at", {
      withTimezone: true,
      mode: "string",
    })
      .defaultNow()
      .notNull(),
    endedAt: timestamp("ended_at", { withTimezone: true, mode: "string" }),
  },
  (table) => [
    foreignKey({
      columns: [table.userId],
      foreignColumns: [users.userId],
      name: "live_tracking_sessions_user_id_fkey",
    }).onDelete("cascade"),
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

// ---------------------------------------------------------------------------
// Buddy Walks & Runs
//
// A live shared walk/run: several friends move at the same time and see each
// other's progress. The session is SERVER-AUTHORITATIVE — every participant
// reports to the backend and reads everyone else back from it. There is no
// peer-to-peer link, which is what makes a remote session work at all and what
// keeps the session alive when two people on the same walk drift apart.
//
// A session DECORATES a normal workout; it never replaces one. Each participant
// is running the ordinary WorkoutTrackingView / HealthKit / upload path, so
// streaks, daily-mile, competitions and badges are untouched by this feature.
// The live numbers below are for DISPLAY; the authoritative result is stamped
// later by reconcileBuddySessions() from the real synced HKWorkout.
// ---------------------------------------------------------------------------
export const buddySessions = pgTable(
  "buddy_sessions",
  {
    id: varchar({ length: 32 })
      .default(sql`replace((gen_random_uuid())::text, '-'::text, ''::text)`)
      .primaryKey()
      .notNull(),
    // Short human-shareable code. Unique only among sessions that are still
    // open (partial index below) so codes recycle instead of exhausting.
    joinCode: varchar("join_code", { length: 8 }).notNull(),
    hostUserId: text("host_user_id"),
    mode: text().notNull(),
    // Miles for coop_goal/race_goal, minutes for race_time, NULL for 'together'.
    goalValue: doublePrecision("goal_value"),
    activityType: varchar("activity_type", { length: 50 }).notNull(),
    status: text().notNull(),
    // Which door people actually came through. Worth measuring before investing
    // in the proximity handshake.
    origin: text().notNull(),
    // Phase 4 (scheduled long-distance sessions). NULL for everything today.
    scheduledStartAt: timestamp("scheduled_start_at", {
      withTimezone: true,
      mode: "string",
    }),
    // Claim column for the "starts in 15 minutes" push — claimed BEFORE the
    // send so overlapping containers on a deploy can't double-notify. Nullable
    // with NO default on purpose: a default of now() would be stored as a
    // missing-value and make every pre-existing row read as already-reminded
    // (PG 11+ ADD COLUMN behaviour), which here would be harmless but is the
    // trap documented in the backend rules and not worth rehearsing.
    scheduledReminderSentAt: timestamp("scheduled_reminder_sent_at", {
      withTimezone: true,
      mode: "string",
    }),
    // Set a few seconds in the FUTURE at start, so every client counts down to
    // the same wall-clock instant instead of each starting when its own request
    // happens to return.
    startedAt: timestamp("started_at", { withTimezone: true, mode: "string" }),
    // Only meaningful for race_time — computed from goal_value at start.
    endsAt: timestamp("ends_at", { withTimezone: true, mode: "string" }),
    endedAt: timestamp("ended_at", { withTimezone: true, mode: "string" }),
    winnerUserId: text("winner_user_id"),
    // Bumped on EVERY mutation. This is the polling cursor: clients send
    // ?since=<version> and get a 304 when nothing has changed.
    stateVersion: integer("state_version").default(1).notNull(),
    localDate: date("local_date").notNull(),
    createdAt: timestamp("created_at", { withTimezone: true, mode: "string" })
      .defaultNow()
      .notNull(),
  },
  (table) => [
    uniqueIndex("uq_buddy_sessions_join_code_open")
      .using("btree", table.joinCode.asc().nullsLast())
      .where(sql`(status = ANY (ARRAY['lobby'::text, 'active'::text]))`),
    index("idx_buddy_sessions_status_created").using(
      "btree",
      table.status.asc().nullsLast(),
      table.createdAt.desc().nullsLast(),
    ),
    foreignKey({
      columns: [table.hostUserId],
      foreignColumns: [users.userId],
      name: "buddy_sessions_host_user_id_fkey",
    }).onDelete("set null"),
    foreignKey({
      columns: [table.winnerUserId],
      foreignColumns: [users.userId],
      name: "buddy_sessions_winner_user_id_fkey",
    }).onDelete("set null"),
    check(
      "buddy_sessions_mode_check",
      sql`mode = ANY (ARRAY['together'::text, 'coop_goal'::text, 'race_goal'::text, 'race_time'::text])`,
    ),
    check(
      "buddy_sessions_status_check",
      sql`status = ANY (ARRAY['lobby'::text, 'active'::text, 'completed'::text, 'cancelled'::text])`,
    ),
    check(
      "buddy_sessions_origin_check",
      sql`origin = ANY (ARRAY['invite'::text, 'code'::text, 'join_active'::text, 'nearby'::text])`,
    ),
  ],
);

export const buddySessionParticipants = pgTable(
  "buddy_session_participants",
  {
    sessionId: varchar("session_id", { length: 32 }).notNull(),
    userId: text("user_id").notNull(),
    status: text().notNull(),
    invitedBy: text("invited_by"),
    joinedAt: timestamp("joined_at", { withTimezone: true, mode: "string" }),
    readyAt: timestamp("ready_at", { withTimezone: true, mode: "string" }),
    finishedAt: timestamp("finished_at", {
      withTimezone: true,
      mode: "string",
    }),
    // Live, MONOTONIC. Progress is clamped up (never rejected, never lowered):
    // a rejected report freezes a participant whose GPS burped, which reads as a
    // bug to everyone else watching the roster.
    distanceMiles: doublePrecision("distance_miles").default(0).notNull(),
    durationSeconds: integer("duration_seconds").default(0).notNull(),
    // Staleness is derived from this at READ time (>90s → "out of range" in the
    // UI). No cron is involved in the live display.
    lastProgressAt: timestamp("last_progress_at", {
      withTimezone: true,
      mode: "string",
    }),
    // Stamped by reconcileBuddySessions() once the real workout syncs.
    workoutId: varchar("workout_id", { length: 255 }),
    finalDistanceMiles: doublePrecision("final_distance_miles"),
    place: integer(),
    // Indoor vs outdoor is PER PARTICIPANT, not per session: two people can
    // walk "together" with one on a treadmill and one on a street, and the
    // choice decides which instrument that phone measures with (GPS vs
    // pedometer). NULL = never chosen, which the client reads as outdoor.
    locationType: text("location_type"),
    // Per-VIEWER removal of a finished walk from the history screen. Only ever
    // hides this participant's own row from their own archive — the walk
    // happened, and the other people on it keep it. Nothing is deleted, so an
    // accidental hide costs nothing and a shared total can't silently drift.
    hiddenAt: timestamp("hidden_at", { withTimezone: true, mode: "string" }),
  },
  (table) => [
    index("idx_buddy_participants_user_status").using(
      "btree",
      table.userId.asc().nullsLast(),
      table.status.asc().nullsLast(),
    ),
    foreignKey({
      columns: [table.sessionId],
      foreignColumns: [buddySessions.id],
      name: "buddy_session_participants_session_id_fkey",
    }).onDelete("cascade"),
    foreignKey({
      columns: [table.userId],
      foreignColumns: [users.userId],
      name: "buddy_session_participants_user_id_fkey",
    }).onDelete("cascade"),
    foreignKey({
      columns: [table.workoutId],
      foreignColumns: [workouts.workoutId],
      name: "buddy_session_participants_workout_id_fkey",
    }).onDelete("set null"),
    primaryKey({
      columns: [table.sessionId, table.userId],
      name: "buddy_session_participants_pkey",
    }),
    check(
      "buddy_session_participants_status_check",
      sql`status = ANY (ARRAY['invited'::text, 'joined'::text, 'ready'::text, 'active'::text, 'finished'::text, 'left'::text, 'declined'::text])`,
    ),
    check(
      "buddy_session_participants_location_type_check",
      sql`location_type IS NULL OR location_type = ANY (ARRAY['outdoor'::text, 'indoor'::text])`,
    ),
  ],
);

// Append-only timeline. Drives the recap screen and the auto-generated caption
// on the collab post ("Rob hit the goal first at 22:14").
export const buddySessionEvents = pgTable(
  "buddy_session_events",
  {
    id: bigserial({ mode: "bigint" }).primaryKey().notNull(),
    sessionId: varchar("session_id", { length: 32 }).notNull(),
    userId: text("user_id"),
    kind: text().notNull(),
    payload: jsonb(),
    at: timestamp({ withTimezone: true, mode: "string" })
      .defaultNow()
      .notNull(),
  },
  (table) => [
    index("idx_buddy_events_session_at").using(
      "btree",
      table.sessionId.asc().nullsLast(),
      table.at.asc().nullsLast(),
    ),
    foreignKey({
      columns: [table.sessionId],
      foreignColumns: [buddySessions.id],
      name: "buddy_session_events_session_id_fkey",
    }).onDelete("cascade"),
    foreignKey({
      columns: [table.userId],
      foreignColumns: [users.userId],
      name: "buddy_session_events_user_id_fkey",
    }).onDelete("set null"),
  ],
);

// Multi-person collab posts.
//
// The legacy coauthor mechanism is three SCALAR columns on `posts`
// (coauthor_user_id / coauthor_status / coauthor_workout_id) and therefore tops
// out at exactly two people — a 4-person buddy walk does not fit.
//
// This table COEXISTS with those columns rather than replacing them. A buddy
// post writes BOTH: a row here for every participant, and the legacy scalars
// populated with the first coauthor. A shipped client that knows nothing about
// buddy walks then renders a 4-person walk as an ordinary 2-person collab —
// degraded, but coherent — and visiblePostAuthor's existing predicate keeps
// working unchanged for every post that has no rows here.
export const postCoauthors = pgTable(
  "post_coauthors",
  {
    postId: uuid("post_id").notNull(),
    userId: text("user_id").notNull(),
    status: text().default("pending").notNull(),
    workoutId: varchar("workout_id", { length: 255 }),
    buddySessionId: varchar("buddy_session_id", { length: 32 }),
    // THIS participant's own photo on the shared post.
    //
    // A buddy walk is one walk, so it gets one post — but everyone on it was
    // there, and everyone took a picture. Rather than have the second person
    // open a second post for the same walk (which is what they did, because
    // "already posted" was answered from a device-local registry that cannot
    // see a friend's phone), they add their photo here and it becomes another
    // slide on the card that already exists.
    //
    // Null on every pre-existing row and on every participant who hasn't added
    // one, which are the same thing as far as any reader is concerned.
    mediaUrl: text("media_url"),
    photoAddedAt: timestamp("photo_added_at", {
      withTimezone: true,
      mode: "string",
    }),
    // THIS participant's reach consent, the multi-person mirror of
    // posts.coauthor_on_feed. NULL = TRUE (every pre-existing row), so the
    // column can only ever withhold reach that was previously granted, never
    // grant new reach.
    onFeed: boolean("on_feed"),
    // THIS participant's per-post route consent, overriding their global
    // `share_route_maps` for this one card. Tri-state on purpose and in this
    // order: NULL = "follow my setting", which is what every existing crew
    // photo does — so the global switch keeps covering posts made before the
    // override existed. An explicit value pins one walk either way, which is
    // the actual ask ("share the park loop, never the one that starts at my
    // front door"). Read through crewRouteConsentSql; the poster's own
    // include_route still covers the whole card above it.
    includeRoute: boolean("include_route"),
    createdAt: timestamp("created_at", { withTimezone: true, mode: "string" })
      .defaultNow()
      .notNull(),
    respondedAt: timestamp("responded_at", {
      withTimezone: true,
      mode: "string",
    }),
    // Claim stamp for the hour-later "put your photo on it too" nudge, so the
    // cron sends it at most once per participant per post.
    //
    // NOT `DEFAULT now()`: on an existing table that stores the default once as
    // a missing-value, so every pre-existing row would read back the same
    // DDL-time timestamp — and a cron gating on "older than an hour" would then
    // stay silent for an hour and fire on the entire backlog in one tick
    // (backend.md). Nullable with no default: NULL means un-nudged, and the
    // cron's own window (sessions that ended in the last few hours) is what
    // keeps the backlog out.
    photoNudgeSentAt: timestamp("photo_nudge_sent_at", {
      withTimezone: true,
      mode: "string",
    }),
  },
  (table) => [
    index("idx_post_coauthors_user").using(
      "btree",
      table.userId.asc().nullsLast(),
      table.status.asc().nullsLast(),
    ),
    // The buddy history screen looks posts up BY session ("what did we take a
    // picture of on that walk"), which is the one direction this table had no
    // index for — the FK alone doesn't create one. Deliberately NOT partial on
    // `IS NOT NULL`: the lookup's predicate is `= ANY($1)`, and a partial index
    // is only usable when the planner can prove the query implies its
    // predicate, which is not worth betting a seq scan on for the handful of
    // pages this saves.
    index("idx_post_coauthors_buddy_session").using(
      "btree",
      table.buddySessionId.asc().nullsLast(),
    ),
    foreignKey({
      columns: [table.postId],
      foreignColumns: [posts.postId],
      name: "post_coauthors_post_id_fkey",
    }).onDelete("cascade"),
    foreignKey({
      columns: [table.userId],
      foreignColumns: [users.userId],
      name: "post_coauthors_user_id_fkey",
    }).onDelete("cascade"),
    foreignKey({
      columns: [table.workoutId],
      foreignColumns: [workouts.workoutId],
      name: "post_coauthors_workout_id_fkey",
    }).onDelete("set null"),
    foreignKey({
      columns: [table.buddySessionId],
      foreignColumns: [buddySessions.id],
      name: "post_coauthors_buddy_session_id_fkey",
    }).onDelete("set null"),
    primaryKey({
      columns: [table.postId, table.userId],
      name: "post_coauthors_pkey",
    }),
    check(
      "post_coauthors_status_check",
      sql`status = ANY (ARRAY['pending'::text, 'accepted'::text, 'declined'::text])`,
    ),
  ],
);

/**
 * A standing buddy walk — "us, 6pm, weekdays".
 *
 * The point of the feature is a habit, and until now every occurrence meant
 * rebuilding the lobby and re-inviting from scratch. This is the template; the
 * cron spawns a real `buddy_sessions` row from it shortly before each due time
 * and everything downstream (the scheduled-start promotion, the heads-up push,
 * the lobby) is the existing machinery unchanged.
 *
 * Time is stored as LOCAL wall-clock minutes plus an IANA zone, never as a
 * timestamp: "6pm on weekdays" has to survive DST, and a stored instant would
 * drift an hour twice a year. `minutes_of_day` rather than a `time` column
 * because the cron does arithmetic on it.
 */
export const buddyRecurringWalks = pgTable(
  "buddy_recurring_walks",
  {
    id: varchar({ length: 32 })
      .default(sql`replace((gen_random_uuid())::text, '-'::text, ''::text)`)
      .primaryKey()
      .notNull(),
    hostUserId: text("host_user_id").notNull(),
    mode: text().notNull(),
    goalValue: doublePrecision("goal_value"),
    activityType: varchar("activity_type", { length: 50 }).notNull(),
    // Who gets invited to every occurrence. Re-validated at spawn time against
    // friendship/block/enrollment/opt-out — a routine set up months ago must
    // not keep inviting someone who has since unfriended or opted out.
    inviteUserIds: text("invite_user_ids")
      .array()
      .default(sql`'{}'::text[]`)
      .notNull(),
    // 0=Sunday … 6=Saturday, matching Postgres EXTRACT(DOW).
    daysOfWeek: integer("days_of_week").array().notNull(),
    /** Local wall-clock minutes since midnight, 0…1439. */
    minutesOfDay: integer("minutes_of_day").notNull(),
    timezone: text().notNull(),
    isActive: boolean("is_active").default(true).notNull(),
    // The host's LOCAL date we last spawned for. Claimed before the spawn, so
    // overlapping containers on a deploy can't create the walk twice.
    lastSpawnedDate: date("last_spawned_date"),
    createdAt: timestamp("created_at", { withTimezone: true, mode: "string" })
      .defaultNow()
      .notNull(),
    updatedAt: timestamp("updated_at", { withTimezone: true, mode: "string" })
      .defaultNow()
      .notNull(),
  },
  (table) => [
    index("idx_buddy_recurring_active").using(
      "btree",
      table.isActive.asc().nullsLast(),
      table.hostUserId.asc().nullsLast(),
    ),
    foreignKey({
      columns: [table.hostUserId],
      foreignColumns: [users.userId],
      name: "buddy_recurring_walks_host_user_id_fkey",
    }).onDelete("cascade"),
    check(
      "buddy_recurring_walks_mode_check",
      sql`mode = ANY (ARRAY['together'::text, 'coop_goal'::text, 'race_goal'::text, 'race_time'::text])`,
    ),
    check(
      "buddy_recurring_walks_minutes_check",
      sql`minutes_of_day >= 0 AND minutes_of_day <= 1439`,
    ),
  ],
);

/**
 * Catalog of weekly challenges. One THEME is served globally per ISO week
 * (deterministic by week index, so friends share the week's event), but the
 * TARGET is scaled per user from their own trailing four weeks — a flat global
 * number is either trivial for a high-volume runner or impossible for a new
 * one.
 *
 * `icon` must exist in SF Symbols 5: the app's deployment target is iOS 17 and
 * a newer symbol renders as a blank box rather than falling back, which a
 * build against a newer SDK will not catch.
 *
 * Seeded post-boot by `seedWeeklyChallenges()` rather than in a migration, so
 * copy edits and new rows never need one.
 */
export const weeklyChallenges = pgTable(
  "weekly_challenges",
  {
    challengeKey: text("challenge_key").primaryKey().notNull(),
    title: text().notNull(),
    // Supports {target} and {unit} substitution.
    descriptionTemplate: text("description_template").notNull(),
    icon: text().notNull(),
    gradientStart: text("gradient_start").notNull(),
    gradientEnd: text("gradient_end").notNull(),
    metric: text().notNull(),
    unit: text().notNull(),
    // Floor, and the target for anyone without enough history to scale from.
    baseTarget: doublePrecision("base_target").notNull(),
    scaleMultiplier: doublePrecision("scale_multiplier").default(1.1).notNull(),
    // Clamp band, expressed as multiples of base_target, so one freak week
    // can't set an impossible target and a very high-volume user isn't handed
    // something absurd.
    scaleMinMultiplier: doublePrecision("scale_min_multiplier")
      .default(1)
      .notNull(),
    scaleMaxMultiplier: doublePrecision("scale_max_multiplier")
      .default(2.5)
      .notNull(),
    targetCeiling: doublePrecision("target_ceiling").notNull(),
    // Rounding step, so the number stays legible (0.5 mi, 1000 steps, 1 day).
    targetStep: doublePrecision("target_step").default(1).notNull(),
    active: boolean().default(true).notNull(),
    rotationIndex: integer("rotation_index").notNull(),
    createdAt: timestamp("created_at", { withTimezone: true, mode: "string" })
      .defaultNow()
      .notNull(),
  },
  (table) => [
    unique("weekly_challenges_rotation_index_key").on(table.rotationIndex),
  ],
);

/**
 * Which weekly challenge a user was SERVED, and — load-bearing — the target
 * they were set.
 *
 * The target is FROZEN here on first serve (first-write-wins, same reason
 * `user_daily_challenges` stamps the day's pick). Every read afterwards uses
 * this value and never re-derives it. Without the freeze the target chases the
 * runner as their trailing average moves, a change to the scaling formula
 * silently rewrites history, and someone can be told "completed" on Monday and
 * "not completed" on Thursday.
 *
 * Written on the user's own read and by the Monday cron — never from a friend's
 * read, which resolves someone else's week.
 */
export const userWeeklyChallenges = pgTable(
  "user_weekly_challenges",
  {
    userId: text("user_id").notNull(),
    // Monday of the user's local week.
    weekStart: date("week_start", { mode: "string" }).notNull(),
    challengeKey: text("challenge_key").notNull(),
    target: doublePrecision().notNull(),
    // What the target was scaled from, for the "based on your last 4 weeks"
    // explainer. Null when the user had no history and got base_target.
    baseline: doublePrecision(),
    createdAt: timestamp("created_at", { withTimezone: true, mode: "string" })
      .defaultNow()
      .notNull(),
  },
  (table) => [
    foreignKey({
      columns: [table.userId],
      foreignColumns: [users.userId],
      name: "user_weekly_challenges_user_id_fkey",
    }).onDelete("cascade"),
    foreignKey({
      columns: [table.challengeKey],
      foreignColumns: [weeklyChallenges.challengeKey],
      name: "user_weekly_challenges_challenge_key_fkey",
    }),
    primaryKey({
      columns: [table.userId, table.weekStart],
      name: "user_weekly_challenges_pkey",
    }),
  ],
);

/**
 * A completed week. Separate from the daily tables because those hardcode
 * one-per-day in their PK/UNIQUE — a weekly row keyed on a Monday would collide
 * with that Monday's daily row.
 */
export const userWeeklyChallengeCompletions = pgTable(
  "user_weekly_challenge_completions",
  {
    id: bigserial({ mode: "bigint" }).primaryKey().notNull(),
    userId: text("user_id").notNull(),
    weekStart: date("week_start", { mode: "string" }).notNull(),
    challengeKey: text("challenge_key").notNull(),
    // Snapshotted so history reads never depend on the served row surviving.
    target: doublePrecision().notNull(),
    finalValue: doublePrecision("final_value").notNull(),
    completedAt: timestamp("completed_at", {
      withTimezone: true,
      mode: "string",
    })
      .defaultNow()
      .notNull(),
  },
  (table) => [
    index("idx_uwcc_user_week").using(
      "btree",
      table.userId.asc().nullsLast(),
      table.weekStart.desc().nullsFirst(),
    ),
    foreignKey({
      columns: [table.userId],
      foreignColumns: [users.userId],
      name: "user_weekly_challenge_completions_user_id_fkey",
    }).onDelete("cascade"),
    foreignKey({
      columns: [table.challengeKey],
      foreignColumns: [weeklyChallenges.challengeKey],
      name: "user_weekly_challenge_completions_challenge_key_fkey",
    }),
    unique("user_weekly_challenge_completions_user_id_week_start_key").on(
      table.userId,
      table.weekStart,
    ),
  ],
);

/**
 * Claim-then-send log for the weekly pushes, one row per (user, week, kind).
 *
 * A separate table rather than a nullable timestamp column on
 * `user_weekly_challenges` on purpose: `ADD COLUMN ts timestamptz DEFAULT now()`
 * stores one DDL-time missing-value for every pre-existing row, so a cron
 * gating on "not yet sent" would stay silent and then fire on the whole
 * backlog at once.
 */
export const weeklyChallengePushLog = pgTable(
  "weekly_challenge_push_log",
  {
    userId: text("user_id").notNull(),
    weekStart: date("week_start", { mode: "string" }).notNull(),
    // 'new' | 'nudge'
    kind: text().notNull(),
    sentAt: timestamp("sent_at", { withTimezone: true, mode: "string" })
      .defaultNow()
      .notNull(),
  },
  (table) => [
    foreignKey({
      columns: [table.userId],
      foreignColumns: [users.userId],
      name: "weekly_challenge_push_log_user_id_fkey",
    }).onDelete("cascade"),
    primaryKey({
      columns: [table.userId, table.weekStart, table.kind],
      name: "weekly_challenge_push_log_pkey",
    }),
  ],
);

/**
 * A named, permanent collection of the owner's own posts — Instagram's Story
 * Highlights, applied to the thing this app actually accumulates: walks.
 *
 * The point is that a story is the only content here with an expiry, and the
 * expiry is the reason people don't bother making one. `story_expires_at`
 * retires a story from the RAIL; it never deletes the row, and a story-only
 * post already survives on its author's profile in the "not on your feed"
 * strip. A highlight is therefore nothing more than a name and an ordered list
 * of post ids the owner already has — no copies, no second media path, and no
 * new privacy surface: every read re-resolves the member posts through the
 * ordinary post-visibility rules, so a post that later goes private or gets
 * deleted simply leaves the highlight for everyone but its owner.
 *
 * Owner-only content by construction: a highlight can only ever contain posts
 * whose author is the highlight's owner (enforced at write time), so there is
 * no path here for one user to publish another's photo.
 */
export const postHighlights = pgTable(
  "post_highlights",
  {
    highlightId: uuid("highlight_id").defaultRandom().primaryKey().notNull(),
    userId: text("user_id").notNull(),
    title: text().notNull(),
    // Which member post's photo is the circle on the profile rail. Nullable and
    // SET NULL on delete: a cover whose post is gone falls back to the first
    // member at read time rather than leaving a broken tile.
    coverPostId: uuid("cover_post_id"),
    // An uploaded cover image (/uploads/posts/...), chosen from the camera
    // roll instead of from the member posts. Wins over cover_post_id at read
    // time; NULL means "use a member's photo", which is the shipped behaviour
    // and what every highlight created before this column has.
    coverImageUrl: text("cover_image_url"),
    // Owner-chosen order of the rail itself. Ties break on created_at so a
    // batch created with the same index still has a stable order.
    sortIndex: integer("sort_index").default(0).notNull(),
    createdAt: timestamp("created_at", { withTimezone: true, mode: "string" })
      .defaultNow()
      .notNull(),
    updatedAt: timestamp("updated_at", { withTimezone: true, mode: "string" })
      .defaultNow()
      .notNull(),
  },
  (table) => [
    index("idx_post_highlights_user").using(
      "btree",
      table.userId.asc().nullsLast(),
      table.sortIndex.asc().nullsLast(),
      table.createdAt.asc().nullsLast(),
    ),
    foreignKey({
      columns: [table.userId],
      foreignColumns: [users.userId],
      name: "post_highlights_user_id_fkey",
    }).onDelete("cascade"),
    foreignKey({
      columns: [table.coverPostId],
      foreignColumns: [posts.postId],
      name: "post_highlights_cover_post_id_fkey",
    }).onDelete("set null"),
    check("post_highlights_title_check", sql`char_length(title) BETWEEN 1 AND 30`),
  ],
);

/** Ordered membership of a highlight. Cascades from both sides. */
export const postHighlightItems = pgTable(
  "post_highlight_items",
  {
    highlightId: uuid("highlight_id").notNull(),
    postId: uuid("post_id").notNull(),
    sortIndex: integer("sort_index").default(0).notNull(),
    addedAt: timestamp("added_at", { withTimezone: true, mode: "string" })
      .defaultNow()
      .notNull(),
  },
  (table) => [
    index("idx_post_highlight_items_order").using(
      "btree",
      table.highlightId.asc().nullsLast(),
      table.sortIndex.asc().nullsLast(),
      table.addedAt.asc().nullsLast(),
    ),
    // "Which highlights is this post in?" — asked when a post is deleted from
    // the grid and when the composer offers "add to a highlight".
    index("idx_post_highlight_items_post").using(
      "btree",
      table.postId.asc().nullsLast(),
    ),
    foreignKey({
      columns: [table.highlightId],
      foreignColumns: [postHighlights.highlightId],
      name: "post_highlight_items_highlight_id_fkey",
    }).onDelete("cascade"),
    foreignKey({
      columns: [table.postId],
      foreignColumns: [posts.postId],
      name: "post_highlight_items_post_id_fkey",
    }).onDelete("cascade"),
    primaryKey({
      columns: [table.highlightId, table.postId],
      name: "post_highlight_items_pkey",
    }),
  ],
);

/**
 * Manual resolution for a referral that names nobody we can find.
 *
 * Attribution is the free-text name a user types at onboarding, so plenty of
 * it never resolves: a real name instead of a handle, a typo, a nickname. An
 * admin who KNOWS who was meant records it here rather than rewriting what
 * the user typed — `users.referral_detail` stays exactly as entered, which
 * keeps the mapping reversible and the original answer auditable.
 *
 * `alias` is the normalised handle the graph already computes (trimmed,
 * case-folded, leading "@" stripped), so a lookup is a plain equality join.
 */
export const referralAliases = pgTable(
  "referral_aliases",
  {
    alias: text().primaryKey().notNull(),
    userId: text("user_id").notNull(),
    // Who made the call, for when the number is questioned later.
    createdBy: text("created_by"),
    createdAt: timestamp("created_at", { withTimezone: true, mode: "string" })
      .defaultNow()
      .notNull(),
  },
  (table) => [
    foreignKey({
      columns: [table.userId],
      foreignColumns: [users.userId],
      name: "referral_aliases_user_id_fkey",
    }).onDelete("cascade"),
    index("idx_referral_aliases_user").on(table.userId),
  ],
);
