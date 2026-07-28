ALTER TABLE "competition_users" ADD COLUMN "team_id" text;--> statement-breakpoint
ALTER TABLE "competitions" ADD COLUMN "teams" jsonb;