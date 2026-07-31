ALTER TABLE "notification_settings" ADD COLUMN "tagged_posts_on_profile" boolean DEFAULT true;--> statement-breakpoint
ALTER TABLE "posts" ADD COLUMN "coauthor_on_profile" boolean;