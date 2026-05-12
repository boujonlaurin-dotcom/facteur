"""Add is_liked_collection to collections table.

Revision ID: lc01
Revises: wl02
Create Date: 2026-03-14
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = 'lc01'
down_revision: Union[str, Sequence[str]] = 'wl02'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        'collections',
        sa.Column('is_liked_collection', sa.Boolean(), server_default='false', nullable=False),
    )


def downgrade() -> None:
    op.drop_column('collections', 'is_liked_collection')
