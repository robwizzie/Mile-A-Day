ALTER TABLE "users" ADD COLUMN "nudges_sent_total" integer DEFAULT 0 NOT NULL;--> statement-breakpoint
-- Custom step: seed the lifetime counter from the nudge logs that still
-- exist. Both logs are pruned after 7 days (cleanupNotificationLogs), so this
-- is at most a week of rows and touches only the users who sent them — small
-- enough for a boot-time migration. From here on logNudge/logFriendNudge bump
-- the counter in the same statement as the log row, so it counts every nudge
-- sent since (deploy − 7 days); nothing older survives anywhere to count.
UPDATE "users" u
SET "nudges_sent_total" = n.total
FROM (
	SELECT sender_id, COUNT(*)::int AS total
	FROM (
		SELECT sender_id FROM "friend_nudge_log"
		UNION ALL
		SELECT sender_id FROM "nudge_log"
	) l
	GROUP BY sender_id
) n
WHERE u.user_id = n.sender_id;
