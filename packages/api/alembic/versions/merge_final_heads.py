"""merge all heads into single revision chain

Revision ID: merge_final_heads
Revises: sw01, e12a0002
Create Date: 2026-03-04

Merge the 2 remaining heads (sw01 source weighting + e12a0002 epic12/curation)
into a single linear chain so alembic upgrade head works.
"""
from collections.abc import Sequence
from typing import Union


# revision identifiers, used by Alembic.
revision: str = 'merge_final_heads'
down_revision: Union[str, Sequence[str], None] = ('sw01', 'e12a0002')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
