CREATE TABLE "badges" (
	"badge_id" text PRIMARY KEY NOT NULL,
	"category" text NOT NULL,
	"name" text NOT NULL,
	"description" text NOT NULL,
	"icon" text NOT NULL,
	"rarity" text NOT NULL,
	"requirement" numeric,
	"is_hidden" boolean DEFAULT false NOT NULL,
	"sort_order" integer DEFAULT 0 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "badges_rarity_check" CHECK (rarity = ANY (ARRAY['common'::text, 'rare'::text, 'legendary'::text]))
);
--> statement-breakpoint
CREATE TABLE "close_friends" (
	"user_id" text NOT NULL,
	"close_friend_id" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "close_friends_pkey" PRIMARY KEY("user_id","close_friend_id")
);
--> statement-breakpoint
CREATE TABLE "competition_users" (
	"competition_id" text NOT NULL,
	"user_id" text NOT NULL,
	"progress" jsonb,
	"invite_status" varchar(20),
	"placement" integer,
	"last_known_rank" integer,
	"last_known_score" double precision,
	"last_rank_updated_at" timestamp with time zone,
	CONSTRAINT "competition_users_pkey" PRIMARY KEY("competition_id","user_id"),
	CONSTRAINT "competition_users_invite_status_check" CHECK ((invite_status)::text = ANY ((ARRAY['pending'::character varying, 'accepted'::character varying, 'declined'::character varying])::text[]))
);
--> statement-breakpoint
CREATE TABLE "competitions" (
	"id" varchar(32) PRIMARY KEY DEFAULT replace((gen_random_uuid())::text, '-'::text, ''::text) NOT NULL,
	"competition_name" varchar(100),
	"start_date" date,
	"end_date" date,
	"workouts" jsonb NOT NULL,
	"type" varchar(20) NOT NULL,
	"options" jsonb NOT NULL,
	"ended" boolean DEFAULT false,
	"winner" text,
	"owner" text,
	"created_at" timestamp with time zone DEFAULT now(),
	"updated_at" timestamp with time zone DEFAULT now(),
	CONSTRAINT "competitions_type_check" CHECK ((type)::text = ANY ((ARRAY['streaks'::character varying, 'apex'::character varying, 'clash'::character varying, 'targets'::character varying, 'race'::character varying])::text[]))
);
--> statement-breakpoint
CREATE TABLE "daily_challenges" (
	"challenge_key" text PRIMARY KEY NOT NULL,
	"title" text NOT NULL,
	"description_template" text NOT NULL,
	"icon" text NOT NULL,
	"gradient_start" text NOT NULL,
	"gradient_end" text NOT NULL,
	"type" text NOT NULL,
	"active" boolean DEFAULT true NOT NULL,
	"rotation_index" integer NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "daily_challenges_rotation_index_key" UNIQUE("rotation_index"),
	CONSTRAINT "daily_challenges_type_check" CHECK (type = ANY (ARRAY['pace'::text, 'distance'::text, 'time'::text, 'activity'::text, 'steps'::text]))
);
--> statement-breakpoint
CREATE TABLE "daily_steps" (
	"user_id" text NOT NULL,
	"local_date" date NOT NULL,
	"steps" integer NOT NULL,
	"timezone_offset" integer NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "daily_steps_pkey" PRIMARY KEY("user_id","local_date"),
	CONSTRAINT "daily_steps_steps_check" CHECK (steps >= 0)
);
--> statement-breakpoint
CREATE TABLE "device_tokens" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" text NOT NULL,
	"device_token" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now(),
	"updated_at" timestamp with time zone DEFAULT now(),
	CONSTRAINT "device_tokens_user_id_device_token_key" UNIQUE("user_id","device_token")
);
--> statement-breakpoint
CREATE TABLE "flex_log" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"sender_id" text NOT NULL,
	"target_id" text NOT NULL,
	"competition_id" text NOT NULL,
	"message" text,
	"created_at" timestamp with time zone DEFAULT now()
);
--> statement-breakpoint
CREATE TABLE "friend_notification_settings" (
	"user_id" text NOT NULL,
	"friend_id" text NOT NULL,
	"muted" boolean DEFAULT false NOT NULL,
	"nudges_muted" boolean DEFAULT false NOT NULL,
	"activity_muted" boolean DEFAULT false NOT NULL,
	"created_at" timestamp with time zone DEFAULT now(),
	"updated_at" timestamp with time zone DEFAULT now(),
	CONSTRAINT "friend_notification_settings_pkey" PRIMARY KEY("user_id","friend_id")
);
--> statement-breakpoint
CREATE TABLE "friend_nudge_log" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"sender_id" text NOT NULL,
	"target_id" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now()
);
--> statement-breakpoint
CREATE TABLE "friendships" (
	"user_id" text NOT NULL,
	"friend_id" text NOT NULL,
	"status" text DEFAULT 'pending' NOT NULL,
	CONSTRAINT "friendships_pkey" PRIMARY KEY("user_id","friend_id"),
	CONSTRAINT "unique_friendship_pair" UNIQUE("user_id","friend_id")
);
--> statement-breakpoint
CREATE TABLE "hype_log" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"sender_id" text NOT NULL,
	"target_id" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now(),
	"context_type" text,
	"context_id" text,
	"context_label" text
);
--> statement-breakpoint
CREATE TABLE "in_app_notifications" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" text NOT NULL,
	"title" text NOT NULL,
	"body" text NOT NULL,
	"type" text NOT NULL,
	"data" jsonb DEFAULT '{}'::jsonb,
	"is_read" boolean DEFAULT false,
	"created_at" timestamp with time zone DEFAULT now()
);
--> statement-breakpoint
CREATE TABLE "milestone_notifications" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"milestone_key" text NOT NULL,
	"competition_id" text,
	"user_id" text,
	"created_at" timestamp with time zone DEFAULT now(),
	CONSTRAINT "milestone_notifications_milestone_key_key" UNIQUE("milestone_key")
);
--> statement-breakpoint
CREATE TABLE "notification_audience_settings" (
	"user_id" text NOT NULL,
	"direction" text NOT NULL,
	"event_type" text NOT NULL,
	"activity_type" text DEFAULT '' NOT NULL,
	"audience" text NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "notification_audience_settings_pkey" PRIMARY KEY("user_id","direction","event_type","activity_type"),
	CONSTRAINT "notification_audience_settings_direction_check" CHECK (direction = ANY (ARRAY['outgoing'::text, 'incoming'::text])),
	CONSTRAINT "notification_audience_settings_audience_check" CHECK (audience = ANY (ARRAY['none'::text, 'close'::text, 'all'::text, 'ask'::text, 'match_run'::text]))
);
--> statement-breakpoint
CREATE TABLE "notification_log" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" text NOT NULL,
	"type" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now()
);
--> statement-breakpoint
CREATE TABLE "notification_settings" (
	"user_id" text PRIMARY KEY NOT NULL,
	"nudges_enabled" boolean DEFAULT true,
	"flexes_enabled" boolean DEFAULT true,
	"friend_activity_enabled" boolean DEFAULT true,
	"competition_invites_enabled" boolean DEFAULT true,
	"competition_updates_enabled" boolean DEFAULT true,
	"competition_milestones_enabled" boolean DEFAULT true,
	"quiet_hours_start" integer,
	"quiet_hours_end" integer,
	"created_at" timestamp with time zone DEFAULT now(),
	"updated_at" timestamp with time zone DEFAULT now(),
	"hypes_enabled" boolean DEFAULT true NOT NULL,
	"step_goal_enabled" boolean DEFAULT true NOT NULL,
	"friend_personal_best_enabled" boolean DEFAULT true,
	"daily_reminder_enabled" boolean DEFAULT true,
	"daily_reminder_hour" integer DEFAULT 18,
	"timezone_offset_minutes" integer
);
--> statement-breakpoint
CREATE TABLE "nudge_log" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"competition_id" text NOT NULL,
	"sender_id" text NOT NULL,
	"target_id" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now()
);
--> statement-breakpoint
CREATE TABLE "pending_friend_notifications" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"event_type" text NOT NULL,
	"activity_type" text DEFAULT '' NOT NULL,
	"workout_id" text,
	"payload" jsonb NOT NULL,
	"local_date" date NOT NULL,
	"status" text DEFAULT 'pending' NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "pending_friend_notifications_status_check" CHECK (status = ANY (ARRAY['pending'::text, 'sent'::text, 'dismissed'::text, 'expired'::text]))
);
--> statement-breakpoint
CREATE TABLE "pending_notifications" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" text NOT NULL,
	"type" text NOT NULL,
	"competition_id" text,
	"competition_name" text,
	"created_at" timestamp with time zone DEFAULT now(),
	"sent_at" timestamp with time zone
);
--> statement-breakpoint
CREATE TABLE "refresh_tokens" (
	"token_id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" varchar(32) NOT NULL,
	"token_hash" varchar(64) NOT NULL,
	"token_family_id" uuid NOT NULL,
	"created_at" timestamp DEFAULT now() NOT NULL,
	"last_used_at" timestamp DEFAULT now() NOT NULL,
	"expires_at" timestamp,
	"revoked_at" timestamp,
	"revoked_reason" varchar(50),
	"user_agent" text,
	"ip_address" "inet",
	"device_info" jsonb,
	CONSTRAINT "refresh_tokens_token_hash_key" UNIQUE("token_hash")
);
--> statement-breakpoint
CREATE TABLE "user_badges" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"badge_id" text NOT NULL,
	"earned_at" timestamp with time zone DEFAULT now() NOT NULL,
	"is_new" boolean DEFAULT true NOT NULL,
	"triggering_workout_id" varchar(255),
	"progress_snapshot" jsonb,
	"pin_slot" integer,
	CONSTRAINT "user_badges_user_id_badge_id_key" UNIQUE("user_id","badge_id"),
	CONSTRAINT "user_badges_pin_slot_range" CHECK ((pin_slot IS NULL) OR ((pin_slot >= 0) AND (pin_slot <= 2)))
);
--> statement-breakpoint
CREATE TABLE "user_challenge_completions" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"local_date" date NOT NULL,
	"challenge_key" text NOT NULL,
	"completed_at" timestamp with time zone DEFAULT now() NOT NULL,
	"completing_workout_id" varchar(255),
	CONSTRAINT "user_challenge_completions_user_id_local_date_key" UNIQUE("user_id","local_date")
);
--> statement-breakpoint
CREATE TABLE "users" (
	"user_id" text PRIMARY KEY NOT NULL,
	"username" varchar(30),
	"email" varchar(255),
	"first_name" varchar(50),
	"last_name" varchar(50),
	"apple_sub" varchar(255) NOT NULL,
	"profile_image_url" text,
	"bio" text,
	"role" varchar(20) DEFAULT 'user',
	"goal_miles" numeric DEFAULT '1.0' NOT NULL,
	"current_streak" integer DEFAULT 0 NOT NULL,
	CONSTRAINT "users_apple_id_key" UNIQUE("email"),
	CONSTRAINT "users_apple_sub_key" UNIQUE("apple_sub")
);
--> statement-breakpoint
CREATE TABLE "workout_completion_notifications" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" text NOT NULL,
	"notified_date" date NOT NULL,
	"created_at" timestamp with time zone DEFAULT now(),
	CONSTRAINT "workout_completion_notifications_user_id_notified_date_key" UNIQUE("user_id","notified_date")
);
--> statement-breakpoint
CREATE TABLE "workout_splits" (
	"id" serial PRIMARY KEY NOT NULL,
	"workout_id" varchar(255) NOT NULL,
	"split_number" integer NOT NULL,
	"split_duration" double precision NOT NULL,
	"split_distance" double precision,
	"split_pace" double precision,
	CONSTRAINT "workout_splits_workout_id_split_number_key" UNIQUE("workout_id","split_number")
);
--> statement-breakpoint
CREATE TABLE "workouts" (
	"workout_id" varchar(255) PRIMARY KEY NOT NULL,
	"user_id" varchar(255) NOT NULL,
	"distance" double precision NOT NULL,
	"local_date" date NOT NULL,
	"date" date NOT NULL,
	"timezone_offset" integer NOT NULL,
	"workout_type" varchar(50) NOT NULL,
	"device_end_date" timestamp with time zone NOT NULL,
	"calories" double precision NOT NULL,
	"total_duration" double precision NOT NULL,
	"created_at" timestamp with time zone DEFAULT now(),
	"source" varchar(20) DEFAULT 'healthkit' NOT NULL,
	"original_distance" double precision,
	"original_duration" double precision,
	"steps" integer,
	CONSTRAINT "workouts_user_workout_unique" UNIQUE("workout_id","user_id")
);
--> statement-breakpoint
ALTER TABLE "competition_users" ADD CONSTRAINT "competition_users_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "competition_users" ADD CONSTRAINT "competition_users_competition_id_fkey" FOREIGN KEY ("competition_id") REFERENCES "public"."competitions"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "competitions" ADD CONSTRAINT "competitions_winner_fkey" FOREIGN KEY ("winner") REFERENCES "public"."users"("user_id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "competitions" ADD CONSTRAINT "competitions_owner_fkey" FOREIGN KEY ("owner") REFERENCES "public"."users"("user_id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "daily_steps" ADD CONSTRAINT "daily_steps_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "device_tokens" ADD CONSTRAINT "device_tokens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "friendships" ADD CONSTRAINT "friendships_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "friendships" ADD CONSTRAINT "friendships_friend_id_fkey" FOREIGN KEY ("friend_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "in_app_notifications" ADD CONSTRAINT "in_app_notifications_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "pending_notifications" ADD CONSTRAINT "pending_notifications_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "refresh_tokens" ADD CONSTRAINT "refresh_tokens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "user_badges" ADD CONSTRAINT "user_badges_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "user_badges" ADD CONSTRAINT "user_badges_badge_id_fkey" FOREIGN KEY ("badge_id") REFERENCES "public"."badges"("badge_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "user_badges" ADD CONSTRAINT "user_badges_triggering_workout_id_fkey" FOREIGN KEY ("triggering_workout_id") REFERENCES "public"."workouts"("workout_id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "user_challenge_completions" ADD CONSTRAINT "user_challenge_completions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "user_challenge_completions" ADD CONSTRAINT "user_challenge_completions_challenge_key_fkey" FOREIGN KEY ("challenge_key") REFERENCES "public"."daily_challenges"("challenge_key") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "user_challenge_completions" ADD CONSTRAINT "user_challenge_completions_completing_workout_id_fkey" FOREIGN KEY ("completing_workout_id") REFERENCES "public"."workouts"("workout_id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "workout_splits" ADD CONSTRAINT "workout_splits_workout_id_fkey" FOREIGN KEY ("workout_id") REFERENCES "public"."workouts"("workout_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "idx_badges_category" ON "badges" USING btree ("category");--> statement-breakpoint
CREATE INDEX "idx_close_friends_friend" ON "close_friends" USING btree ("close_friend_id");--> statement-breakpoint
CREATE INDEX "idx_competition_users_comp" ON "competition_users" USING btree ("competition_id");--> statement-breakpoint
CREATE INDEX "idx_competition_users_competition" ON "competition_users" USING btree ("competition_id");--> statement-breakpoint
CREATE INDEX "idx_competition_users_rank_cache" ON "competition_users" USING btree ("competition_id","last_known_rank") WHERE ((invite_status)::text = 'accepted'::text);--> statement-breakpoint
CREATE INDEX "idx_competition_users_user" ON "competition_users" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "idx_competition_users_user_status" ON "competition_users" USING btree ("user_id","invite_status");--> statement-breakpoint
CREATE INDEX "idx_competitions_winner" ON "competitions" USING btree ("winner") WHERE (winner IS NOT NULL);--> statement-breakpoint
CREATE INDEX "idx_daily_steps_user_date" ON "daily_steps" USING btree ("user_id","local_date" DESC NULLS FIRST);--> statement-breakpoint
CREATE INDEX "idx_device_tokens_user_id" ON "device_tokens" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "idx_flex_log_lookup" ON "flex_log" USING btree ("sender_id","target_id","created_at" DESC NULLS FIRST);--> statement-breakpoint
CREATE INDEX "idx_friend_nudge_log_lookup" ON "friend_nudge_log" USING btree ("sender_id","target_id","created_at" DESC NULLS FIRST);--> statement-breakpoint
CREATE INDEX "idx_friendships_friend_status" ON "friendships" USING btree ("friend_id","status");--> statement-breakpoint
CREATE INDEX "idx_friendships_user_status" ON "friendships" USING btree ("user_id","status");--> statement-breakpoint
CREATE UNIQUE INDEX "hype_log_context_dedupe_idx" ON "hype_log" USING btree ("sender_id","target_id","context_type","context_id") WHERE (context_id IS NOT NULL);--> statement-breakpoint
CREATE INDEX "idx_hype_log_lookup" ON "hype_log" USING btree ("sender_id","created_at" DESC NULLS FIRST);--> statement-breakpoint
CREATE INDEX "idx_in_app_notifications_unread" ON "in_app_notifications" USING btree ("user_id","is_read") WHERE (is_read = false);--> statement-breakpoint
CREATE INDEX "idx_in_app_notifications_user" ON "in_app_notifications" USING btree ("user_id","created_at" DESC NULLS FIRST);--> statement-breakpoint
CREATE INDEX "idx_notification_log_user_date" ON "notification_log" USING btree ("user_id","created_at");--> statement-breakpoint
CREATE INDEX "idx_nudge_log_lookup" ON "nudge_log" USING btree ("competition_id","sender_id","target_id","created_at");--> statement-breakpoint
CREATE INDEX "idx_nudge_log_rate_limit" ON "nudge_log" USING btree ("competition_id","sender_id","target_id","created_at");--> statement-breakpoint
CREATE INDEX "idx_pending_friend_notif_user" ON "pending_friend_notifications" USING btree ("user_id","status");--> statement-breakpoint
CREATE UNIQUE INDEX "uq_pending_friend_notif_workout" ON "pending_friend_notifications" USING btree ("user_id","event_type","workout_id") WHERE ((workout_id IS NOT NULL) AND (status = 'pending'::text));--> statement-breakpoint
CREATE INDEX "idx_pending_notifications_unsent" ON "pending_notifications" USING btree ("user_id") WHERE (sent_at IS NULL);--> statement-breakpoint
CREATE INDEX "idx_refresh_tokens_family_id" ON "refresh_tokens" USING btree ("token_family_id");--> statement-breakpoint
CREATE INDEX "idx_refresh_tokens_revoked_at" ON "refresh_tokens" USING btree ("revoked_at") WHERE (revoked_at IS NULL);--> statement-breakpoint
CREATE INDEX "idx_refresh_tokens_token_hash" ON "refresh_tokens" USING btree ("token_hash");--> statement-breakpoint
CREATE INDEX "idx_refresh_tokens_user_id" ON "refresh_tokens" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "idx_user_badges_user" ON "user_badges" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "idx_user_badges_user_new" ON "user_badges" USING btree ("user_id") WHERE (is_new = true);--> statement-breakpoint
CREATE UNIQUE INDEX "idx_user_badges_user_pin_slot" ON "user_badges" USING btree ("user_id","pin_slot") WHERE (pin_slot IS NOT NULL);--> statement-breakpoint
CREATE INDEX "idx_user_badges_workout" ON "user_badges" USING btree ("triggering_workout_id");--> statement-breakpoint
CREATE INDEX "idx_ucc_user" ON "user_challenge_completions" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "idx_ucc_user_date" ON "user_challenge_completions" USING btree ("user_id","local_date" DESC NULLS FIRST);--> statement-breakpoint
CREATE INDEX "idx_users_current_streak_desc" ON "users" USING btree ("current_streak" DESC NULLS FIRST);--> statement-breakpoint
CREATE INDEX "idx_users_email_trgm" ON "users" USING gin ("email" gin_trgm_ops);--> statement-breakpoint
CREATE INDEX "idx_users_username" ON "users" USING btree ("username");--> statement-breakpoint
CREATE INDEX "idx_users_username_trgm" ON "users" USING gin ("username" gin_trgm_ops);--> statement-breakpoint
CREATE INDEX "idx_splits_time" ON "workout_splits" USING btree ("split_duration");--> statement-breakpoint
CREATE INDEX "idx_splits_workout" ON "workout_splits" USING btree ("workout_id");--> statement-breakpoint
CREATE INDEX "idx_workouts_local_date_user_id" ON "workouts" USING btree ("local_date","user_id");--> statement-breakpoint
CREATE INDEX "idx_workouts_user_device_end" ON "workouts" USING btree ("user_id","device_end_date" DESC NULLS FIRST);--> statement-breakpoint
CREATE INDEX "idx_workouts_user_local_date" ON "workouts" USING btree ("user_id","local_date" DESC NULLS FIRST);