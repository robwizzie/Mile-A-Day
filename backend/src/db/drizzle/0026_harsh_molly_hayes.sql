ALTER TABLE "friendships" ADD COLUMN "created_at" timestamp with time zone DEFAULT now();--> statement-breakpoint
ALTER TABLE "friendships" ADD COLUMN "reminder_sent_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "notification_settings" ADD COLUMN "friend_request_reminder_enabled" boolean DEFAULT true;--> statement-breakpoint
-- Custom step: pre-claim every request that was already pending before this
-- deploy, so the new reminder cron can never fire for them.
--
-- Why this is needed: `ADD COLUMN created_at timestamptz DEFAULT now()` does NOT
-- rewrite the table in Postgres 11+. The default is stored once as a
-- missing-value attribute, so every pre-existing row reads back the SINGLE
-- evaluation of now() taken at DDL time — i.e. all legacy pending rows share
-- the deploy timestamp. A `created_at < now() - 24h` gate would therefore stay
-- quiet for exactly 24 hours and then make the entire historical backlog
-- eligible within one hour of each other.
--
-- Per-user coalescing bounds that to one push per affected user, but those
-- pushes would be about requests that are in many cases months old and
-- deliberately ignored. Stamping reminder_sent_at makes legacy rows permanently
-- ineligible; only requests created after this deploy can ever be reminded.
-- Surfacing the genuine backlog, if we want it, is a deliberate one-off to run
-- after the steady-state cron has been observed — not a deploy-day side effect.
UPDATE "friendships" SET "reminder_sent_at" = now()
	WHERE "status" = 'pending' AND "reminder_sent_at" IS NULL;