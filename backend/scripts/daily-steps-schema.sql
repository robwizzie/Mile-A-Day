-- Daily Steps Tracking — additive changes (apply BEFORE backend deploy)
-- See docs/superpowers/specs/2026-04-28-daily-steps-tracking-design.md

CREATE TABLE IF NOT EXISTS daily_steps (
    user_id          TEXT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    local_date       DATE NOT NULL,
    steps            INT  NOT NULL CHECK (steps >= 0),
    timezone_offset  INT  NOT NULL,
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, local_date)
);

CREATE INDEX IF NOT EXISTS idx_daily_steps_user_date
    ON daily_steps (user_id, local_date DESC);

ALTER TABLE notification_settings
    ADD COLUMN IF NOT EXISTS step_goal_enabled BOOLEAN NOT NULL DEFAULT TRUE;

-- AFTER backend deploy of feature/daily-steps-tracking, run separately:
-- ALTER TABLE workouts DROP COLUMN steps;
