CREATE TABLE "live_tracking_sessions" (
	"user_id" text PRIMARY KEY NOT NULL,
	"session_id" uuid DEFAULT gen_random_uuid() NOT NULL,
	"workout_type" varchar(50) NOT NULL,
	"started_at" timestamp with time zone DEFAULT now() NOT NULL,
	"last_seen_at" timestamp with time zone DEFAULT now() NOT NULL,
	"ended_at" timestamp with time zone
);
--> statement-breakpoint
ALTER TABLE "notification_settings" ADD COLUMN "share_live_presence" boolean DEFAULT true;--> statement-breakpoint
ALTER TABLE "live_tracking_sessions" ADD CONSTRAINT "live_tracking_sessions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;