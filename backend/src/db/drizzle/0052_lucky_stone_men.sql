ALTER TABLE "post_coauthors" ADD COLUMN "media_url" text;--> statement-breakpoint
ALTER TABLE "post_coauthors" ADD COLUMN "photo_added_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "posts" ADD COLUMN "buddy_session_id" varchar(32);--> statement-breakpoint
CREATE INDEX "idx_posts_buddy_session" ON "posts" USING btree ("buddy_session_id","created_at" DESC NULLS FIRST) WHERE (buddy_session_id IS NOT NULL AND deleted_at IS NULL);