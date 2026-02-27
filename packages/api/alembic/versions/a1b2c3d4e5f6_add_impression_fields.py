"""add_impression_fields

Revision ID: a1b2c3d4e5f6
Revises: z1a2b3c4d5e6
Create Date: 2026-02-24 10:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a1b2c3d4e5f6'
down_revision: Union[str, Sequence[str], None] = 'z1a2b3c4d5e6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Add last_impressed_at and manually_impressed to user_content_status."""
    op.add_column(
        'user_content_status',
        sa.Column('last_impressed_at', sa.DateTime(timezone=True), nullable=True)
    )
    op.add_column(
        'user_content_status',
        sa.Column('manually_impressed', sa.Boolean(), server_default='false', nullable=False)
    )


def downgrade() -> None:
    """Remove impression fields."""
    op.drop_column('user_content_status', 'manually_impressed')
    op.drop_column('user_content_status', 'last_impressed_at')
