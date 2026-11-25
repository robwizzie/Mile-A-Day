CREATE TABLE "app_settings" (
	"key" text PRIMARY KEY NOT NULL,
	"value" jsonb NOT NULL,
	"updated_by" text,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "coach_ai_calls" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" text NOT NULL,
	"provider" text NOT NULL,
	"kind" text NOT NULL,
	"trigger" text,
	"model" text,
	"client_call_id" text,
	"started_at" timestamp with time zone,
	"latency_ms" integer,
	"input" text,
	"output" text,
	"tool_calls" jsonb,
	"tokens_in" integer,
	"tokens_out" integer,
	"tokens_cached" integer,
	"tokens_cache_write" integer,
	"cost_usd" double precision,
	"error" text,
	"daily_limit_hit" boolean DEFAULT false NOT NULL,
	"proposal_ids" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "coach_ai_calls_provider_check" CHECK (provider IN ('apple', 'anthropic'))
);
--> statement-breakpoint
ALTER TABLE "coach_ai_calls" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
CREATE TABLE "coach_review_notes" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" text,
	"plan_id" uuid,
	"proposal_id" uuid,
	"body" text NOT NULL,
	"status" text DEFAULT 'open' NOT NULL,
	"source" text DEFAULT 'admin' NOT NULL,
	"author_id" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"resolved_at" timestamp with time zone,
	CONSTRAINT "coach_review_notes_status_check" CHECK (status IN ('open', 'resolved'))
);
--> statement-breakpoint
CREATE TABLE "coach_settings" (
	"user_id" text PRIMARY KEY NOT NULL,
	"ai_mode" text DEFAULT 'apple' NOT NULL,
	"user_opt_out" boolean DEFAULT false NOT NULL,
	"anthropic_consent_at" timestamp with time zone,
	"last_anthropic_run_at" timestamp with time zone,
	"updated_by" text,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "coach_settings_ai_mode_check" CHECK (ai_mode IN ('off', 'apple', 'anthropic'))
);
--> statement-breakpoint
CREATE TABLE "coach_spend_monthly" (
	"month" varchar(7) PRIMARY KEY NOT NULL,
	"spent_usd" double precision DEFAULT 0 NOT NULL,
	"calls" integer DEFAULT 0 NOT NULL,
	"warned_low_at" timestamp with time zone,
	"warned_high_at" timestamp with time zone,
	"stopped_at" timestamp with time zone,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "run_fitness_profiles" (
	"user_id" text PRIMARY KEY NOT NULL,
	"profile" jsonb NOT NULL,
	"computed_at" timestamp with time zone,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "run_fitness_profiles" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
CREATE TABLE "run_plan_checkins" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" text NOT NULL,
	"plan_id" uuid NOT NULL,
	"local_date" date NOT NULL,
	"time_available_min" smallint,
	"energy" smallint,
	"soreness" smallint,
	"go_further_mi" double precision,
	"text" text,
	"coach_mode" boolean,
	"proposal_id" uuid,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "run_plan_checkins_energy_check" CHECK (energy BETWEEN 0 AND 10),
	CONSTRAINT "run_plan_checkins_soreness_check" CHECK (soreness BETWEEN 0 AND 10)
);
--> statement-breakpoint
CREATE TABLE "run_plan_days" (
	"plan_id" uuid NOT NULL,
	"local_date" date NOT NULL,
	"kind" text NOT NULL,
	"day" jsonb NOT NULL,
	"note" text,
	"note_source" text DEFAULT 'template' NOT NULL,
	"version" integer DEFAULT 1 NOT NULL,
	"source" text DEFAULT 'formula' NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "run_plan_days_pkey" PRIMARY KEY("plan_id","local_date")
);
--> statement-breakpoint
CREATE TABLE "run_plan_grades" (
	"plan_id" uuid NOT NULL,
	"local_date" date NOT NULL,
	"user_id" text NOT NULL,
	"workout_id" varchar(255),
	"score" smallint NOT NULL,
	"completion" smallint NOT NULL,
	"on_target" smallint NOT NULL,
	"consistency" smallint NOT NULL,
	"source" text NOT NULL,
	"summary" text,
	"summary_source" text DEFAULT 'template' NOT NULL,
	"inputs" jsonb,
	"graded_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "run_plan_grades_pkey" PRIMARY KEY("plan_id","local_date"),
	CONSTRAINT "run_plan_grades_source_check" CHECK (source IN ('phone', 'server'))
);
--> statement-breakpoint
CREATE TABLE "run_plan_history" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"plan_id" uuid NOT NULL,
	"user_id" text NOT NULL,
	"at" timestamp with time zone DEFAULT now() NOT NULL,
	"event" text NOT NULL,
	"source" text,
	"proposal_id" uuid,
	"summary" text NOT NULL,
	"dates" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"detail" jsonb
);
--> statement-breakpoint
CREATE TABLE "run_plan_proposals" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"plan_id" uuid NOT NULL,
	"user_id" text NOT NULL,
	"source" text NOT NULL,
	"kind" text NOT NULL,
	"status" text DEFAULT 'pending' NOT NULL,
	"title" text NOT NULL,
	"reason" text NOT NULL,
	"goal_impact" jsonb,
	"changes" jsonb NOT NULL,
	"checks" jsonb NOT NULL,
	"first_date" date NOT NULL,
	"apply_after_date" date,
	"dedupe_key" text,
	"ai_call_id" uuid,
	"created_by" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"decided_at" timestamp with time zone,
	"applied_at" timestamp with time zone,
	"undo_until" timestamp with time zone,
	"notified_at" timestamp with time zone,
	CONSTRAINT "run_plan_proposals_source_check" CHECK (source IN ('formula', 'apple', 'anthropic', 'overseer', 'user_claude', 'user')),
	CONSTRAINT "run_plan_proposals_status_check" CHECK (status IN ('pending', 'scheduled', 'applied', 'declined', 'superseded', 'undone', 'expired'))
);
--> statement-breakpoint
CREATE TABLE "run_plans" (
	"plan_id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" text NOT NULL,
	"status" text DEFAULT 'active' NOT NULL,
	"goals" jsonb NOT NULL,
	"target_date" date,
	"runs_per_week" smallint NOT NULL,
	"difficulty" smallint NOT NULL,
	"walk_mode" text NOT NULL,
	"fixed_walk_days" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"coach_notes" text DEFAULT '' NOT NULL,
	"shoe_assignments" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"start_date" date NOT NULL,
	"baseline" jsonb NOT NULL,
	"source" text DEFAULT 'formula' NOT NULL,
	"last_open_date" date,
	"last_nightly_date" date,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"archived_at" timestamp with time zone,
	CONSTRAINT "run_plans_status_check" CHECK (status IN ('active', 'archived')),
	CONSTRAINT "run_plans_runs_per_week_check" CHECK (runs_per_week BETWEEN 1 AND 7),
	CONSTRAINT "run_plans_difficulty_check" CHECK (difficulty BETWEEN 1 AND 4),
	CONSTRAINT "run_plans_walk_mode_check" CHECK (walk_mode IN ('built_in', 'fixed', 'flexible'))
);
--> statement-breakpoint
ALTER TABLE "coach_ai_calls" ADD CONSTRAINT "coach_ai_calls_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "coach_review_notes" ADD CONSTRAINT "coach_review_notes_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "coach_review_notes" ADD CONSTRAINT "coach_review_notes_author_id_fkey" FOREIGN KEY ("author_id") REFERENCES "public"."users"("user_id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "coach_settings" ADD CONSTRAINT "coach_settings_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "run_fitness_profiles" ADD CONSTRAINT "run_fitness_profiles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "run_plan_checkins" ADD CONSTRAINT "run_plan_checkins_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "run_plan_checkins" ADD CONSTRAINT "run_plan_checkins_plan_id_fkey" FOREIGN KEY ("plan_id") REFERENCES "public"."run_plans"("plan_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "run_plan_days" ADD CONSTRAINT "run_plan_days_plan_id_fkey" FOREIGN KEY ("plan_id") REFERENCES "public"."run_plans"("plan_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "run_plan_grades" ADD CONSTRAINT "run_plan_grades_plan_id_fkey" FOREIGN KEY ("plan_id") REFERENCES "public"."run_plans"("plan_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "run_plan_grades" ADD CONSTRAINT "run_plan_grades_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "run_plan_history" ADD CONSTRAINT "run_plan_history_plan_id_fkey" FOREIGN KEY ("plan_id") REFERENCES "public"."run_plans"("plan_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "run_plan_history" ADD CONSTRAINT "run_plan_history_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "run_plan_proposals" ADD CONSTRAINT "run_plan_proposals_plan_id_fkey" FOREIGN KEY ("plan_id") REFERENCES "public"."run_plans"("plan_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "run_plan_proposals" ADD CONSTRAINT "run_plan_proposals_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "run_plans" ADD CONSTRAINT "run_plans_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "idx_coach_ai_calls_created" ON "coach_ai_calls" USING btree ("created_at");--> statement-breakpoint
CREATE INDEX "idx_coach_ai_calls_user_created" ON "coach_ai_calls" USING btree ("user_id","created_at");--> statement-breakpoint
CREATE UNIQUE INDEX "coach_ai_calls_client_id" ON "coach_ai_calls" USING btree ("user_id","client_call_id") WHERE client_call_id IS NOT NULL;--> statement-breakpoint
CREATE INDEX "idx_coach_review_notes_status" ON "coach_review_notes" USING btree ("status","created_at");--> statement-breakpoint
CREATE INDEX "idx_run_plan_checkins_user_date" ON "run_plan_checkins" USING btree ("user_id","local_date");--> statement-breakpoint
CREATE INDEX "idx_run_plan_history_plan_at" ON "run_plan_history" USING btree ("plan_id","at");--> statement-breakpoint
CREATE INDEX "idx_run_plan_proposals_plan_status" ON "run_plan_proposals" USING btree ("plan_id","status");--> statement-breakpoint
CREATE INDEX "idx_run_plan_proposals_pending_notify" ON "run_plan_proposals" USING btree ("first_date") WHERE status = 'pending' AND notified_at IS NULL;--> statement-breakpoint
CREATE UNIQUE INDEX "run_plan_proposals_dedupe" ON "run_plan_proposals" USING btree ("plan_id","dedupe_key") WHERE dedupe_key IS NOT NULL;--> statement-breakpoint
CREATE UNIQUE INDEX "run_plans_one_active_per_user" ON "run_plans" USING btree ("user_id") WHERE status = 'active';