"""Add is_serene to daily_digest and update unique constraint.

Revision ID: sm01
Revises: lc01
Create Date: 2026-03-19
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = 'sm01'
down_revision: Union[str, Sequence[str]] = 'lc01'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 1. Add is_serene column
    op.add_column(
        'daily_digest',
        sa.Column('is_serene', sa.Boolean(), server_default='false', nullable=False),
    )

    # 2. Drop old unique constraint (user_id, target_date)
    op.drop_constraint('uq_daily_digest_user_date', 'daily_digest', type_='unique')

    # 3. Create new unique constraint (user_id, target_date, is_serene)
    op.create_unique_constraint(
        'uq_daily_digest_user_date_serene',
        'daily_digest',
        ['user_id', 'target_date', 'is_serene'],
    )


def downgrade() -> None:
    op.drop_constraint('uq_daily_digest_user_date_serene', 'daily_digest', type_='unique')
    op.drop_column('daily_digest', 'is_serene')
    op.create_unique_constraint(
        'uq_daily_digest_user_date', 'daily_digest', ['user_id', 'target_date']
    )
