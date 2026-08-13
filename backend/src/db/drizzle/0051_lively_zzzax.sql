-- Weekly challenges moved from Monday–Sunday weeks to Sunday–Saturday.
--
-- Every row written so far was keyed by `date_trunc('week', ...)`, i.e. an ISO
-- Monday. Under Sunday weeks the containing week starts exactly one day
-- earlier, so shifting each key back a day maps it onto its new window.
--
-- Without this, `serveWeek` would look for the Sunday, miss, and stamp a
-- SECOND row for the same real week — stranding the Monday row as junk history
-- and re-announcing a challenge the user already has.
--
-- The `ISODOW = 1` guard makes each statement a no-op on anything already
-- Sunday-keyed, so a re-run can never shift twice. Tiny by construction: the
-- feature is days old, so these are a handful of rows and the whole migration
-- stays well inside the boot-time statement timeout.
UPDATE "user_weekly_challenges"
	SET "week_start" = "week_start" - 1
	WHERE EXTRACT(ISODOW FROM "week_start") = 1;
--> statement-breakpoint
UPDATE "user_weekly_challenge_completions"
	SET "week_start" = "week_start" - 1
	WHERE EXTRACT(ISODOW FROM "week_start") = 1;
--> statement-breakpoint
UPDATE "weekly_challenge_push_log"
	SET "week_start" = "week_start" - 1
	WHERE EXTRACT(ISODOW FROM "week_start") = 1;
