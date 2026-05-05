"""merge ht01 and pa01 heads

Revision ID: mg03
Revises: ht01, pa01
Create Date: 2026-04-08

"""
from typing import Sequence, Union

# revision identifiers, used by Alembic.
revision: str = "mg03"
down_revision: tuple[str, str] = ("ht01", "pa01")
branch_labels: Sequence[str] | None = None
depends_on: str | None = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
