"""Merge heads sm01 and ts01.

Revision ID: merge01
Revises: sm01, ts01
Create Date: 2026-03-19
"""

from collections.abc import Sequence

revision: str = "merge01"
down_revision: str | Sequence[str] = ("sm01", "ts01")
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
