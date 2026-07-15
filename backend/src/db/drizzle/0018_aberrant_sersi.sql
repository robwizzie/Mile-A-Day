ALTER TABLE "users" ADD COLUMN "referral_source" varchar(40);--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "referral_detail" varchar(120);--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "signup_goal" varchar(40);--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "experience_level" varchar(40);--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "onboarding_completed_at" timestamp with time zone;