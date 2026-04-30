"""add_source_theme_constraint

Revision ID: d1a2b3c4d5e6
Revises: ce8cff0c3c5d
Create Date: 2026-01-19 19:30:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'd1a2b3c4d5e6'
down_revision: Union[str, Sequence[str], None] = 'a1b2c3d4e5f6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Normalize Source.theme values and add CHECK constraint."""
    # Mapping for legacy theme values to normalized slugs
    theme_normalization = {
        'culture_ideas': 'culture',
        'geopolitics': 'international', 
        'society_climate': 'society',
        # Add more mappings if needed
    }
    
    # Normalize existing theme values
    for old_value, new_value in theme_normalization.items():
        op.execute(f"UPDATE sources SET theme = '{new_value}' WHERE theme = '{old_value}'")
    
    # Now add the CHECK constraint for data integrity
    op.create_check_constraint(
        "ck_source_theme_valid",
        "sources",
        "theme IN ('tech', 'society', 'environment', 'economy', 'politics', 'culture', 'science', 'international')"
    )


def downgrade() -> None:
    """Remove CHECK constraint from Source.theme column."""
    op.drop_constraint("ck_source_theme_valid", "sources", type_="check")
