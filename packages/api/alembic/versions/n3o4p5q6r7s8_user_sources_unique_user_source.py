"""user_sources_unique_user_source

Revision ID: n3o4p5q6r7s8
Revises: m2n3o4p5q6r7
Create Date: 2026-01-30

Adds UNIQUE(user_id, source_id) on user_sources to enforce one link per user per source
and prevent duplicate custom sources in listings.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'n3o4p5q6r7s8'
down_revision: Union[str, Sequence[str], None] = 'm2n3o4p5q6r7'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Remove duplicates: keep one row per (user_id, source_id), delete others
    op.execute(sa.text("""
        DELETE FROM user_sources us
        USING user_sources us2
        WHERE us.user_id = us2.user_id AND us.source_id = us2.source_id AND us.id > us2.id
    """))
    op.create_unique_constraint(
        'uq_user_sources_user_source',
        'user_sources',
        ['user_id', 'source_id'],
    )


def downgrade() -> None:
    op.drop_constraint(
        'uq_user_sources_user_source',
        'user_sources',
        type_='unique',
    )
