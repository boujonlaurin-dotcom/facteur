"""merge heads sr01 and fb01

Revision ID: mg02
Revises: sr01, fb01
Create Date: 2026-04-02

"""
from typing import Sequence, Union

# revision identifiers, used by Alembic.
revision: str = "mg02"
down_revision: Union[str, Sequence[str]] = ("sr01", "fb01")
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
