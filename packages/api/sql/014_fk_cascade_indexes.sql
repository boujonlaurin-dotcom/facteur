-- 014_fk_cascade_indexes.sql
-- Phase 1.2 du fix de slowness (docs/bugs/bug-app-slowness.md).
-- Trois FK ON DELETE CASCADE référençaient public.contents(id) sans index
-- côté enfant. Le DELETE FROM contents du cleanup quotidien forçait un seq scan
-- complet sur chaque table enfant à chaque ligne supprimée.
--
-- Appliqué via Supabase SQL Editor (CLAUDE.md : pas d'Alembic sur Railway).

CREATE INDEX IF NOT EXISTS ix_user_content_status_content_id
    ON public.user_content_status (content_id);

CREATE INDEX IF NOT EXISTS ix_daily_top3_content_id
    ON public.daily_top3 (content_id);

CREATE INDEX IF NOT EXISTS ix_curation_annotations_content_id
    ON public.curation_annotations (content_id);
