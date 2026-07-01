CREATE TABLE "story_reactions" (
	"post_id" uuid NOT NULL,
	"user_id" text NOT NULL,
	"emoji" varchar(16) NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "story_reactions_pkey" PRIMARY KEY("post_id","user_id")
);
--> statement-breakpoint
DROP INDEX "uq_posts_workout_active";--> statement-breakpoint
ALTER TABLE "story_reactions" ADD CONSTRAINT "story_reactions_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "public"."posts"("post_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "story_reactions" ADD CONSTRAINT "story_reactions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "uq_posts_workout_story" ON "posts" USING btree ("workout_id") WHERE (deleted_at IS NULL AND workout_id IS NOT NULL AND share_to_story AND NOT share_to_feed);--> statement-breakpoint
CREATE UNIQUE INDEX "uq_posts_workout_active" ON "posts" USING btree ("workout_id") WHERE (deleted_at IS NULL AND workout_id IS NOT NULL AND share_to_feed);