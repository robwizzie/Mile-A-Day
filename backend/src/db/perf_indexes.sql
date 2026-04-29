-- Performance indexes for hot query paths.
-- All statements are idempotent (IF NOT EXISTS / IF EXISTS).
-- Run once against the PostgreSQL database; safe to re-run.

-- ============================================================================
-- workouts: queried per user_id, often ordered by local_date or device_end_date.
-- Used by: workoutService.getActiveStreak, getQuantityDateRange, getUserWorkouts;
-- friendshipService.getFriendsActivityToday; competitionService.getUserScores.
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_workouts_user_local_date
    ON workouts (user_id, local_date DESC);

CREATE INDEX IF NOT EXISTS idx_workouts_user_device_end
    ON workouts (user_id, device_end_date DESC);

-- ============================================================================
-- friendships: filtered by (user_id, status) and (friend_id, status).
-- Used by: friendshipService.getFriends, getFriendsActivityToday,
-- getIncomingRequests, etc.
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_friendships_user_status
    ON friendships (user_id, status);

CREATE INDEX IF NOT EXISTS idx_friendships_friend_status
    ON friendships (friend_id, status);

-- ============================================================================
-- competition_users: filtered by (user_id, invite_status) for "my competitions"
-- and by (competition_id) for participant lookups.
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_competition_users_user_status
    ON competition_users (user_id, invite_status);

CREATE INDEX IF NOT EXISTS idx_competition_users_competition
    ON competition_users (competition_id);

-- ============================================================================
-- users: searched via ILIKE '%query%' on username/email (leading wildcard,
-- so a plain btree won't help). pg_trgm enables index-backed ILIKE.
-- Also: GET /public/profile-image/:username does an exact-match lookup.
-- ============================================================================
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX IF NOT EXISTS idx_users_username_trgm
    ON users USING gin (username gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_users_email_trgm
    ON users USING gin (email gin_trgm_ops);

-- Exact-match username lookup (public profile image endpoint).
-- Skip if the schema already has a UNIQUE constraint on username — check first:
--   SELECT 1 FROM pg_indexes WHERE tablename = 'users' AND indexdef ILIKE '%username%';
CREATE INDEX IF NOT EXISTS idx_users_username
    ON users (username);
