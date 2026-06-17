-- Metadata-only verification for the public RLS security remediation.
-- Usage:
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f packages/api/scripts/verify_security_rls_metadata.sql
--
-- This reads PostgreSQL catalogs and privilege metadata only. It does not read
-- application rows.

\set ON_ERROR_STOP on

CREATE TEMP TABLE expected_security_rls (
    table_name text PRIMARY KEY,
    direct_client_access boolean NOT NULL,
    required boolean NOT NULL DEFAULT true
);

INSERT INTO expected_security_rls (table_name, direct_client_access, required)
VALUES
    ('collections', true, true),
    ('collection_items', true, true),
    ('article_feedback', true, true),
    ('daily_digest', true, true),
    ('digest_completions', true, true),
    ('curation_annotations', true, true),
    ('user_personalization', true, true),
    ('user_entity_preferences', true, true),
    ('user_topic_progress', true, true),
    ('user_favorite_interests', true, true),
    ('user_favorite_sources', true, true),
    ('veille_keywords', true, true),
    ('serene_reports', true, false),
    ('digest_generation_state', false, true),
    ('failed_source_attempts', false, true),
    ('perspective_analyses', false, true),
    ('topic_quizzes', false, true),
    ('classification_queue', false, true),
    ('source_search_cache', false, true),
    ('editorial_highlights_history', false, true),
    ('cluster_title_annotations', false, true);

DO $$
DECLARE
    failures text;
BEGIN
    SELECT string_agg(e.table_name, ', ' ORDER BY e.table_name)
    INTO failures
    FROM expected_security_rls e
    LEFT JOIN pg_class c
        ON c.oid = to_regclass(format('public.%I', e.table_name))
        AND c.relkind IN ('r', 'p')
    WHERE e.required AND c.oid IS NULL;

    IF failures IS NOT NULL THEN
        RAISE EXCEPTION 'Missing required RLS tables: %', failures;
    END IF;

    WITH present AS (
        SELECT e.table_name, e.direct_client_access, to_regclass(format('public.%I', e.table_name)) AS oid
        FROM expected_security_rls e
        WHERE to_regclass(format('public.%I', e.table_name)) IS NOT NULL
    )
    SELECT string_agg(p.table_name, ', ' ORDER BY p.table_name)
    INTO failures
    FROM present p
    JOIN pg_class c ON c.oid = p.oid
    WHERE NOT c.relrowsecurity;

    IF failures IS NOT NULL THEN
        RAISE EXCEPTION 'RLS is not enabled for: %', failures;
    END IF;

    WITH present AS (
        SELECT e.table_name, to_regclass(format('public.%I', e.table_name)) AS oid
        FROM expected_security_rls e
        WHERE to_regclass(format('public.%I', e.table_name)) IS NOT NULL
    )
    SELECT string_agg(table_name, ', ' ORDER BY table_name)
    INTO failures
    FROM present
    WHERE has_table_privilege('anon', oid, 'SELECT')
        OR has_table_privilege('anon', oid, 'INSERT')
        OR has_table_privilege('anon', oid, 'UPDATE')
        OR has_table_privilege('anon', oid, 'DELETE');

    IF failures IS NOT NULL THEN
        RAISE EXCEPTION 'anon still has direct DML grants on: %', failures;
    END IF;

    WITH present AS (
        SELECT e.table_name, to_regclass(format('public.%I', e.table_name)) AS oid
        FROM expected_security_rls e
        WHERE NOT e.direct_client_access
            AND to_regclass(format('public.%I', e.table_name)) IS NOT NULL
    )
    SELECT string_agg(table_name, ', ' ORDER BY table_name)
    INTO failures
    FROM present
    WHERE has_table_privilege('authenticated', oid, 'SELECT')
        OR has_table_privilege('authenticated', oid, 'INSERT')
        OR has_table_privilege('authenticated', oid, 'UPDATE')
        OR has_table_privilege('authenticated', oid, 'DELETE');

    IF failures IS NOT NULL THEN
        RAISE EXCEPTION 'authenticated still has backend-only DML grants on: %', failures;
    END IF;

    WITH present AS (
        SELECT e.table_name, to_regclass(format('public.%I', e.table_name)) AS oid
        FROM expected_security_rls e
        WHERE e.direct_client_access
            AND to_regclass(format('public.%I', e.table_name)) IS NOT NULL
    )
    SELECT string_agg(table_name, ', ' ORDER BY table_name)
    INTO failures
    FROM present
    WHERE NOT has_table_privilege('authenticated', oid, 'SELECT')
        OR NOT has_table_privilege('authenticated', oid, 'INSERT')
        OR NOT has_table_privilege('authenticated', oid, 'UPDATE')
        OR NOT has_table_privilege('authenticated', oid, 'DELETE');

    IF failures IS NOT NULL THEN
        RAISE EXCEPTION 'authenticated is missing client-table DML grants on: %', failures;
    END IF;

    IF to_regprocedure('public.handle_new_user_notion_sync()') IS NOT NULL THEN
        IF has_function_privilege('anon', 'public.handle_new_user_notion_sync()', 'EXECUTE') THEN
            RAISE EXCEPTION 'anon can still execute public.handle_new_user_notion_sync()';
        END IF;
        IF has_function_privilege('authenticated', 'public.handle_new_user_notion_sync()', 'EXECUTE') THEN
            RAISE EXCEPTION 'authenticated can still execute public.handle_new_user_notion_sync()';
        END IF;
    END IF;
END $$;

SELECT
    e.table_name,
    c.relrowsecurity AS rls_enabled,
    has_table_privilege('anon', c.oid, 'SELECT') AS anon_select,
    has_table_privilege('anon', c.oid, 'INSERT') AS anon_insert,
    has_table_privilege('anon', c.oid, 'UPDATE') AS anon_update,
    has_table_privilege('anon', c.oid, 'DELETE') AS anon_delete,
    has_table_privilege('authenticated', c.oid, 'SELECT') AS authenticated_select,
    has_table_privilege('authenticated', c.oid, 'INSERT') AS authenticated_insert,
    has_table_privilege('authenticated', c.oid, 'UPDATE') AS authenticated_update,
    has_table_privilege('authenticated', c.oid, 'DELETE') AS authenticated_delete,
    e.direct_client_access
FROM expected_security_rls e
JOIN pg_class c ON c.oid = to_regclass(format('public.%I', e.table_name))
ORDER BY e.table_name;

SELECT 'security RLS metadata verification passed' AS result;
