ALTER TABLE "competitions" ADD COLUMN "legacy_team_scoring" boolean DEFAULT false NOT NULL;--> statement-breakpoint
-- Freeze every competition that had ALREADY BEEN DECIDED on the rule that
-- decided it. Team standings are recomputed live on every read, finished
-- competitions included, while `competitions.winner` and
-- `competition_users.placement` were stamped once at resolution — so without
-- this, every team competition ever played would redraw its standings under
-- the new rule while still showing the medals the old one awarded.
--
-- A stamp rather than an `end_date < '<deploy date>'` test: a competition that
-- resolves just after this ships records the last COMPLETED interval as its
-- end_date, which is before the deploy (a whole month before, on a monthly
-- interval), so a date test would decide it under the new rule and then redraw
-- it under the old one.
--
-- Bounded and metadata-light: `competitions` is a small table and only rows
-- with a stamped winner are touched, so this stays well inside the 30s
-- statement timeout migrations run under at boot.
UPDATE "competitions" SET "legacy_team_scoring" = true WHERE "winner" IS NOT NULL;
