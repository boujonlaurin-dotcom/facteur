"""merge_epic11_with_main

Revision ID: b8d0b17ee658
Revises: c3d4e5f6a7b8, e11a0001
Create Date: 2026-03-03 12:02:24.216029

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'b8d0b17ee658'
down_revision: Union[str, Sequence[str], None] = ('c3d4e5f6a7b8', 'e11a0001')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    pass


def downgrade() -> None:
    """Downgrade schema."""
    pass
