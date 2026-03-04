"""merge_epic12_and_curation

Revision ID: e12a0002
Revises: e12a0001, ca01
Create Date: 2026-03-04 16:30:00.000000

Merge heads: e12a0001 (taxonomy slug migration) + ca01 (curation annotations).
"""
from collections.abc import Sequence
from typing import Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'e12a0002'
down_revision: Union[str, Sequence[str], None] = ('e12a0001', 'ca01')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
