-- Story 13.2 — Feed Pépites Carousel
--
-- A exécuter dans Supabase SQL Editor (prod + staging).
--
-- 1. Applique la migration Alembic (`pr01_feed_pepites_carousel`) manuellement
--    si Alembic n'a pas été run : ajoute les 2 colonnes sur `sources` et les 2
--    timestamps sur `user_personalization`. Idempotent.
-- 2. Seed initial : flag les sources à pousser dans le carousel.
--
-- Pour retirer une source du carousel plus tard :
--   UPDATE sources SET is_pepite_recommendation = FALSE WHERE name = '…';
-- Pour en ajouter une :
--   UPDATE sources SET is_pepite_recommendation = TRUE,
--          pepite_for_themes = ARRAY['tech']
--   WHERE name = '…';

BEGIN;

-- 1. Migration (idempotent). À skipper si Alembic a déjà joué pr01.
ALTER TABLE sources
  ADD COLUMN IF NOT EXISTS is_pepite_recommendation BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE sources
  ADD COLUMN IF NOT EXISTS pepite_for_themes TEXT[];

CREATE INDEX IF NOT EXISTS ix_sources_is_pepite_recommendation
  ON sources (is_pepite_recommendation);

ALTER TABLE user_personalization
  ADD COLUMN IF NOT EXISTS pepite_carousel_dismissed_at TIMESTAMPTZ;

ALTER TABLE user_personalization
  ADD COLUMN IF NOT EXISTS pepite_carousel_last_shown_at TIMESTAMPTZ;

-- 2. Seed initial — curation manuelle (liste à finaliser par Laurin).
-- Les `pepite_for_themes` sont utilisés pour prioriser l'affichage aux users
-- dont les thèmes suivis matchent. Sans match, les sources restent éligibles
-- mais passent après les matchs.

UPDATE sources
   SET is_pepite_recommendation = TRUE,
       pepite_for_themes = ARRAY['geopolitics', 'international']
 WHERE name ILIKE '%grand continent%';

UPDATE sources
   SET is_pepite_recommendation = TRUE,
       pepite_for_themes = ARRAY['tech']
 WHERE name ILIKE 'next.ink' OR name ILIKE 'next inpact%';

UPDATE sources
   SET is_pepite_recommendation = TRUE,
       pepite_for_themes = ARRAY['society', 'science']
 WHERE name ILIKE 'the conversation%';

UPDATE sources
   SET is_pepite_recommendation = TRUE,
       pepite_for_themes = ARRAY['environment']
 WHERE name ILIKE 'ethic et tac%';

-- Vérification :
SELECT id, name, theme, pepite_for_themes
  FROM sources
 WHERE is_pepite_recommendation = TRUE
 ORDER BY name;

COMMIT;
