DROP INDEX "idx_post_comments_post";--> statement-breakpoint
ALTER TABLE "post_comments" ALTER COLUMN "post_id" DROP NOT NULL;--> statement-breakpoint
ALTER TABLE "post_comments" ADD COLUMN "workout_id" varchar(255);--> statement-breakpoint
ALTER TABLE "post_comments" ADD CONSTRAINT "post_comments_workout_id_fkey" FOREIGN KEY ("workout_id") REFERENCES "public"."workouts"("workout_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "idx_post_comments_workout" ON "post_comments" USING btree ("workout_id","created_at") WHERE (deleted_at IS NULL AND workout_id IS NOT NULL);--> statement-breakpoint
CREATE INDEX "idx_post_comments_post" ON "post_comments" USING btree ("post_id","created_at") WHERE (deleted_at IS NULL AND post_id IS NOT NULL);--> statement-breakpoint
ALTER TABLE "post_comments" ADD CONSTRAINT "post_comments_one_target_check" CHECK (((post_id IS NOT NULL)::int + (workout_id IS NOT NULL)::int) = 1);