"""Rename 🌻 liked collection to 'Mes contenus recommandés 🌻'.

Revision ID: sf02
Revises: sf01
Create Date: 2026-04-13

⚠️  NO-OP MIGRATION — applied manually via Supabase SQL Editor.

sf01 was neutralized to unblock Railway deploys (see its docstring). For
consistency with CLAUDE.md ("Alembic : jamais d'exécution sur Railway"),
the final rename is also applied out-of-band in Supabase SQL Editor and
`alembic_version` is stamped to 'sf02'.

Kept as a no-op so the revision chain stays valid and future migrations
can chain from 'sf02' without ambiguity.
"""
from collections.abc import Sequence

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "sf02"
down_revision: str = "sf01"
branch_labels: Sequence[str] | None = None
depends_on: str | None = None


def upgrade() -> None:
    # Intentionally empty — operations applied manually in Supabase.
    # See file docstring and PR #391 runbook.
    pass


def downgrade() -> None:
    # Reference rollback SQL — run manually in Supabase if needed.
    op.execute(
        "UPDATE collections SET name = 'Mes articles intéressants 🌻' "
        "WHERE is_liked_collection = true "
        "AND name = 'Mes contenus recommandés 🌻'"
    )
