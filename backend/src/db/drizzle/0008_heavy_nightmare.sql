CREATE TABLE "workout_routes" (
	"workout_id" varchar(255) PRIMARY KEY NOT NULL,
	"route" jsonb NOT NULL,
	"point_count" integer NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "posts" ADD COLUMN "is_auto" boolean DEFAULT false NOT NULL;--> statement-breakpoint
ALTER TABLE "posts" ADD COLUMN "include_route" boolean DEFAULT true NOT NULL;--> statement-breakpoint
ALTER TABLE "workout_routes" ADD CONSTRAINT "workout_routes_workout_id_fkey" FOREIGN KEY ("workout_id") REFERENCES "public"."workouts"("workout_id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
-- Backfill: classify pre-existing auto route/stats cards (published by the app
-- when the user skips the post-run photo prompt) as auto, so a later
-- deliberate photo post can replace them instead of hitting the new
-- one-post-per-workout 409. Signature: caption-less feed-only post linked to a
-- workout with a stats snapshot.
UPDATE "posts" SET "is_auto" = true
WHERE "workout_id" IS NOT NULL
	AND "caption" IS NULL
	AND "stats_snapshot" IS NOT NULL
	AND "share_to_feed"
	AND NOT "share_to_story";
