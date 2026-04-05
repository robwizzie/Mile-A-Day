-- Notification System Tables
-- Run these against the PostgreSQL database manually

-- Friend nudge log (for friends list nudges, separate from competition nudges)
CREATE TABLE IF NOT EXISTS friend_nudge_log (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    sender_id TEXT NOT NULL,
    target_id TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_friend_nudge_log_lookup
    ON friend_nudge_log (sender_id, target_id, created_at DESC);

-- Flex log (per sender per target per day, across all competitions)
CREATE TABLE IF NOT EXISTS flex_log (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    sender_id TEXT NOT NULL,
    target_id TEXT NOT NULL,
    competition_id TEXT NOT NULL,
    message TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_flex_log_lookup
    ON flex_log (sender_id, target_id, created_at DESC);

-- Notification settings (per-user global preferences)
CREATE TABLE IF NOT EXISTS notification_settings (
    user_id TEXT PRIMARY KEY,
    nudges_enabled BOOLEAN DEFAULT TRUE,
    flexes_enabled BOOLEAN DEFAULT TRUE,
    friend_activity_enabled BOOLEAN DEFAULT TRUE,
    competition_invites_enabled BOOLEAN DEFAULT TRUE,
    competition_updates_enabled BOOLEAN DEFAULT TRUE,
    competition_milestones_enabled BOOLEAN DEFAULT TRUE,
    quiet_hours_start INTEGER,
    quiet_hours_end INTEGER,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Friend-specific notification settings (muting per friend)
CREATE TABLE IF NOT EXISTS friend_notification_settings (
    user_id TEXT NOT NULL,
    friend_id TEXT NOT NULL,
    muted BOOLEAN DEFAULT FALSE,
    nudges_muted BOOLEAN DEFAULT FALSE,
    activity_muted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (user_id, friend_id)
);

-- Workout completion notifications (prevents duplicate daily notifications)
CREATE TABLE IF NOT EXISTS workout_completion_notifications (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id TEXT NOT NULL,
    notified_date DATE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (user_id, notified_date)
);

-- Competition milestone notifications (prevents duplicate milestone alerts)
CREATE TABLE IF NOT EXISTS milestone_notifications (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    milestone_key TEXT UNIQUE NOT NULL,
    competition_id TEXT,
    user_id TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
