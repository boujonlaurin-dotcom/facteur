"""Merge source weighting and is_serene heads.

Revision ID: sw02
Revises: sw01, c134526be6cd
Create Date: 2026-03-04

"""
from typing import Sequence, Union


# revision identifiers, used by Alembic.
revision: str = 'sw02'
down_revision: Union[str, Sequence[str], None] = ('sw01', 'c134526be6cd')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Merge heads — no schema changes."""
    pass


def downgrade() -> None:
    """Downgrade — no schema changes."""
    pass
