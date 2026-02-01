-- ==============================================================
-- Migration 011: Extend user_streaks with closure tracking (Epic 10)
-- ==============================================================
-- Purpose: Add closure streak tracking to the user_streaks table
-- for the digest-first experience. Closure streak tracks consecutive
-- days the user completed their digest (feeling "finished").
-- ==============================================================

-- Add closure_streak column if not exists
ALTER TABLE user_streaks 
    ADD COLUMN IF NOT EXISTS closure_streak INTEGER NOT NULL DEFAULT 0;

-- Add longest_closure_streak column if not exists
ALTER TABLE user_streaks 
    ADD COLUMN IF NOT EXISTS longest_closure_streak INTEGER NOT NULL DEFAULT 0;

-- Add last_closure_date column if not exists
ALTER TABLE user_streaks 
    ADD COLUMN IF NOT EXISTS last_closure_date DATE;

-- Add comments
COMMENT ON COLUMN user_streaks.closure_streak IS 
    'Current consecutive days of digest completion (feeling "finished")';
COMMENT ON COLUMN user_streaks.longest_closure_streak IS 
    'Longest ever consecutive days of digest completion';
COMMENT ON COLUMN user_streaks.last_closure_date IS 
    'Date of last digest completion (used for streak calculation)';

-- Create index for last_closure_date (useful for streak calculations)
CREATE INDEX IF NOT EXISTS ix_user_streaks_last_closure_date 
    ON user_streaks(last_closure_date);

-- Create index for closure_streak (useful for leaderboards/analytics)
CREATE INDEX IF NOT EXISTS ix_user_streaks_closure_streak 
    ON user_streaks(closure_streak);

-- ==============================================================
-- End Migration 011
-- ==============================================================
