ALTER TABLE "users" ADD COLUMN "streak_start_date" date;--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "streak_valid_through" date;--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "streak_computed_at" timestamp with time zone;