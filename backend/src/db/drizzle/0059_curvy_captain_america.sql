CREATE TABLE "feature_events" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"user_id" varchar(255) NOT NULL,
	"feature" varchar(50) NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "stealth_windows" (
	"id" bigserial PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"started_at" timestamp with time zone NOT NULL,
	"ended_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "notification_settings" ADD COLUMN "auto_posts_on_profile" boolean DEFAULT true;--> statement-breakpoint
ALTER TABLE "notification_settings" ADD COLUMN "flyover_visibility" text DEFAULT 'friends' NOT NULL;--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "profile_banner_url" text;--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "profile_banner_style" varchar(24);--> statement-breakpoint
ALTER TABLE "workouts" ADD COLUMN "is_indoor" boolean;--> statement-breakpoint
ALTER TABLE "workouts" ADD COLUMN "stealth" boolean;--> statement-breakpoint
ALTER TABLE "stealth_windows" ADD CONSTRAINT "stealth_windows_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("user_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "idx_feature_events_feature_at" ON "feature_events" USING btree ("feature","created_at");--> statement-breakpoint
CREATE INDEX "idx_stealth_windows_user_started" ON "stealth_windows" USING btree ("user_id","started_at");--> statement-breakpoint
ALTER TABLE "notification_settings" ADD CONSTRAINT "notification_settings_flyover_visibility_check" CHECK (flyover_visibility = ANY (ARRAY['friends'::text, 'self'::text]));