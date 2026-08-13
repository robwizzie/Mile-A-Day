CREATE TABLE "user_weekly_challenge_completions" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"week_start" date NOT NULL,
	"challenge_key" text NOT NULL,
	"target" double precision NOT NULL,
	"final_value" double precision NOT NULL,
	"completed_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "user_weekly_challenge_completions_user_id_week_start_key" UNIQUE("user_id","week_start")
);
--> statement-breakpoint
CREATE TABLE "user_weekly_challenges" (
	"user_id" text NOT NULL,
	"week_start" date NOT NULL,
	"challenge_key" text NOT NULL,
	"target" double precision NOT NULL,
	"baseline" double precision,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "user_weekly_challenges_pkey" PRIMARY KEY("user_id","week_start")
);
--> statement-breakpoint
CREATE TABLE "weekly_challenge_push_log" (
	"user_id" text NOT NULL,
	"week_start" date NOT NULL,
	"kind" text NOT NULL,
	"sent_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "weekly_challenge_push_log_pkey" PRIMARY KEY("user_id","week_start","kind")
);
--> statement-breakpoint
CREATE TABLE "weekly_challenges" (
	"challenge_key" text PRIMARY KEY NOT NULL,
	"title" text NOT NULL,
	"description_template" text NOT NULL,
	"icon" text NOT NULL,
	"gradient_start" text NOT NULL,
	"gradient_end" text NOT NULL,
	"metric" text NOT NULL,
	"unit" text NOT NULL,
	"base_target" double precision NOT NULL,
	"scale_multiplier" double precision DEFAULT 1.1 NOT NULL,
	"scale_min_multiplier" double precision DEFAULT 1 NOT NULL,
	"scale_max_multiplier" double precision DEFAULT 2.5 NOT NULL,
	"target_ceiling" double precision NOT NULL,
	"target_step" double precision DEFAULT 1 NOT NULL,
	"active" boolean DEFAULT true NOT NULL,
	"rotation_index" integer NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "weekly_challenges_rotation_index_key" UNIQUE("rotation_index")
);
--> statement-breakpoint
ALTER TABLE "notification_settings" ADD COLUMN "weekly_challenge_enabled" boolean DEFAULT true;--> statement-breakpoint
ALTER TABLE "user_weekly_challenge_completions" ADD CONSTRAINT "user_weekly_challenge_completions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "user_weekly_challenge_completions" ADD CONSTRAINT "user_weekly_challenge_completions_challenge_key_fkey" FOREIGN KEY ("challenge_key") REFERENCES "public"."weekly_challenges"("challenge_key") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "user_weekly_challenges" ADD CONSTRAINT "user_weekly_challenges_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "user_weekly_challenges" ADD CONSTRAINT "user_weekly_challenges_challenge_key_fkey" FOREIGN KEY ("challenge_key") REFERENCES "public"."weekly_challenges"("challenge_key") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "weekly_challenge_push_log" ADD CONSTRAINT "weekly_challenge_push_log_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "idx_uwcc_user_week" ON "user_weekly_challenge_completions" USING btree ("user_id","week_start" DESC NULLS FIRST);