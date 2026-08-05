CREATE TABLE "buddy_recurring_walks" (
	"id" varchar(32) PRIMARY KEY DEFAULT replace((gen_random_uuid())::text, '-'::text, ''::text) NOT NULL,
	"host_user_id" text NOT NULL,
	"mode" text NOT NULL,
	"goal_value" double precision,
	"activity_type" varchar(50) NOT NULL,
	"invite_user_ids" text[] DEFAULT '{}'::text[] NOT NULL,
	"days_of_week" integer[] NOT NULL,
	"minutes_of_day" integer NOT NULL,
	"timezone" text NOT NULL,
	"is_active" boolean DEFAULT true NOT NULL,
	"last_spawned_date" date,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "buddy_recurring_walks_mode_check" CHECK (mode = ANY (ARRAY['together'::text, 'coop_goal'::text, 'race_goal'::text, 'race_time'::text])),
	CONSTRAINT "buddy_recurring_walks_minutes_check" CHECK (minutes_of_day >= 0 AND minutes_of_day <= 1439)
);
--> statement-breakpoint
ALTER TABLE "buddy_recurring_walks" ADD CONSTRAINT "buddy_recurring_walks_host_user_id_fkey" FOREIGN KEY ("host_user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "idx_buddy_recurring_active" ON "buddy_recurring_walks" USING btree ("is_active","host_user_id");