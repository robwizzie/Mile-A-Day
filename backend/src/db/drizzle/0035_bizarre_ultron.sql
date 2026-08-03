CREATE TABLE "buddy_session_events" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"session_id" varchar(32) NOT NULL,
	"user_id" text,
	"kind" text NOT NULL,
	"payload" jsonb,
	"at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "buddy_session_participants" (
	"session_id" varchar(32) NOT NULL,
	"user_id" text NOT NULL,
	"status" text NOT NULL,
	"invited_by" text,
	"joined_at" timestamp with time zone,
	"ready_at" timestamp with time zone,
	"finished_at" timestamp with time zone,
	"distance_miles" double precision DEFAULT 0 NOT NULL,
	"duration_seconds" integer DEFAULT 0 NOT NULL,
	"last_progress_at" timestamp with time zone,
	"workout_id" varchar(255),
	"final_distance_miles" double precision,
	"place" integer,
	CONSTRAINT "buddy_session_participants_pkey" PRIMARY KEY("session_id","user_id"),
	CONSTRAINT "buddy_session_participants_status_check" CHECK (status = ANY (ARRAY['invited'::text, 'joined'::text, 'ready'::text, 'active'::text, 'finished'::text, 'left'::text, 'declined'::text]))
);
--> statement-breakpoint
CREATE TABLE "buddy_sessions" (
	"id" varchar(32) PRIMARY KEY DEFAULT replace((gen_random_uuid())::text, '-'::text, ''::text) NOT NULL,
	"join_code" varchar(8) NOT NULL,
	"host_user_id" text,
	"mode" text NOT NULL,
	"goal_value" double precision,
	"activity_type" varchar(50) NOT NULL,
	"status" text NOT NULL,
	"origin" text NOT NULL,
	"scheduled_start_at" timestamp with time zone,
	"started_at" timestamp with time zone,
	"ends_at" timestamp with time zone,
	"ended_at" timestamp with time zone,
	"winner_user_id" text,
	"state_version" integer DEFAULT 1 NOT NULL,
	"local_date" date NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "buddy_sessions_mode_check" CHECK (mode = ANY (ARRAY['together'::text, 'coop_goal'::text, 'race_goal'::text, 'race_time'::text])),
	CONSTRAINT "buddy_sessions_status_check" CHECK (status = ANY (ARRAY['lobby'::text, 'active'::text, 'completed'::text, 'cancelled'::text])),
	CONSTRAINT "buddy_sessions_origin_check" CHECK (origin = ANY (ARRAY['invite'::text, 'code'::text, 'join_active'::text, 'nearby'::text]))
);
--> statement-breakpoint
CREATE TABLE "post_coauthors" (
	"post_id" uuid NOT NULL,
	"user_id" text NOT NULL,
	"status" text DEFAULT 'pending' NOT NULL,
	"workout_id" varchar(255),
	"buddy_session_id" varchar(32),
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"responded_at" timestamp with time zone,
	CONSTRAINT "post_coauthors_pkey" PRIMARY KEY("post_id","user_id"),
	CONSTRAINT "post_coauthors_status_check" CHECK (status = ANY (ARRAY['pending'::text, 'accepted'::text, 'declined'::text]))
);
--> statement-breakpoint
ALTER TABLE "notification_settings" ADD COLUMN "buddy_invites_enabled" boolean DEFAULT true;--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "buddy_enrolled_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "buddy_session_events" ADD CONSTRAINT "buddy_session_events_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "public"."buddy_sessions"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "buddy_session_events" ADD CONSTRAINT "buddy_session_events_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "buddy_session_participants" ADD CONSTRAINT "buddy_session_participants_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "public"."buddy_sessions"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "buddy_session_participants" ADD CONSTRAINT "buddy_session_participants_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "buddy_session_participants" ADD CONSTRAINT "buddy_session_participants_workout_id_fkey" FOREIGN KEY ("workout_id") REFERENCES "public"."workouts"("workout_id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "buddy_sessions" ADD CONSTRAINT "buddy_sessions_host_user_id_fkey" FOREIGN KEY ("host_user_id") REFERENCES "public"."users"("user_id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "buddy_sessions" ADD CONSTRAINT "buddy_sessions_winner_user_id_fkey" FOREIGN KEY ("winner_user_id") REFERENCES "public"."users"("user_id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "post_coauthors" ADD CONSTRAINT "post_coauthors_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "public"."posts"("post_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "post_coauthors" ADD CONSTRAINT "post_coauthors_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "post_coauthors" ADD CONSTRAINT "post_coauthors_workout_id_fkey" FOREIGN KEY ("workout_id") REFERENCES "public"."workouts"("workout_id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "post_coauthors" ADD CONSTRAINT "post_coauthors_buddy_session_id_fkey" FOREIGN KEY ("buddy_session_id") REFERENCES "public"."buddy_sessions"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "idx_buddy_events_session_at" ON "buddy_session_events" USING btree ("session_id","at");--> statement-breakpoint
CREATE INDEX "idx_buddy_participants_user_status" ON "buddy_session_participants" USING btree ("user_id","status");--> statement-breakpoint
CREATE UNIQUE INDEX "uq_buddy_sessions_join_code_open" ON "buddy_sessions" USING btree ("join_code") WHERE (status = ANY (ARRAY['lobby'::text, 'active'::text]));--> statement-breakpoint
CREATE INDEX "idx_buddy_sessions_status_created" ON "buddy_sessions" USING btree ("status","created_at" DESC NULLS LAST);--> statement-breakpoint
CREATE INDEX "idx_post_coauthors_user" ON "post_coauthors" USING btree ("user_id","status");