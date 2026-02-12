"""merge multiple heads: mode and is_liked

Revision ID: a424896cdfd9
Revises: a1b2c3d4e5f7, b3c4d5e6f7a8
Create Date: 2026-02-12 23:13:42.623770

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a424896cdfd9'
down_revision: Union[str, Sequence[str], None] = ('a1b2c3d4e5f7', 'b3c4d5e6f7a8')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    pass


def downgrade() -> None:
    """Downgrade schema."""
    pass
