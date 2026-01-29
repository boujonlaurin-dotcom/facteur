"""add_custom_theme_to_constraint

Revision ID: 531d5a43b511
Revises: 1a2b3c4d5e6f
Create Date: 2026-01-29 14:37:48.261262

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '531d5a43b511'
down_revision: Union[str, Sequence[str], None] = '1a2b3c4d5e6f'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Add 'custom' to the allowed values in ck_source_theme_valid."""
    # Drop existing constraint
    op.execute("ALTER TABLE sources DROP CONSTRAINT IF EXISTS ck_source_theme_valid")
    # Re-create with 'custom' added
    op.create_check_constraint(
        "ck_source_theme_valid",
        "sources",
        "theme IN ('tech', 'society', 'environment', 'economy', 'politics', 'culture', 'science', 'international', 'custom')"
    )


def downgrade() -> None:
    """Remove 'custom' from the allowed values in ck_source_theme_valid."""
    # Drop existing constraint
    op.execute("ALTER TABLE sources DROP CONSTRAINT IF EXISTS ck_source_theme_valid")
    # Re-create without 'custom'
    op.create_check_constraint(
        "ck_source_theme_valid",
        "sources",
        "theme IN ('tech', 'society', 'environment', 'economy', 'politics', 'culture', 'science', 'international')"
    )
