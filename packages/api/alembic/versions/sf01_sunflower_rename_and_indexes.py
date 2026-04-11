"""Sunflower 🌻 feature: rename liked collection + add scoring indexes.

Revision ID: sf01
Revises: td01
Create Date: 2026-04-11

"""
from collections.abc import Sequence

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "sf01"
down_revision: str = "td01"
branch_labels: Sequence[str] | None = None
depends_on: str | None = None


def upgrade() -> None:
    # Rename existing "Contenus likés" collections to new name
    op.execute(
        "UPDATE collections SET name = 'Mes articles intéressants 🌻' "
        "WHERE is_liked_collection = true AND name = 'Contenus likés'"
    )

    # Partial index for community scoring queries (liked articles by recency)
    op.execute(
        "CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_ucs_liked_at_partial "
        "ON user_content_status(liked_at DESC) "
        "WHERE is_liked = true"
    )

    # Index for future creator dashboard (aggregate by source)
    op.execute(
        "CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_ucs_content_liked_partial "
        "ON user_content_status(content_id) "
        "WHERE is_liked = true"
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_ucs_content_liked_partial")
    op.execute("DROP INDEX IF EXISTS ix_ucs_liked_at_partial")
    op.execute(
        "UPDATE collections SET name = 'Contenus likés' "
        "WHERE is_liked_collection = true AND name = 'Mes articles intéressants 🌻'"
    )
