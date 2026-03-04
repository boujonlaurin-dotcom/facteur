"""add_is_serene

Revision ID: s1r2n3e4f5g6
Revises: f6170e07e614
Create Date: 2026-03-04 14:00:00.000000

"""
from collections.abc import Sequence
from typing import Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 's1r2n3e4f5g6'
down_revision: Union[str, Sequence[str], None] = 'f6170e07e614'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Add is_serene boolean column to contents table."""
    op.add_column('contents', sa.Column('is_serene', sa.Boolean(), nullable=True))


def downgrade() -> None:
    """Remove is_serene column from contents table."""
    op.drop_column('contents', 'is_serene')
