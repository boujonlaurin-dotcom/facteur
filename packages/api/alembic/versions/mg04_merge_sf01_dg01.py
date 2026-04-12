"""merge sf01 (sunflower) and dg01 (digest generation state) heads

Revision ID: mg04
Revises: sf01, dg01
Create Date: 2026-04-12

"""
from typing import Sequence, Union

# revision identifiers, used by Alembic.
revision: str = "mg04"
down_revision: tuple[str, str] = ("sf01", "dg01")
branch_labels: Sequence[str] | None = None
depends_on: str | None = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
