"""merge_heads_final_v2

Revision ID: 752ae6586a6f
Revises: n3o4p5q6r7s8, p1q2r3s4t5u6
Create Date: 2026-01-31 16:26:20.121298

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '752ae6586a6f'
down_revision: Union[str, Sequence[str], None] = ('n3o4p5q6r7s8', 'p1q2r3s4t5u6')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    pass


def downgrade() -> None:
    """Downgrade schema."""
    pass
