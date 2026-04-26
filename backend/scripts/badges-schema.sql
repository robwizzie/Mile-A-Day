-- Badges & Daily Challenges schema
-- Idempotent: safe to re-run. No migration framework in this repo; apply via psql "$DATABASE_URL" -f this file.

BEGIN;

-- 1. Extend existing tables
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS goal_miles NUMERIC NOT NULL DEFAULT 1.0;

ALTER TABLE workouts
    ADD COLUMN IF NOT EXISTS steps INTEGER;

-- 2. badges catalog
CREATE TABLE IF NOT EXISTS badges (
    badge_id     TEXT PRIMARY KEY,
    category     TEXT NOT NULL,
    name         TEXT NOT NULL,
    description  TEXT NOT NULL,
    icon         TEXT NOT NULL,
    rarity       TEXT NOT NULL CHECK (rarity IN ('common','rare','legendary')),
    requirement  NUMERIC,
    is_hidden    BOOLEAN NOT NULL DEFAULT FALSE,
    sort_order   INTEGER NOT NULL DEFAULT 0,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_badges_category ON badges(category);

-- 3. user-earned badges
CREATE TABLE IF NOT EXISTS user_badges (
    id                     BIGSERIAL PRIMARY KEY,
    user_id                TEXT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    badge_id               TEXT NOT NULL REFERENCES badges(badge_id) ON DELETE CASCADE,
    earned_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_new                 BOOLEAN NOT NULL DEFAULT TRUE,
    triggering_workout_id  VARCHAR(255) REFERENCES workouts(workout_id) ON DELETE SET NULL,
    progress_snapshot      JSONB,
    UNIQUE (user_id, badge_id)
);
CREATE INDEX IF NOT EXISTS idx_user_badges_user     ON user_badges(user_id);
CREATE INDEX IF NOT EXISTS idx_user_badges_user_new ON user_badges(user_id) WHERE is_new = TRUE;
CREATE INDEX IF NOT EXISTS idx_user_badges_workout  ON user_badges(triggering_workout_id);

-- 4. challenge catalog
CREATE TABLE IF NOT EXISTS daily_challenges (
    challenge_key         TEXT PRIMARY KEY,
    title                 TEXT NOT NULL,
    description_template  TEXT NOT NULL,
    icon                  TEXT NOT NULL,
    gradient_start        TEXT NOT NULL,
    gradient_end          TEXT NOT NULL,
    type                  TEXT NOT NULL CHECK (type IN ('pace','distance','time','activity','steps')),
    active                BOOLEAN NOT NULL DEFAULT TRUE,
    rotation_index        INTEGER NOT NULL UNIQUE,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 5. challenge completion history
CREATE TABLE IF NOT EXISTS user_challenge_completions (
    id                     BIGSERIAL PRIMARY KEY,
    user_id                TEXT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    local_date             DATE NOT NULL,
    challenge_key          TEXT NOT NULL REFERENCES daily_challenges(challenge_key),
    completed_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completing_workout_id  VARCHAR(255) REFERENCES workouts(workout_id) ON DELETE SET NULL,
    UNIQUE (user_id, local_date)
);
CREATE INDEX IF NOT EXISTS idx_ucc_user      ON user_challenge_completions(user_id);
CREATE INDEX IF NOT EXISTS idx_ucc_user_date ON user_challenge_completions(user_id, local_date DESC);

COMMIT;
