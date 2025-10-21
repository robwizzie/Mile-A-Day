-- Add user stats columns to users table
ALTER TABLE users ADD COLUMN IF NOT EXISTS streak INTEGER DEFAULT 0;
ALTER TABLE users ADD COLUMN IF NOT EXISTS total_miles DECIMAL(10, 2) DEFAULT 0.0;
ALTER TABLE users ADD COLUMN IF NOT EXISTS fastest_mile_pace DECIMAL(10, 2) DEFAULT 0.0;
ALTER TABLE users ADD COLUMN IF NOT EXISTS most_miles_in_one_day DECIMAL(10, 2) DEFAULT 0.0;
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_completion_date TIMESTAMP;
ALTER TABLE users ADD COLUMN IF NOT EXISTS goal_miles DECIMAL(10, 2) DEFAULT 1.0;

-- Create badges table
CREATE TABLE IF NOT EXISTS badges (
    badge_id SERIAL PRIMARY KEY,
    user_id VARCHAR(255) NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    badge_key VARCHAR(100) NOT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    date_awarded TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_new BOOLEAN DEFAULT TRUE,
    UNIQUE(user_id, badge_key)
);

-- Create index for faster badge queries
CREATE INDEX IF NOT EXISTS idx_badges_user_id ON badges(user_id);
