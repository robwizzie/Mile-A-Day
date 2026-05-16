-- Leaderboard support — additive changes (apply BEFORE backend deploy)
-- Adds a precomputed current_streak column and an index for cross-user
-- date-windowed miles aggregation, which the /leaderboard endpoint needs.

-- Precomputed current_streak on users. Maintained by workoutService after
-- every workout upload so the streak leaderboard reads as a simple ORDER BY
-- instead of recomputing the streak per user on every leaderboard request.
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS current_streak INT NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_users_current_streak_desc
    ON users (current_streak DESC);

-- Cross-user, date-windowed miles aggregation. The existing per-user index
-- (workouts (user_id, local_date DESC)) is optimal for one-user queries but
-- doesn't help the leaderboard's "WHERE local_date >= ? GROUP BY user_id"
-- pattern. This index leads with local_date so the planner can range-scan
-- the relevant period and then bucket by user.
CREATE INDEX IF NOT EXISTS idx_workouts_local_date_user_id
    ON workouts (local_date, user_id);

-- Per-user opt-out for the global/friends leaderboard. Defaults to FALSE so
-- existing users appear on the leaderboard automatically; toggled via the
-- PATCH /users/:userId/leaderboard-opt-out endpoint. Opted-out users are
-- excluded from both the rankings list and their own current_user_entry.
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS leaderboard_opt_out BOOLEAN NOT NULL DEFAULT FALSE;

-- One-time backfill: seed current_streak for every existing user. Safe to
-- re-run; recomputes from workouts each call. Comment out after the first
-- successful run if you'd rather skip it on schema replays.
--
-- This uses the same "qualifying day = sum(distance) >= 0.95 mi" rule as
-- workoutService.getActiveStreak() and counts consecutive qualifying days
-- ending today or yesterday in each user's local timezone.
WITH user_today AS (
    SELECT u.user_id,
           (NOW() + (COALESCE(
               (SELECT timezone_offset FROM workouts w
                  WHERE w.user_id = u.user_id
                  ORDER BY device_end_date DESC LIMIT 1),
               0
           ) || ' minutes')::interval)::date AS today_local
    FROM users u
),
qualifying_days AS (
    SELECT user_id, local_date
    FROM workouts
    GROUP BY user_id, local_date
    HAVING SUM(distance) >= 0.95
),
streaks AS (
    SELECT q.user_id,
           q.local_date,
           (q.local_date - (ROW_NUMBER() OVER (PARTITION BY q.user_id ORDER BY q.local_date))::int) AS streak_group
    FROM qualifying_days q
),
streak_lengths AS (
    SELECT s.user_id,
           s.streak_group,
           MAX(s.local_date) AS streak_end,
           COUNT(*) AS streak_len
    FROM streaks s
    GROUP BY s.user_id, s.streak_group
),
current_streaks AS (
    SELECT sl.user_id, sl.streak_len
    FROM streak_lengths sl
    JOIN user_today ut ON ut.user_id = sl.user_id
    WHERE sl.streak_end = ut.today_local
       OR sl.streak_end = ut.today_local - INTERVAL '1 day'
)
UPDATE users u
SET current_streak = COALESCE(cs.streak_len, 0)
FROM (
    SELECT user_id, MAX(streak_len) AS streak_len
    FROM current_streaks
    GROUP BY user_id
) cs
WHERE u.user_id = cs.user_id;
