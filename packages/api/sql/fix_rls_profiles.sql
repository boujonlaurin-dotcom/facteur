-- ==============================================================
-- FIX RLS Policies for User Profiles & Onboarding
-- ==============================================================
-- Ce script configure les Row Level Security (RLS) policies
-- manquantes pour les tables liées au profil utilisateur.
-- Cela permet au client Flutter (via Supabase Auth) de lire/écrire
-- ses propres données.
--
-- À exécuter dans la console SQL de Supabase.
-- ==============================================================

-- 1. Table: user_profiles
ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;

-- SELECT: L'utilisateur peut lire son propre profil
CREATE POLICY "user_profiles_select_own" ON user_profiles
    FOR SELECT
    TO authenticated
    USING (user_id = auth.uid());

-- INSERT: L'utilisateur peut créer son propre profil (via trigger ou API)
-- Note: Si créé via API backend (service_role), cette policy n'est pas bloquante,
-- mais nécessaire si on permettait la création via client.
CREATE POLICY "user_profiles_insert_own" ON user_profiles
    FOR INSERT
    TO authenticated
    WITH CHECK (user_id = auth.uid());

-- UPDATE: L'utilisateur peut modifier son propre profil
CREATE POLICY "user_profiles_update_own" ON user_profiles
    FOR UPDATE
    TO authenticated
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());


-- 2. Table: user_preferences
ALTER TABLE user_preferences ENABLE ROW LEVEL SECURITY;

-- SELECT: Lire ses propres préférences
CREATE POLICY "user_preferences_select_own" ON user_preferences
    FOR SELECT
    TO authenticated
    USING (user_id = auth.uid());

-- INSERT: Ajouter ses propres préférences
CREATE POLICY "user_preferences_insert_own" ON user_preferences
    FOR INSERT
    TO authenticated
    WITH CHECK (user_id = auth.uid());

-- DELETE: Supprimer ses propres préférences (nécessaire pour le fix idempotence)
CREATE POLICY "user_preferences_delete_own" ON user_preferences
    FOR DELETE
    TO authenticated
    USING (user_id = auth.uid());


-- 3. Table: user_interests
ALTER TABLE user_interests ENABLE ROW LEVEL SECURITY;

-- SELECT: Lire ses propres intérêts
CREATE POLICY "user_interests_select_own" ON user_interests
    FOR SELECT
    TO authenticated
    USING (user_id = auth.uid());

-- INSERT: Ajouter ses propres intérêts
CREATE POLICY "user_interests_insert_own" ON user_interests
    FOR INSERT
    TO authenticated
    WITH CHECK (user_id = auth.uid());

-- DELETE: Supprimer ses propres intérêts (nécessaire pour le fix idempotence)
CREATE POLICY "user_interests_delete_own" ON user_interests
    FOR DELETE
    TO authenticated
    USING (user_id = auth.uid());


-- 4. Table: user_streaks
ALTER TABLE user_streaks ENABLE ROW LEVEL SECURITY;

-- SELECT: Lire son streak
CREATE POLICY "user_streaks_select_own" ON user_streaks
    FOR SELECT
    TO authenticated
    USING (user_id = auth.uid());

-- UPDATE: Mettre à jour son streak (si logique côté client, sinon via backend/triggers)
CREATE POLICY "user_streaks_update_own" ON user_streaks
    FOR UPDATE
    TO authenticated
    USING (user_id = auth.uid());

-- ==============================================================
-- Fin du script
-- ==============================================================
