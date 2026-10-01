ALTER TABLE "pending_notifications" ADD COLUMN "body" text;--> statement-breakpoint
ALTER TABLE "pending_notifications" ADD COLUMN "data" jsonb;--> statement-breakpoint
ALTER TABLE "pending_notifications" ADD COLUMN "category" text;--> statement-breakpoint
ALTER TABLE "pending_notifications" ADD COLUMN "reason" text;