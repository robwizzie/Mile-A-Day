-- Collab tags became immediate (Instagram-style): a coauthor is added when the
-- post is created and removes themselves afterwards if they'd rather not be on
-- it. There is no longer any UI that can answer a 'pending' invite, so rows
-- left in that state would sit there forever — showing on neither profile.
--
-- Settle them the way the new model would have created them. Every one of them
-- keeps the "Remove me from this post" exit, which is the same control a tag
-- created today has.
--
-- Bounded and cheap on purpose: posts with a pending coauthor are a tiny set
-- (the Feed UI predates the App Store build that ships it), so this stays a
-- plain in-migration UPDATE rather than a post-listen background backfill.
UPDATE posts
SET coauthor_status = 'accepted',
    coauthor_workout_id = COALESCE(
        coauthor_workout_id,
        (
            SELECT w.workout_id FROM workouts w
            WHERE w.user_id = posts.coauthor_user_id
                AND w.local_date = posts.local_date
                AND w.deleted_at IS NULL AND w.exclusion_reason IS NULL
            ORDER BY w.distance DESC LIMIT 1
        )
    )
WHERE coauthor_status = 'pending'
    AND coauthor_user_id IS NOT NULL
    AND deleted_at IS NULL;
