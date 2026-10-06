ALTER TABLE "desk_box_settings" ADD COLUMN "sleep_start" smallint;--> statement-breakpoint
ALTER TABLE "desk_box_settings" ADD COLUMN "sleep_end" smallint;--> statement-breakpoint
ALTER TABLE "desk_box_settings" ADD COLUMN "never_sleep" boolean DEFAULT false NOT NULL;--> statement-breakpoint
ALTER TABLE "display_keys" ADD COLUMN "state" jsonb;--> statement-breakpoint
ALTER TABLE "display_keys" ADD COLUMN "state_at" timestamp with time zone;