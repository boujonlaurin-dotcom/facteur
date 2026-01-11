-- ==============================================================
-- RLS Policies for Facteur - Story 3.1
-- ==============================================================
-- Ce script configure les Row Level Security (RLS) policies
-- pour les tables sources et contenus dans Supabase.
-- 
-- À exécuter dans la console SQL de Supabase.
-- ==============================================================

-- ==============================================================
-- 1. Table: sources
-- Lectures publiques pour les utilisateurs authentifiés
-- ==============================================================

ALTER TABLE sources ENABLE ROW LEVEL SECURITY;

-- Tout utilisateur authentifié peut lire toutes les sources
CREATE POLICY "sources_select_authenticated" ON sources
    FOR SELECT
    TO authenticated
    USING (true);

-- Seuls les admins peuvent insérer/modifier/supprimer (à définir plus tard)
-- Pour le MVP, on garde ça simple

-- ==============================================================
-- 2. Table: contents
-- Lectures publiques pour les utilisateurs authentifiés
-- ==============================================================

ALTER TABLE contents ENABLE ROW LEVEL SECURITY;

-- Tout utilisateur authentifié peut lire tous les contenus
CREATE POLICY "contents_select_authenticated" ON contents
    FOR SELECT
    TO authenticated
    USING (true);

-- ==============================================================
-- 3. Table: user_sources
-- RLS strict : chaque utilisateur ne voit que ses propres sources
-- ==============================================================

ALTER TABLE user_sources ENABLE ROW LEVEL SECURITY;

-- SELECT: L'utilisateur ne peut lire que ses propres associations
CREATE POLICY "user_sources_select_own" ON user_sources
    FOR SELECT
    TO authenticated
    USING (user_id = auth.uid());

-- INSERT: L'utilisateur peut créer des associations pour lui-même
CREATE POLICY "user_sources_insert_own" ON user_sources
    FOR INSERT
    TO authenticated
    WITH CHECK (user_id = auth.uid());

-- UPDATE: L'utilisateur peut modifier ses propres associations
CREATE POLICY "user_sources_update_own" ON user_sources
    FOR UPDATE
    TO authenticated
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

-- DELETE: L'utilisateur peut supprimer ses propres associations
CREATE POLICY "user_sources_delete_own" ON user_sources
    FOR DELETE
    TO authenticated
    USING (user_id = auth.uid());

-- ==============================================================
-- 4. Table: user_content_status
-- RLS strict : chaque utilisateur ne voit que ses propres statuts
-- ==============================================================

ALTER TABLE user_content_status ENABLE ROW LEVEL SECURITY;

-- SELECT: L'utilisateur ne peut lire que ses propres statuts
CREATE POLICY "user_content_status_select_own" ON user_content_status
    FOR SELECT
    TO authenticated
    USING (user_id = auth.uid());

-- INSERT: L'utilisateur peut créer des statuts pour lui-même
CREATE POLICY "user_content_status_insert_own" ON user_content_status
    FOR INSERT
    TO authenticated
    WITH CHECK (user_id = auth.uid());

-- UPDATE: L'utilisateur peut modifier ses propres statuts
CREATE POLICY "user_content_status_update_own" ON user_content_status
    FOR UPDATE
    TO authenticated
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

-- DELETE: L'utilisateur peut supprimer ses propres statuts
CREATE POLICY "user_content_status_delete_own" ON user_content_status
    FOR DELETE
    TO authenticated
    USING (user_id = auth.uid());

-- ==============================================================
-- Indexes supplémentaires pour les performances
-- (certains peuvent déjà exister via SQLAlchemy)
-- ==============================================================

-- Index pour les requêtes fréquentes sur user_sources
CREATE INDEX IF NOT EXISTS ix_user_sources_user_id ON user_sources(user_id);

-- Index pour les requêtes fréquentes sur user_content_status
CREATE INDEX IF NOT EXISTS ix_user_content_status_user_id ON user_content_status(user_id);
CREATE INDEX IF NOT EXISTS ix_user_content_status_content_id ON user_content_status(content_id);
CREATE INDEX IF NOT EXISTS ix_user_content_status_status ON user_content_status(status);

-- ==============================================================
-- Fin du script RLS
-- ==============================================================
