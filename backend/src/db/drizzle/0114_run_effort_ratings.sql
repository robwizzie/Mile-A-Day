CREATE TABLE "run_effort_ratings" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" text NOT NULL,
	"plan_id" uuid,
	"workout_id" varchar(255) NOT NULL,
	"local_date" date NOT NULL,
	"run_type" text NOT NULL,
	"effort_type" text NOT NULL,
	"features" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"raw_guess" double precision NOT NULL,
	"offset_applied" double precision DEFAULT 0 NOT NULL,
	"guess" smallint NOT NULL,
	"user_rating" smallint,
	"rated_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "run_effort_ratings_effort_type_check" CHECK (effort_type IN ('easy', 'long', 'quality')),
	CONSTRAINT "run_effort_ratings_raw_guess_check" CHECK (raw_guess BETWEEN 1 AND 10),
	CONSTRAINT "run_effort_ratings_guess_check" CHECK (guess BETWEEN 1 AND 10),
	CONSTRAINT "run_effort_ratings_user_rating_check" CHECK (user_rating IS NULL OR user_rating BETWEEN 1 AND 10)
);
--> statement-breakpoint
ALTER TABLE "run_effort_ratings" ENABLE ROW LEVEL SECURITY;--> statement-breakpoint
ALTER TABLE "run_effort_ratings" ADD CONSTRAINT "run_effort_ratings_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "run_effort_ratings" ADD CONSTRAINT "run_effort_ratings_plan_id_fkey" FOREIGN KEY ("plan_id") REFERENCES "public"."run_plans"("plan_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "run_effort_ratings_user_workout" ON "run_effort_ratings" USING btree ("user_id","workout_id");--> statement-breakpoint
CREATE INDEX "idx_run_effort_ratings_user_date" ON "run_effort_ratings" USING btree ("user_id","local_date");--> statement-breakpoint
CREATE INDEX "idx_run_effort_ratings_user_type_rated" ON "run_effort_ratings" USING btree ("user_id","effort_type","rated_at") WHERE user_rating IS NOT NULL;