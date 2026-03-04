"""Add priority_multiplier to user_sources for source weighting.

Revision ID: sw01
Revises: c3d4e5f6a7b8, b2c3d4e5f6a7, b3c4d5e6f7a8, f6170e07e614, f7e8a9b0c1d2, p1q2r3s4t5u6
Create Date: 2026-03-04

"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'sw01'
down_revision: Union[str, Sequence[str]] = (
    'c3d4e5f6a7b8',
    'b2c3d4e5f6a7',
    'b3c4d5e6f7a8',
    'f6170e07e614',
    'f7e8a9b0c1d2',
    'p1q2r3s4t5u6',
)
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        'user_sources',
        sa.Column('priority_multiplier', sa.Float(), server_default='1.0', nullable=False),
    )


def downgrade() -> None:
    op.drop_column('user_sources', 'priority_multiplier')
