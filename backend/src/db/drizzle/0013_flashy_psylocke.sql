ALTER TABLE "users" ADD COLUMN "created_at" timestamp with time zone DEFAULT now() NOT NULL;--> statement-breakpoint
-- Backfill signup time for existing users from the upload timestamp of their
-- earliest workout (MIN(workouts.created_at) — the DB insert time, NOT the
-- workout's start date, which may be backdated for historical HealthKit syncs).
-- Users with no workouts keep the ADD COLUMN default (now()). MIN(created_at)
-- is stable (workouts only ever get newer insert times), so this is safe to
-- re-run under the catch-up applier.
UPDATE "users" u
SET "created_at" = w.first_upload
FROM (
	SELECT user_id, MIN(created_at) AS first_upload
	FROM "workouts"
	WHERE created_at IS NOT NULL
	GROUP BY user_id
) w
WHERE w.user_id = u.user_id;
