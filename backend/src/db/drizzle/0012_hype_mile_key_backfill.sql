-- Custom migration: collapse legacy 'mile' hype rows keyed by workout_id onto
-- the canonical `<userId>:<localDate>` composite key. Send-time
-- canonicalization has written only composite keys since v1.2; this migrates
-- the historical rows so read paths no longer need dual-key matching.
--
-- Step 1: rewrite each legacy row to its composite key. ROW_NUMBER picks one
-- winner when several legacy rows (two workouts on the same day) map to the
-- same composite, and NOT EXISTS skips rows whose composite twin already
-- exists — both guards keep hype_log_context_dedupe_idx from firing.
WITH mapped AS (
	SELECT h.id,
		(w.user_id || ':' || w.local_date::text) AS new_ctx,
		ROW_NUMBER() OVER (
			PARTITION BY h.sender_id, h.target_id, (w.user_id || ':' || w.local_date::text)
			ORDER BY h.created_at, h.id
		) AS rn
	FROM hype_log h
	JOIN workouts w ON w.workout_id = h.context_id
	WHERE h.context_type = 'mile'
		AND h.context_id !~ ':\d{4}-\d{2}-\d{2}$'
)
UPDATE hype_log h
SET context_id = m.new_ctx
FROM mapped m
WHERE h.id = m.id
	AND m.rn = 1
	AND NOT EXISTS (
		SELECT 1 FROM hype_log h2
		WHERE h2.sender_id = h.sender_id
			AND h2.target_id = h.target_id
			AND h2.context_type = 'mile'
			AND h2.context_id = m.new_ctx
	);
--> statement-breakpoint
-- Step 2: the legacy rows left over are exact duplicates of a composite row
-- that now exists (same sender/target/day) — drop ONLY those. Legacy rows
-- whose workout_id no longer resolves are kept untouched.
DELETE FROM hype_log h
USING workouts w
WHERE h.context_type = 'mile'
	AND h.context_id !~ ':\d{4}-\d{2}-\d{2}$'
	AND w.workout_id = h.context_id
	AND EXISTS (
		SELECT 1 FROM hype_log h2
		WHERE h2.sender_id = h.sender_id
			AND h2.target_id = h.target_id
			AND h2.context_type = 'mile'
			AND h2.context_id = (w.user_id || ':' || w.local_date::text)
	);
