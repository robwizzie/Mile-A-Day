ALTER TABLE "users" ADD COLUMN "dedupe_since" timestamp with time zone DEFAULT now();--> statement-breakpoint
ALTER TABLE "workouts" ADD COLUMN "source_bundle_id" varchar(255);--> statement-breakpoint
ALTER TABLE "workouts" ADD COLUMN "duplicate_of" varchar(255);