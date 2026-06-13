-- 015_rls_auth_uid_optimization.sql
-- Phase 2.3 du fix slowness (docs/bugs/bug-app-slowness.md).
-- Wrap auth.uid() dans (SELECT auth.uid()) → init-plan caching :
-- Postgres évalue la fonction une fois par requête au lieu d'une fois par row.
-- Équivalence fonctionnelle stricte (même UUID retourné).
-- Ref : https://supabase.com/docs/guides/database/postgres/row-level-security
--
-- Appliqué via Supabase SQL Editor (CLAUDE.md : pas d'Alembic sur Railway).
-- Tout en 1 seule transaction → pas de fenêtre où la RLS est manquante.

BEGIN;

-- user_content_status (4 policies)
DROP POLICY IF EXISTS user_content_status_select_own ON public.user_content_status;
CREATE POLICY user_content_status_select_own ON public.user_content_status
    FOR SELECT USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS user_content_status_insert_own ON public.user_content_status;
CREATE POLICY user_content_status_insert_own ON public.user_content_status
    FOR INSERT WITH CHECK (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS user_content_status_update_own ON public.user_content_status;
CREATE POLICY user_content_status_update_own ON public.user_content_status
    FOR UPDATE USING (user_id = (SELECT auth.uid()))
    WITH CHECK (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS user_content_status_delete_own ON public.user_content_status;
CREATE POLICY user_content_status_delete_own ON public.user_content_status
    FOR DELETE USING (user_id = (SELECT auth.uid()));

-- user_sources (4 policies)
DROP POLICY IF EXISTS user_sources_select_own ON public.user_sources;
CREATE POLICY user_sources_select_own ON public.user_sources
    FOR SELECT USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS user_sources_insert_own ON public.user_sources;
CREATE POLICY user_sources_insert_own ON public.user_sources
    FOR INSERT WITH CHECK (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS user_sources_update_own ON public.user_sources;
CREATE POLICY user_sources_update_own ON public.user_sources
    FOR UPDATE USING (user_id = (SELECT auth.uid()))
    WITH CHECK (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS user_sources_delete_own ON public.user_sources;
CREATE POLICY user_sources_delete_own ON public.user_sources
    FOR DELETE USING (user_id = (SELECT auth.uid()));

-- user_profiles (3 policies — pas de DELETE)
DROP POLICY IF EXISTS user_profiles_select_own ON public.user_profiles;
CREATE POLICY user_profiles_select_own ON public.user_profiles
    FOR SELECT USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS user_profiles_insert_own ON public.user_profiles;
CREATE POLICY user_profiles_insert_own ON public.user_profiles
    FOR INSERT WITH CHECK (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS user_profiles_update_own ON public.user_profiles;
CREATE POLICY user_profiles_update_own ON public.user_profiles
    FOR UPDATE USING (user_id = (SELECT auth.uid()))
    WITH CHECK (user_id = (SELECT auth.uid()));

-- user_preferences (3 policies — pas d'UPDATE)
DROP POLICY IF EXISTS user_preferences_select_own ON public.user_preferences;
CREATE POLICY user_preferences_select_own ON public.user_preferences
    FOR SELECT USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS user_preferences_insert_own ON public.user_preferences;
CREATE POLICY user_preferences_insert_own ON public.user_preferences
    FOR INSERT WITH CHECK (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS user_preferences_delete_own ON public.user_preferences;
CREATE POLICY user_preferences_delete_own ON public.user_preferences
    FOR DELETE USING (user_id = (SELECT auth.uid()));

-- user_interests (3 policies — pas d'UPDATE)
DROP POLICY IF EXISTS user_interests_select_own ON public.user_interests;
CREATE POLICY user_interests_select_own ON public.user_interests
    FOR SELECT USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS user_interests_insert_own ON public.user_interests;
CREATE POLICY user_interests_insert_own ON public.user_interests
    FOR INSERT WITH CHECK (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS user_interests_delete_own ON public.user_interests;
CREATE POLICY user_interests_delete_own ON public.user_interests
    FOR DELETE USING (user_id = (SELECT auth.uid()));

-- user_streaks (2 policies — SELECT + UPDATE)
DROP POLICY IF EXISTS user_streaks_select_own ON public.user_streaks;
CREATE POLICY user_streaks_select_own ON public.user_streaks
    FOR SELECT USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS user_streaks_update_own ON public.user_streaks;
CREATE POLICY user_streaks_update_own ON public.user_streaks
    FOR UPDATE USING (user_id = (SELECT auth.uid()));

-- user_topic_profiles (1 ALL policy)
DROP POLICY IF EXISTS "Users can manage their own topic profiles" ON public.user_topic_profiles;
CREATE POLICY "Users can manage their own topic profiles" ON public.user_topic_profiles
    FOR ALL USING ((SELECT auth.uid()) = user_id)
    WITH CHECK ((SELECT auth.uid()) = user_id);

COMMIT;
