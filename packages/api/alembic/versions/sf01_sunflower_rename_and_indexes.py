"""Sunflower 🌻 feature: rename liked collection + add scoring indexes.

Revision ID: sf01
Revises: dg01
Create Date: 2026-04-11

⚠️  NO-OP MIGRATION — applied manually via Supabase SQL Editor.

Original upgrade() issued `CREATE INDEX CONCURRENTLY` inside Alembic's
`begin_transaction()` (see env.py), which Postgres forbids
(`CREATE INDEX CONCURRENTLY cannot run inside a transaction block`).
This broke every Railway deploy after PR #388 because the startup check
(`app/checks.py`) crashes the app when `alembic_version` lags behind code.

Per CLAUDE.md ("Alembic : jamais d'exécution sur Railway"), the DDL/UPDATE
for this revision is applied out-of-band in Supabase SQL Editor, and
`alembic_version` is stamped to 'sf02' manually. See deploy runbook in
the PR #391 description for the exact SQL.

Keeping this file as a no-op (instead of deleting it) preserves the
revision chain so Alembic history remains valid on environments that
still had `dg01` as HEAD at the time of the incident.
"""
from collections.abc import Sequence

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "sf01"
down_revision: str = "dg01"
branch_labels: Sequence[str] | None = None
depends_on: str | None = None


def upgrade() -> None:
    # Intentionally empty — operations applied manually in Supabase.
    # See file docstring and PR #391 runbook.
    pass


def downgrade() -> None:
    # Mirror of the manual operations, for reference only. Not executed
    # on Railway; run manually in Supabase if rollback is ever needed.
    op.execute("DROP INDEX IF EXISTS ix_ucs_content_liked_partial")
    op.execute("DROP INDEX IF EXISTS ix_ucs_liked_at_partial")
    op.execute(
        "UPDATE collections SET name = 'Contenus likés' "
        "WHERE is_liked_collection = true "
        "AND name = 'Mes articles intéressants 🌻'"
    )
