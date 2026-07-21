CREATE TABLE "comment_reports" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"comment_id" uuid NOT NULL,
	"reporter_id" text NOT NULL,
	"reason" text NOT NULL,
	"details" text,
	"status" text DEFAULT 'open' NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "comment_reports_reason_check" CHECK (reason = ANY (ARRAY['spam'::text, 'nudity'::text, 'harassment'::text, 'violence'::text, 'other'::text]))
);
--> statement-breakpoint
CREATE TABLE "post_comments" (
	"comment_id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"post_id" uuid NOT NULL,
	"user_id" text NOT NULL,
	"parent_comment_id" uuid,
	"content" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"deleted_at" timestamp with time zone,
	CONSTRAINT "post_comments_content_check" CHECK (char_length(content) >= 1 AND char_length(content) <= 1000)
);
--> statement-breakpoint
ALTER TABLE "posts" ADD COLUMN "coauthor_user_id" text;--> statement-breakpoint
ALTER TABLE "posts" ADD COLUMN "coauthor_status" text;--> statement-breakpoint
ALTER TABLE "posts" ADD COLUMN "coauthor_workout_id" varchar(255);--> statement-breakpoint
ALTER TABLE "comment_reports" ADD CONSTRAINT "comment_reports_comment_id_fkey" FOREIGN KEY ("comment_id") REFERENCES "public"."post_comments"("comment_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "comment_reports" ADD CONSTRAINT "comment_reports_reporter_id_fkey" FOREIGN KEY ("reporter_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "post_comments" ADD CONSTRAINT "post_comments_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "public"."posts"("post_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "post_comments" ADD CONSTRAINT "post_comments_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "post_comments" ADD CONSTRAINT "post_comments_parent_fkey" FOREIGN KEY ("parent_comment_id") REFERENCES "public"."post_comments"("comment_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "comment_reports_dedupe_idx" ON "comment_reports" USING btree ("comment_id","reporter_id");--> statement-breakpoint
CREATE INDEX "idx_comment_reports_status" ON "comment_reports" USING btree ("status","created_at" DESC NULLS FIRST);--> statement-breakpoint
CREATE INDEX "idx_post_comments_post" ON "post_comments" USING btree ("post_id","created_at") WHERE (deleted_at IS NULL);--> statement-breakpoint
ALTER TABLE "posts" ADD CONSTRAINT "posts_coauthor_user_id_fkey" FOREIGN KEY ("coauthor_user_id") REFERENCES "public"."users"("user_id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "posts" ADD CONSTRAINT "posts_coauthor_workout_id_fkey" FOREIGN KEY ("coauthor_workout_id") REFERENCES "public"."workouts"("workout_id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "posts" ADD CONSTRAINT "posts_coauthor_status_check" CHECK (coauthor_status IS NULL OR coauthor_status = ANY (ARRAY['pending'::text, 'accepted'::text]));