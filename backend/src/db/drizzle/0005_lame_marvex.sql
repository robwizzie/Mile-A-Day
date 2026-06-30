ALTER TABLE "workouts" ADD COLUMN "deleted_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "workouts" ADD COLUMN "exclusion_reason" text;--> statement-breakpoint
ALTER TABLE "workouts" ADD COLUMN "speed_flagged" boolean DEFAULT false NOT NULL;