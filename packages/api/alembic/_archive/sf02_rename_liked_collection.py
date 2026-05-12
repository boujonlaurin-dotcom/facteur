"""Rename 🌻 liked collection to 'Mes contenus recommandés 🌻'.

Revision ID: sf02
Revises: sf01
Create Date: 2026-04-13

sf01 already renamed "Contenus likés" → "Mes articles intéressants 🌻" and
has been applied in production. Alembic tracks revisions by ID, so editing
sf01 in place would not re-run on envs where it is already applied. This
follow-up migration performs the final rename to "Mes contenus recommandés
🌻" and is safe to run on any env regardless of which prior name the row
currently holds.
"""
from collections.abc import Sequence

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "sf02"
down_revision: str = "sf01"
branch_labels: Sequence[str] | None = None
depends_on: str | None = None


def upgrade() -> None:
    # Idempotent rename — handles both predecessor names so the migration
    # converges regardless of whether sf01 was already applied.
    op.execute(
        "UPDATE collections SET name = 'Mes contenus recommandés 🌻' "
        "WHERE is_liked_collection = true "
        "AND name IN ('Contenus likés', 'Mes articles intéressants 🌻')"
    )


def downgrade() -> None:
    op.execute(
        "UPDATE collections SET name = 'Mes articles intéressants 🌻' "
        "WHERE is_liked_collection = true "
        "AND name = 'Mes contenus recommandés 🌻'"
    )
