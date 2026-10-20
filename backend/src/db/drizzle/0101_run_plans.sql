CREATE TABLE "run_plan_checkins" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"plan_id" uuid NOT NULL,
	"user_id" text NOT NULL,
	"local_date" date NOT NULL,
	"feeling" text,
	"message" text,
	"pain_flag" boolean DEFAULT false NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "run_plan_checkins_feeling_check" CHECK ("run_plan_checkins"."feeling" IS NULL OR "run_plan_checkins"."feeling" IN ('tired', 'sore', 'normal', 'great'))
);
--> statement-breakpoint
CREATE TABLE "run_plan_days" (
	"plan_id" uuid NOT NULL,
	"local_date" date NOT NULL,
	"kind" text NOT NULL,
	"title" text NOT NULL,
	"distance_mi" numeric(6, 2) NOT NULL,
	"segments" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"note" text,
	"source" text DEFAULT 'engine' NOT NULL,
	"original" jsonb,
	"moved_from" date,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "run_plan_days_pkey" PRIMARY KEY("plan_id","local_date"),
	CONSTRAINT "run_plan_days_kind_check" CHECK ("run_plan_days"."kind" IN ('streak', 'easy', 'intervals', 'tempo', 'long', 'race_test')),
	CONSTRAINT "run_plan_days_source_check" CHECK ("run_plan_days"."source" IN ('engine', 'flamey', 'claude', 'user'))
);
--> statement-breakpoint
CREATE TABLE "run_plan_proposals" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"plan_id" uuid NOT NULL,
	"source" text NOT NULL,
	"action" text NOT NULL,
	"summary" text NOT NULL,
	"rationale" text,
	"changes" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"cap_note" text,
	"status" text DEFAULT 'pending' NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"decided_at" timestamp with time zone,
	CONSTRAINT "run_plan_proposals_source_check" CHECK ("run_plan_proposals"."source" IN ('flamey', 'claude', 'engine')),
	CONSTRAINT "run_plan_proposals_status_check" CHECK ("run_plan_proposals"."status" IN ('pending', 'applied', 'declined', 'expired'))
);
--> statement-breakpoint
CREATE TABLE "run_plans" (
	"plan_id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" text NOT NULL,
	"status" text DEFAULT 'active' NOT NULL,
	"goals" jsonb NOT NULL,
	"effort" smallint NOT NULL,
	"hard_days" smallint,
	"run_daily_mile" boolean DEFAULT true NOT NULL,
	"finish_by" date,
	"start_date" date NOT NULL,
	"baseline" jsonb NOT NULL,
	"claude_auto_apply" boolean DEFAULT false NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"archived_at" timestamp with time zone,
	CONSTRAINT "run_plans_status_check" CHECK ("run_plans"."status" IN ('active', 'archived')),
	CONSTRAINT "run_plans_effort_check" CHECK ("run_plans"."effort" BETWEEN 1 AND 4),
	CONSTRAINT "run_plans_hard_days_check" CHECK ("run_plans"."hard_days" IS NULL OR "run_plans"."hard_days" BETWEEN 1 AND 7)
);
--> statement-breakpoint
ALTER TABLE "run_plan_checkins" ADD CONSTRAINT "run_plan_checkins_plan_id_fkey" FOREIGN KEY ("plan_id") REFERENCES "public"."run_plans"("plan_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "run_plan_checkins" ADD CONSTRAINT "run_plan_checkins_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "run_plan_days" ADD CONSTRAINT "run_plan_days_plan_id_fkey" FOREIGN KEY ("plan_id") REFERENCES "public"."run_plans"("plan_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "run_plan_proposals" ADD CONSTRAINT "run_plan_proposals_plan_id_fkey" FOREIGN KEY ("plan_id") REFERENCES "public"."run_plans"("plan_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "run_plans" ADD CONSTRAINT "run_plans_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "idx_run_plan_checkins_user_date" ON "run_plan_checkins" USING btree ("user_id","local_date");--> statement-breakpoint
CREATE INDEX "idx_run_plan_proposals_plan_status" ON "run_plan_proposals" USING btree ("plan_id","status");--> statement-breakpoint
CREATE UNIQUE INDEX "run_plans_one_active_per_user" ON "run_plans" USING btree ("user_id") WHERE (status = 'active'::text);--> statement-breakpoint
CREATE INDEX "idx_run_plans_user" ON "run_plans" USING btree ("user_id");