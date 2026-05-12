-- ============================================================================
-- vl01_create_veille_tables.sql
-- ============================================================================
-- Export SQL pour application manuelle dans Supabase SQL Editor (prod).
-- Équivalent à `alembic upgrade en01:vl01` (cf. alembic/versions/vl01_create_veille_tables.py).
--
-- Convention repo : Alembic tourne en local. En prod, le SQL est exécuté
-- manuellement dans Supabase SQL Editor (jamais d'Alembic sur Railway,
-- cf. CLAUDE.md "Contraintes Techniques").
--
-- 4 tables Epic 18 « Ma veille » (phase 2 backend) :
--   - veille_configs    : 1 active par user (partial UNIQUE), thème + cadence
--   - veille_topics     : topics rattachés (preset/suggested/custom)
--   - veille_sources    : sources rattachées (followed/niche), FK RESTRICT
--   - veille_deliveries : livraisons périodiques (squelette V1, items=[])
--
-- Pré-requis : extension `pgcrypto` activée pour `gen_random_uuid()`.
-- ============================================================================

-- Pré-requis : extension pour gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ─── 1. veille_configs ───────────────────────────────────────────────────────
CREATE TABLE veille_configs (
    id UUID DEFAULT gen_random_uuid() NOT NULL,
    user_id UUID NOT NULL,
    theme_id VARCHAR(50) NOT NULL,
    theme_label VARCHAR(120) NOT NULL,
    frequency VARCHAR(20) NOT NULL,
    day_of_week SMALLINT,
    delivery_hour SMALLINT DEFAULT 7 NOT NULL,
    timezone TEXT DEFAULT 'Europe/Paris' NOT NULL,
    status VARCHAR(20) DEFAULT 'active' NOT NULL,
    last_delivered_at TIMESTAMP WITH TIME ZONE,
    next_scheduled_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    PRIMARY KEY (id),
    FOREIGN KEY(user_id) REFERENCES user_profiles (user_id) ON DELETE CASCADE
);

CREATE INDEX ix_veille_configs_next_scheduled
    ON veille_configs (next_scheduled_at)
    WHERE status = 'active';

CREATE INDEX ix_veille_configs_user_id
    ON veille_configs (user_id);

-- Partial UNIQUE : 1 seule config ACTIVE par user (V1).
CREATE UNIQUE INDEX uq_veille_configs_user_active
    ON veille_configs (user_id)
    WHERE status = 'active';


-- ─── 2. veille_topics ────────────────────────────────────────────────────────
CREATE TABLE veille_topics (
    id UUID DEFAULT gen_random_uuid() NOT NULL,
    veille_config_id UUID NOT NULL,
    topic_id VARCHAR(80) NOT NULL,
    label VARCHAR(200) NOT NULL,
    kind VARCHAR(20) NOT NULL,
    reason TEXT,
    position SMALLINT DEFAULT 0 NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    PRIMARY KEY (id),
    CONSTRAINT uq_veille_topics_config_topic UNIQUE (veille_config_id, topic_id),
    FOREIGN KEY(veille_config_id) REFERENCES veille_configs (id) ON DELETE CASCADE
);


-- ─── 3. veille_sources ───────────────────────────────────────────────────────
CREATE TABLE veille_sources (
    id UUID DEFAULT gen_random_uuid() NOT NULL,
    veille_config_id UUID NOT NULL,
    source_id UUID NOT NULL,
    kind VARCHAR(20) NOT NULL,
    why TEXT,
    position SMALLINT DEFAULT 0 NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    PRIMARY KEY (id),
    CONSTRAINT uq_veille_sources_config_source UNIQUE (veille_config_id, source_id),
    FOREIGN KEY(veille_config_id) REFERENCES veille_configs (id) ON DELETE CASCADE,
    FOREIGN KEY(source_id) REFERENCES sources (id) ON DELETE RESTRICT
);

CREATE INDEX ix_veille_sources_source_id
    ON veille_sources (source_id);


-- ─── 4. veille_deliveries ────────────────────────────────────────────────────
CREATE TABLE veille_deliveries (
    id UUID DEFAULT gen_random_uuid() NOT NULL,
    veille_config_id UUID NOT NULL,
    target_date DATE NOT NULL,
    items JSONB DEFAULT '[]'::jsonb NOT NULL,
    generation_state VARCHAR(20) DEFAULT 'pending' NOT NULL,
    attempts SMALLINT DEFAULT 0 NOT NULL,
    started_at TIMESTAMP WITH TIME ZONE,
    finished_at TIMESTAMP WITH TIME ZONE,
    last_error TEXT,
    version SMALLINT DEFAULT 1 NOT NULL,
    generated_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    PRIMARY KEY (id),
    CONSTRAINT uq_veille_deliveries_config_target UNIQUE (veille_config_id, target_date),
    FOREIGN KEY(veille_config_id) REFERENCES veille_configs (id) ON DELETE CASCADE
);

CREATE INDEX ix_veille_deliveries_target_date
    ON veille_deliveries (target_date);

CREATE INDEX ix_veille_deliveries_state
    ON veille_deliveries (generation_state);


-- ============================================================================
-- Vérification post-migration
-- ============================================================================
-- SELECT tablename FROM pg_tables WHERE tablename LIKE 'veille_%' ORDER BY 1;
-- Attendu : 4 lignes (veille_configs / veille_deliveries / veille_sources / veille_topics)
