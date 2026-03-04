"""Merge source-weighting head (sw01) with main head (e12a0002).

Revision ID: sw02
Revises: sw01, e12a0002
Create Date: 2026-03-04

Context:
- sw01: add priority_multiplier to user_sources (source weighting feature)
- e12a0002: main's pre-existing merge head (e12a0001 taxonomy slugs + ca01 curation)

s1r2n3e4f5g6 was a duplicate add_is_serene already applied to prod via
c134526be6cd (PR #153 rename fix). It has been deleted from this branch.
"""
from typing import Sequence, Union


# revision identifiers, used by Alembic.
revision: str = 'sw02'
down_revision: Union[str, Sequence[str], None] = ('sw01', 'e12a0002')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Merge heads — no schema changes."""
    pass


def downgrade() -> None:
    """Downgrade — no schema changes."""
    pass
