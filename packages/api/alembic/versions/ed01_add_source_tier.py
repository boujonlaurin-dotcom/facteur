"""Add source_tier column to sources for editorial digest deep sources.

Revision ID: ed01
Revises: ps01
Create Date: 2026-03-10

"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'ed01'
down_revision: Union[str, Sequence[str]] = 'ps01'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    columns = [c['name'] for c in inspector.get_columns('sources')]
    if 'source_tier' not in columns:
        op.add_column(
            'sources',
            sa.Column('source_tier', sa.String(20), server_default='mainstream', nullable=False),
        )


def downgrade() -> None:
    op.drop_column('sources', 'source_tier')
