-- ==============================================================
-- Migration 009: Create daily_digest table (Epic 10 - Digest Central)
-- ==============================================================
-- Purpose: Replace daily_top3 pattern with a 5-article digest model
-- The items column uses JSONB to store an array of 5 articles with
-- content_id references and metadata.
-- ==============================================================

-- Create daily_digest table if not exists
CREATE TABLE IF NOT EXISTS daily_digest (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    target_date DATE NOT NULL,
    items JSONB NOT NULL DEFAULT '[]'::jsonb,
    -- items schema: [{"content_id": "uuid", "rank": 1, "reason": "...", "source_slug": "..."}, ...]
    -- Exactly 5 items per digest
    generated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Create unique index for one digest per user per day
CREATE UNIQUE INDEX IF NOT EXISTS uq_daily_digest_user_date 
    ON daily_digest(user_id, target_date);

-- Create index for user lookups
CREATE INDEX IF NOT EXISTS ix_daily_digest_user_id 
    ON daily_digest(user_id);

-- Create index for date-based queries
CREATE INDEX IF NOT EXISTS ix_daily_digest_target_date 
    ON daily_digest(target_date);

-- Create index for generated_at (useful for cleanup queries)
CREATE INDEX IF NOT EXISTS ix_daily_digest_generated_at 
    ON daily_digest(generated_at);

-- Add comment explaining items structure
COMMENT ON COLUMN daily_digest.items IS 
    'JSONB array of 5 digest items. Each item: {content_id, rank, reason, source_slug}';

-- Enable Row Level Security
ALTER TABLE daily_digest ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Users can only see their own digests
CREATE POLICY IF NOT EXISTS "daily_digest_select_own" ON daily_digest
    FOR SELECT
    TO authenticated
    USING (user_id = auth.uid());

-- RLS Policy: Users cannot modify digests (read-only, system-generated)
-- No INSERT/UPDATE/DELETE policies - digests are system-generated only

-- ==============================================================
-- End Migration 009
-- ==============================================================
