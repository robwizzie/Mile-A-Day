ALTER TABLE "notification_settings" ADD COLUMN "route_privacy_meters" integer;--> statement-breakpoint
ALTER TABLE "workout_routes" ADD COLUMN "privacy_bounds" jsonb;--> statement-breakpoint
ALTER TABLE "notification_settings" ADD CONSTRAINT "notification_settings_route_privacy_meters_check" CHECK (route_privacy_meters IS NULL OR (route_privacy_meters >= 0 AND route_privacy_meters <= 1609));