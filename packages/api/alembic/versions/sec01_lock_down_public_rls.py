"""lock down public RLS exposure

Security remediation for exposed Supabase PostgREST tables:
enable RLS on user-owned tables, deny anonymous access, deny direct client
access to backend-only tables, and revoke public RPC execution.
"""

from alembic import op
from sqlalchemy import text

revision: str = "sec01_lock_down_public_rls"
down_revision: str | None = "cl01_drop_daily_top3"
branch_labels: str | None = None
depends_on: str | None = None

USER_OWNED_TABLES = (
    "collections",
    "article_feedback",
    "daily_digest",
    "digest_completions",
    "curation_annotations",
    "user_personalization",
    "user_entity_preferences",
    "user_topic_progress",
    "user_favorite_interests",
    "user_favorite_sources",
)

OPTIONAL_USER_OWNED_TABLES = ("serene_reports",)

BACKEND_ONLY_TABLES = (
    "digest_generation_state",
    "failed_source_attempts",
    "perspective_analyses",
    "topic_quizzes",
    "classification_queue",
    "source_search_cache",
    "editorial_highlights_history",
    "cluster_title_annotations",
)


def _bootstrap_supabase_auth_primitives() -> None:
    """Provide Supabase auth primitives when replaying migrations locally."""
    op.execute(
        """
        DO $$
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
                CREATE ROLE anon NOLOGIN;
            END IF;
            IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
                CREATE ROLE authenticated NOLOGIN;
            END IF;
        END $$;
        """
    )
    op.execute(
        """
        DO $$
        BEGIN
            CREATE SCHEMA IF NOT EXISTS auth;

            IF to_regprocedure('auth.uid()') IS NULL THEN
                EXECUTE $fn$
                    CREATE FUNCTION auth.uid()
                    RETURNS uuid
                    LANGUAGE sql
                    STABLE
                    AS $body$
                        SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid
                    $body$
                $fn$;
            END IF;
        END $$;
        """
    )


def _table_exists(table: str) -> bool:
    bind = op.get_bind()
    return bool(
        bind.execute(
            text("SELECT to_regclass(:table_name) IS NOT NULL"),
            {"table_name": f"public.{table}"},
        ).scalar()
    )


def _create_user_id_policies(table: str) -> None:
    for action in ("select", "insert", "update", "delete"):
        op.execute(f"DROP POLICY IF EXISTS {table}_{action}_own ON {table}")

    op.execute(
        f"""
        CREATE POLICY {table}_select_own ON {table}
            FOR SELECT TO authenticated
            USING (user_id = auth.uid())
        """
    )
    op.execute(
        f"""
        CREATE POLICY {table}_insert_own ON {table}
            FOR INSERT TO authenticated
            WITH CHECK (user_id = auth.uid())
        """
    )
    op.execute(
        f"""
        CREATE POLICY {table}_update_own ON {table}
            FOR UPDATE TO authenticated
            USING (user_id = auth.uid())
            WITH CHECK (user_id = auth.uid())
        """
    )
    op.execute(
        f"""
        CREATE POLICY {table}_delete_own ON {table}
            FOR DELETE TO authenticated
            USING (user_id = auth.uid())
        """
    )


def _lock_down_user_owned_table(table: str) -> None:
    op.execute(f"ALTER TABLE {table} ENABLE ROW LEVEL SECURITY")
    op.execute(f"REVOKE ALL ON TABLE {table} FROM anon")
    op.execute(f"GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE {table} TO authenticated")
    _create_user_id_policies(table)


def upgrade() -> None:
    _bootstrap_supabase_auth_primitives()

    for table in USER_OWNED_TABLES:
        _lock_down_user_owned_table(table)

    for table in OPTIONAL_USER_OWNED_TABLES:
        if _table_exists(table):
            _lock_down_user_owned_table(table)

    op.execute("ALTER TABLE collection_items ENABLE ROW LEVEL SECURITY")
    op.execute("REVOKE ALL ON TABLE collection_items FROM anon")
    op.execute("GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE collection_items TO authenticated")
    for action in ("select", "insert", "update", "delete"):
        op.execute(f"DROP POLICY IF EXISTS collection_items_{action}_own ON collection_items")
    op.execute(
        """
        CREATE POLICY collection_items_select_own ON collection_items
            FOR SELECT TO authenticated
            USING (
                EXISTS (
                    SELECT 1 FROM collections c
                    WHERE c.id = collection_id AND c.user_id = auth.uid()
                )
            )
        """
    )
    op.execute(
        """
        CREATE POLICY collection_items_insert_own ON collection_items
            FOR INSERT TO authenticated
            WITH CHECK (
                EXISTS (
                    SELECT 1 FROM collections c
                    WHERE c.id = collection_id AND c.user_id = auth.uid()
                )
            )
        """
    )
    op.execute(
        """
        CREATE POLICY collection_items_update_own ON collection_items
            FOR UPDATE TO authenticated
            USING (
                EXISTS (
                    SELECT 1 FROM collections c
                    WHERE c.id = collection_id AND c.user_id = auth.uid()
                )
            )
            WITH CHECK (
                EXISTS (
                    SELECT 1 FROM collections c
                    WHERE c.id = collection_id AND c.user_id = auth.uid()
                )
            )
        """
    )
    op.execute(
        """
        CREATE POLICY collection_items_delete_own ON collection_items
            FOR DELETE TO authenticated
            USING (
                EXISTS (
                    SELECT 1 FROM collections c
                    WHERE c.id = collection_id AND c.user_id = auth.uid()
                )
            )
        """
    )

    op.execute("ALTER TABLE veille_keywords ENABLE ROW LEVEL SECURITY")
    op.execute("REVOKE ALL ON TABLE veille_keywords FROM anon")
    op.execute("GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE veille_keywords TO authenticated")
    for action in ("select", "insert", "update", "delete"):
        op.execute(f"DROP POLICY IF EXISTS veille_keywords_{action}_own ON veille_keywords")
    op.execute(
        """
        CREATE POLICY veille_keywords_select_own ON veille_keywords
            FOR SELECT TO authenticated
            USING (
                EXISTS (
                    SELECT 1 FROM veille_configs vc
                    WHERE vc.id = veille_config_id AND vc.user_id = auth.uid()
                )
            )
        """
    )
    op.execute(
        """
        CREATE POLICY veille_keywords_insert_own ON veille_keywords
            FOR INSERT TO authenticated
            WITH CHECK (
                EXISTS (
                    SELECT 1 FROM veille_configs vc
                    WHERE vc.id = veille_config_id AND vc.user_id = auth.uid()
                )
            )
        """
    )
    op.execute(
        """
        CREATE POLICY veille_keywords_update_own ON veille_keywords
            FOR UPDATE TO authenticated
            USING (
                EXISTS (
                    SELECT 1 FROM veille_configs vc
                    WHERE vc.id = veille_config_id AND vc.user_id = auth.uid()
                )
            )
            WITH CHECK (
                EXISTS (
                    SELECT 1 FROM veille_configs vc
                    WHERE vc.id = veille_config_id AND vc.user_id = auth.uid()
                )
            )
        """
    )
    op.execute(
        """
        CREATE POLICY veille_keywords_delete_own ON veille_keywords
            FOR DELETE TO authenticated
            USING (
                EXISTS (
                    SELECT 1 FROM veille_configs vc
                    WHERE vc.id = veille_config_id AND vc.user_id = auth.uid()
                )
            )
        """
    )

    for table in BACKEND_ONLY_TABLES:
        op.execute(f"ALTER TABLE {table} ENABLE ROW LEVEL SECURITY")
        op.execute(f"REVOKE ALL ON TABLE {table} FROM anon, authenticated")

    op.execute(
        """
        DO $$
        BEGIN
            IF to_regprocedure('public.handle_new_user_notion_sync()') IS NOT NULL THEN
                REVOKE EXECUTE ON FUNCTION public.handle_new_user_notion_sync()
                FROM anon, authenticated;
            END IF;
        END $$;
        """
    )


def downgrade() -> None:
    op.execute(
        """
        DO $$
        BEGIN
            IF to_regprocedure('public.handle_new_user_notion_sync()') IS NOT NULL THEN
                GRANT EXECUTE ON FUNCTION public.handle_new_user_notion_sync()
                TO anon, authenticated;
            END IF;
        END $$;
        """
    )

    for table in BACKEND_ONLY_TABLES:
        op.execute(f"GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE {table} TO anon, authenticated")
        op.execute(f"ALTER TABLE {table} DISABLE ROW LEVEL SECURITY")

    for table in ("collection_items", "veille_keywords"):
        for action in ("select", "insert", "update", "delete"):
            op.execute(f"DROP POLICY IF EXISTS {table}_{action}_own ON {table}")
        op.execute(f"GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE {table} TO anon, authenticated")
        op.execute(f"ALTER TABLE {table} DISABLE ROW LEVEL SECURITY")

    for table in (*USER_OWNED_TABLES, *OPTIONAL_USER_OWNED_TABLES):
        if not _table_exists(table):
            continue
        for action in ("select", "insert", "update", "delete"):
            op.execute(f"DROP POLICY IF EXISTS {table}_{action}_own ON {table}")
        op.execute(f"GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE {table} TO anon, authenticated")
        op.execute(f"ALTER TABLE {table} DISABLE ROW LEVEL SECURITY")
