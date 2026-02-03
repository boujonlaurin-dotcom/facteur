-- Digest performance indexes (run ONE statement at a time in Supabase SQL Editor)
-- If a statement times out: wait 30s, then retry that same statement.
-- After each CREATE INDEX, run the verification query below to confirm.

-- ========== 1. Composite index for Content queries ==========
CREATE INDEX ix_contents_source_published ON contents (source_id, published_at DESC);

-- ========== 2. Index for Emergency Fallback ==========
CREATE INDEX ix_contents_curated_published ON contents (published_at DESC, source_id);

-- ========== 3. Composite index for UserContentStatus exclusion ==========
CREATE INDEX ix_user_content_status_exclusion ON user_content_status (user_id, content_id, is_hidden, is_saved, status);

-- ========== 4. Index on Source.theme ==========
CREATE INDEX ix_sources_theme ON sources (theme);

-- ========== 5. Record migration as applied ==========
INSERT INTO alembic_version (version_num) VALUES ('x8y9z0a1b2c3');

-- ========== Verification (run after all above): list indexes ==========
-- SELECT indexname FROM pg_indexes WHERE indexname LIKE 'ix_%' ORDER BY indexname;
