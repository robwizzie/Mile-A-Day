ALTER TABLE "posts" ADD COLUMN "coauthor_user_id" text;--> statement-breakpoint
ALTER TABLE "posts" ADD COLUMN "coauthor_status" text;--> statement-breakpoint
ALTER TABLE "posts" ADD COLUMN "coauthor_workout_id" varchar(255);--> statement-breakpoint
ALTER TABLE "posts" ADD CONSTRAINT "posts_coauthor_user_id_fkey" FOREIGN KEY ("coauthor_user_id") REFERENCES "public"."users"("user_id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "posts" ADD CONSTRAINT "posts_coauthor_workout_id_fkey" FOREIGN KEY ("coauthor_workout_id") REFERENCES "public"."workouts"("workout_id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "posts" ADD CONSTRAINT "posts_coauthor_status_check" CHECK (coauthor_status IS NULL OR coauthor_status = ANY (ARRAY['pending'::text, 'accepted'::text]));