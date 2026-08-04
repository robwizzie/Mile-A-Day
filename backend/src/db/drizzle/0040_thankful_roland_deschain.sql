ALTER TABLE "workouts" ADD COLUMN "ghost_friend_user_id" varchar(255);--> statement-breakpoint
ALTER TABLE "workouts" ADD COLUMN "ghost_notified_at" timestamp with time zone;