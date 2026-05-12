"""Add is_default boolean to collections for default collection support.

Revision ID: bk01
Revises: ps01
Create Date: 2026-03-10

"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'bk01'
down_revision: Union[str, Sequence[str]] = 'ps01'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    columns = [c['name'] for c in inspector.get_columns('collections')]
    if 'is_default' not in columns:
        op.add_column(
            'collections',
            sa.Column('is_default', sa.Boolean(), server_default='false', nullable=False),
        )


def downgrade() -> None:
    op.drop_column('collections', 'is_default')
