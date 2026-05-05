"""merge_epic11_deploy_heads

Revision ID: f6170e07e614
Revises: e11a0001, c3d4e5f6a7b8
Create Date: 2026-03-03 12:00:00.000000

"""
from collections.abc import Sequence
from typing import Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'f6170e07e614'
down_revision: Union[str, Sequence[str], None] = ('e11a0001', 'c3d4e5f6a7b8')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
