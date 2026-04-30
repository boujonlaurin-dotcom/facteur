"""Add mode column to daily_digest table

Revision ID: a1b2c3d4e5f7
Revises: 4d497ce7bcc2
Create Date: 2026-02-10 10:00:00.000000

Epic 11: Digest mode selector (pour_vous, serein, perspective, theme_focus).
Stores which mode was used to generate each daily digest.
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a1b2c3d4e5f7'
down_revision: Union[str, None] = '4d497ce7bcc2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        'daily_digest',
        sa.Column('mode', sa.String(30), nullable=True, server_default='pour_vous'),
    )


def downgrade() -> None:
    op.drop_column('daily_digest', 'mode')
