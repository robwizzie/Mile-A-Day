CREATE TABLE "post_highlight_items" (
	"highlight_id" uuid NOT NULL,
	"post_id" uuid NOT NULL,
	"sort_index" integer DEFAULT 0 NOT NULL,
	"added_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "post_highlight_items_pkey" PRIMARY KEY("highlight_id","post_id")
);
--> statement-breakpoint
CREATE TABLE "post_highlights" (
	"highlight_id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" text NOT NULL,
	"title" text NOT NULL,
	"cover_post_id" uuid,
	"sort_index" integer DEFAULT 0 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "post_highlights_title_check" CHECK (char_length(title) BETWEEN 1 AND 30)
);
--> statement-breakpoint
ALTER TABLE "post_coauthors" ADD COLUMN "on_feed" boolean;--> statement-breakpoint
ALTER TABLE "post_coauthors" ADD COLUMN "include_route" boolean;--> statement-breakpoint
ALTER TABLE "posts" ADD COLUMN "coauthor_on_feed" boolean;--> statement-breakpoint
ALTER TABLE "posts" ADD COLUMN "pinned_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "post_highlight_items" ADD CONSTRAINT "post_highlight_items_highlight_id_fkey" FOREIGN KEY ("highlight_id") REFERENCES "public"."post_highlights"("highlight_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "post_highlight_items" ADD CONSTRAINT "post_highlight_items_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "public"."posts"("post_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "post_highlights" ADD CONSTRAINT "post_highlights_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "post_highlights" ADD CONSTRAINT "post_highlights_cover_post_id_fkey" FOREIGN KEY ("cover_post_id") REFERENCES "public"."posts"("post_id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "idx_post_highlight_items_order" ON "post_highlight_items" USING btree ("highlight_id","sort_index","added_at");--> statement-breakpoint
CREATE INDEX "idx_post_highlight_items_post" ON "post_highlight_items" USING btree ("post_id");--> statement-breakpoint
CREATE INDEX "idx_post_highlights_user" ON "post_highlights" USING btree ("user_id","sort_index","created_at");--> statement-breakpoint
CREATE INDEX "idx_posts_user_pinned" ON "posts" USING btree ("user_id","pinned_at" DESC NULLS FIRST) WHERE (pinned_at IS NOT NULL AND deleted_at IS NULL);