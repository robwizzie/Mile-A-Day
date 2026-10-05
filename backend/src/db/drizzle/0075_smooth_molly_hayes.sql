CREATE TABLE "widget_refresh_pushes" (
	"user_id" text PRIMARY KEY NOT NULL,
	"last_sent_at" timestamp with time zone NOT NULL,
	"last_reason" text
);
--> statement-breakpoint
ALTER TABLE "device_tokens" ADD COLUMN "widget_kinds" text[];--> statement-breakpoint
ALTER TABLE "widget_refresh_pushes" ADD CONSTRAINT "widget_refresh_pushes_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;