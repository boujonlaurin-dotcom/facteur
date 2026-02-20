"""Add format_version to daily_digest for topics_v1 support.

Revision ID: g2h3i4j5k6l7
Revises: f1e2d3c4b5a6
Create Date: 2026-02-20 01:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'g2h3i4j5k6l7'
down_revision: Union[str, Sequence[str], None] = 'f1e2d3c4b5a6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        'daily_digest',
        sa.Column('format_version', sa.String(20), nullable=True, server_default='flat_v1'),
    )


def downgrade() -> None:
    op.drop_column('daily_digest', 'format_version')
