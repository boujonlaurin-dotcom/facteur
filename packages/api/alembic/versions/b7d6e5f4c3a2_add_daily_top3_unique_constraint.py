"""Add functional unique index to daily_top3

Revision ID: b7d6e5f4c3a2
Revises: k8l9m0n1o2p3
Create Date: 2026-01-22 17:30:00.000000

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = 'b7d6e5f4c3a2'
down_revision = 'a4b5c6d7e8f9'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Create functional unique index
    op.create_index(
        'uq_daily_top3_user_rank_day',
        'daily_top3',
        ['user_id', 'rank', sa.text("date(generated_at AT TIME ZONE 'UTC')")],
        unique=True
    )


def downgrade() -> None:
    op.drop_index('uq_daily_top3_user_rank_day', table_name='daily_top3')
