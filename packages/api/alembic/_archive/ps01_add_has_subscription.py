"""Add has_subscription to user_sources for premium source support.

Revision ID: ps01
Revises: sw01
Create Date: 2026-03-06

"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'ps01'
down_revision: Union[str, Sequence[str]] = ('sw01', 'e12a0001')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    columns = [c['name'] for c in inspector.get_columns('user_sources')]
    if 'has_subscription' not in columns:
        op.add_column(
            'user_sources',
            sa.Column('has_subscription', sa.Boolean(), server_default='false', nullable=False),
        )


def downgrade() -> None:
    op.drop_column('user_sources', 'has_subscription')
