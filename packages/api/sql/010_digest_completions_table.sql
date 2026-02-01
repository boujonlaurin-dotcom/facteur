-- ==============================================================
-- Migration 010: Create digest_completions table (Epic 10 - Digest Central)
-- ==============================================================
-- Purpose: Track user daily digest completions for streak and
-- engagement analytics. Records when a user finishes their digest.
-- ==============================================================

-- Create digest_completions table if not exists
CREATE TABLE IF NOT EXISTS digest_completions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    target_date DATE NOT NULL,
    completed_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    articles_read INTEGER NOT NULL DEFAULT 0,
    articles_saved INTEGER NOT NULL DEFAULT 0,
    articles_dismissed INTEGER NOT NULL DEFAULT 0,
    closure_time_seconds INTEGER,  -- Time spent to complete digest
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Create unique index for one completion record per user per day
CREATE UNIQUE INDEX IF NOT EXISTS uq_digest_completions_user_date 
    ON digest_completions(user_id, target_date);

-- Create index for user lookups
CREATE INDEX IF NOT EXISTS ix_digest_completions_user_id 
    ON digest_completions(user_id);

-- Create index for date-based queries
CREATE INDEX IF NOT EXISTS ix_digest_completions_target_date 
    ON digest_completions(target_date);

-- Create index for completed_at (useful for streak calculations)
CREATE INDEX IF NOT EXISTS ix_digest_completions_completed_at 
    ON digest_completions(completed_at);

-- Add comments
COMMENT ON TABLE digest_completions IS 
    'Tracks when users complete their daily digest for streak and analytics';
COMMENT ON COLUMN digest_completions.articles_read IS 
    'Number of articles marked as read in this digest';
COMMENT ON COLUMN digest_completions.articles_saved IS 
    'Number of articles saved for later';
COMMENT ON COLUMN digest_completions.articles_dismissed IS 
    'Number of articles marked as not interested';
COMMENT ON COLUMN digest_completions.closure_time_seconds IS 
    'Total time in seconds from first open to completion';

-- Enable Row Level Security
ALTER TABLE digest_completions ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Users can only see their own completion records
CREATE POLICY IF NOT EXISTS "digest_completions_select_own" ON digest_completions
    FOR SELECT
    TO authenticated
    USING (user_id = auth.uid());

-- RLS Policy: Users can insert their own completions
CREATE POLICY IF NOT EXISTS "digest_completions_insert_own" ON digest_completions
    FOR INSERT
    TO authenticated
    WITH CHECK (user_id = auth.uid());

-- RLS Policy: Users can update their own completions (e.g., updating closure_time)
CREATE POLICY IF NOT EXISTS "digest_completions_update_own" ON digest_completions
    FOR UPDATE
    TO authenticated
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

-- ==============================================================
-- End Migration 010
-- ==============================================================
