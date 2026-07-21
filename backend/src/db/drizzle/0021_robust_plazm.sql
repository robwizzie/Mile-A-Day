CREATE TABLE "streak_coverage" (
	"user_id" text NOT NULL,
	"local_date" date NOT NULL,
	"kind" varchar(32) NOT NULL,
	"trigger_date" date,
	"source_user" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "streak_coverage_pkey" PRIMARY KEY("user_id","local_date")
);
--> statement-breakpoint
CREATE TABLE "streak_events" (
	"user_id" text NOT NULL,
	"local_date" date NOT NULL,
	"kind" varchar(24) NOT NULL,
	"prior_streak" integer DEFAULT 0 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "streak_events_pkey" PRIMARY KEY("user_id","local_date","kind")
);
--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "streak_features_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "double_down_last_used" date;--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "streak_save_last_used" date;--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "streak_assist_last_used" date;--> statement-breakpoint
ALTER TABLE "streak_coverage" ADD CONSTRAINT "streak_coverage_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "streak_events" ADD CONSTRAINT "streak_events_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;