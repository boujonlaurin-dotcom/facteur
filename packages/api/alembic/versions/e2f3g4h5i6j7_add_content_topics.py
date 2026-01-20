"""add_content_topics

Revision ID: e2f3g4h5i6j7
Revises: d1a2b3c4d5e6
Create Date: 2026-01-19 19:31:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import ARRAY


# revision identifiers, used by Alembic.
revision: str = 'e2f3g4h5i6j7'
down_revision: Union[str, Sequence[str], None] = 'd1a2b3c4d5e6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Add topics column to contents table with GIN index."""
    # Add topics array column
    op.add_column('contents', sa.Column('topics', ARRAY(sa.Text), nullable=True))
    
    # Create GIN index for efficient array searches
    op.create_index(
        'ix_contents_topics',
        'contents',
        ['topics'],
        unique=False,
        postgresql_using='gin'
    )


def downgrade() -> None:
    """Remove topics column and index from contents table."""
    op.drop_index('ix_contents_topics', table_name='contents', postgresql_using='gin')
    op.drop_column('contents', 'topics')
