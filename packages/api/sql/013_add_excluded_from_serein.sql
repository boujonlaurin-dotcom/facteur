-- Story 15.1 — Mode Serein Refine
-- Apply via Supabase SQL Editor (staging first, then prod).
-- Matches Alembic revision `sr01_add_serein_exclusion`
-- (which merges heads `ln01` + `ss01_search_cache`).

-- ========== 1. Add column ==========
ALTER TABLE user_topic_profiles
  ADD COLUMN IF NOT EXISTS excluded_from_serein BOOLEAN NOT NULL DEFAULT false;

-- ========== 2. Record migration as applied ==========
-- Remove the two prior heads that this revision merges, then insert the new head.
DELETE FROM alembic_version WHERE version_num IN ('ln01', 'ss01_search_cache');
INSERT INTO alembic_version (version_num) VALUES ('sr01_add_serein_exclusion')
  ON CONFLICT DO NOTHING;

-- ========== 3. Backfill serein_personalized for existing users ==========
-- Users who had sensitive_themes set before the refactor need the sentinel,
-- otherwise their digest reverts to defaults (regression). Only mark users
-- who already have a non-empty sensitive_themes preference.
INSERT INTO user_preferences (user_id, preference_key, preference_value)
SELECT DISTINCT user_id, 'serein_personalized', 'true'
FROM user_preferences
WHERE preference_key = 'sensitive_themes'
  AND preference_value IS NOT NULL
  AND preference_value <> ''
  AND preference_value <> '[]'
ON CONFLICT DO NOTHING;

-- ========== Verification ==========
-- SELECT column_name, data_type, is_nullable, column_default
-- FROM information_schema.columns
-- WHERE table_name = 'user_topic_profiles' AND column_name = 'excluded_from_serein';
--
-- SELECT version_num FROM alembic_version;
--
-- SELECT COUNT(*) FROM user_preferences WHERE preference_key = 'serein_personalized';
