"""lock down new public tables added after the RLS remediation.

Security follow-up for tables introduced on main while the public RLS lockdown
branch was in review. Keeps Alembic at one head and closes the remaining
Supabase Advisor `rls_disabled_in_public` findings for those new tables.
"""

from alembic import op

revision: str = "sec02_new_public_rls"
down_revision: str | None = "mg03_merge_security_rls_heads"
branch_labels: str | None = None
depends_on: str | None = None

BACKEND_ONLY_TABLES = (
    "api_usage_events",
    "event_rsvps",
    "grille_puzzles",
)


def upgrade() -> None:
    op.execute("ALTER TABLE grille_game_states ENABLE ROW LEVEL SECURITY")
    op.execute("REVOKE ALL ON TABLE grille_game_states FROM anon")
    op.execute(
        "GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE grille_game_states TO authenticated"
    )
    for action in ("select", "insert", "update", "delete"):
        op.execute(
            f"DROP POLICY IF EXISTS grille_game_states_{action}_own ON grille_game_states"
        )
    op.execute(
        """
        CREATE POLICY grille_game_states_select_own ON grille_game_states
            FOR SELECT TO authenticated
            USING (user_id = auth.uid())
        """
    )
    op.execute(
        """
        CREATE POLICY grille_game_states_insert_own ON grille_game_states
            FOR INSERT TO authenticated
            WITH CHECK (user_id = auth.uid())
        """
    )
    op.execute(
        """
        CREATE POLICY grille_game_states_update_own ON grille_game_states
            FOR UPDATE TO authenticated
            USING (user_id = auth.uid())
            WITH CHECK (user_id = auth.uid())
        """
    )
    op.execute(
        """
        CREATE POLICY grille_game_states_delete_own ON grille_game_states
            FOR DELETE TO authenticated
            USING (user_id = auth.uid())
        """
    )

    for table in BACKEND_ONLY_TABLES:
        op.execute(f"ALTER TABLE {table} ENABLE ROW LEVEL SECURITY")
        op.execute(f"REVOKE ALL ON TABLE {table} FROM anon, authenticated")


def downgrade() -> None:
    for table in BACKEND_ONLY_TABLES:
        op.execute(
            f"GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE {table} TO anon, authenticated"
        )
        op.execute(f"ALTER TABLE {table} DISABLE ROW LEVEL SECURITY")

    for action in ("select", "insert", "update", "delete"):
        op.execute(
            f"DROP POLICY IF EXISTS grille_game_states_{action}_own ON grille_game_states"
        )
    op.execute(
        "GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE grille_game_states TO anon, authenticated"
    )
    op.execute("ALTER TABLE grille_game_states DISABLE ROW LEVEL SECURITY")
