CREATE TABLE "weekly_recap_log" (
	"user_id" text NOT NULL,
	"week_start" date NOT NULL,
	"sent_at" timestamp with time zone DEFAULT now(),
	CONSTRAINT "weekly_recap_log_pkey" PRIMARY KEY("user_id","week_start")
);
--> statement-breakpoint
ALTER TABLE "notification_settings" ADD COLUMN "weekly_recap_enabled" boolean DEFAULT true;