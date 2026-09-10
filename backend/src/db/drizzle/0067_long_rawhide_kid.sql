ALTER TABLE "post_highlight_items" ADD COLUMN "slide_key" text DEFAULT '' NOT NULL;--> statement-breakpoint
ALTER TABLE "post_highlight_items" DROP CONSTRAINT "post_highlight_items_pkey";
--> statement-breakpoint
ALTER TABLE "post_highlight_items" ADD CONSTRAINT "post_highlight_items_pkey" PRIMARY KEY("highlight_id","post_id","slide_key");