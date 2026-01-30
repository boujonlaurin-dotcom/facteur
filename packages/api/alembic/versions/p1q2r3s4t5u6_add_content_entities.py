"""add_content_entities

Revision ID: p1q2r3s4t5u6
Revises: z1a2b3c4d5e6
Create Date: 2026-01-30 18:45:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import ARRAY


# revision identifiers, used by Alembic.
revision: str = 'p1q2r3s4t5u6'
down_revision: Union[str, Sequence[str], None] = 'z1a2b3c4d5e6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Add entities column to contents table with GIN index."""
    # Add entities array column (stores entity dicts as JSON strings)
    op.add_column('contents', sa.Column('entities', ARRAY(sa.Text), nullable=True))
    
    # Create GIN index for efficient array searches
    op.create_index(
        'ix_contents_entities',
        'contents',
        ['entities'],
        unique=False,
        postgresql_using='gin'
    )


def downgrade() -> None:
    """Remove entities column and index from contents table."""
    op.drop_index('ix_contents_entities', table_name='contents', postgresql_using='gin')
    op.drop_column('contents', 'entities')
