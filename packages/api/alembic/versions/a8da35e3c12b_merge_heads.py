"""merge_heads

Revision ID: a8da35e3c12b
Revises: b7d6e5f4c3a2, f7e8a9b0c1d2
Create Date: 2026-01-23 00:47:26.272687

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a8da35e3c12b'
down_revision: Union[str, Sequence[str], None] = ('b7d6e5f4c3a2', 'f7e8a9b0c1d2')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    pass


def downgrade() -> None:
    """Downgrade schema."""
    pass
