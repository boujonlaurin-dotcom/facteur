"""merge me02 media-eval + wl01 waitlist heads

Revision ID: 181c618da382
Revises: me02_evaluations_niveau_0_4, wl01_waitlist_comite_fields
Create Date: 2026-07-18 23:19:56.424677

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '181c618da382'
down_revision: Union[str, Sequence[str], None] = ('me02_evaluations_niveau_0_4', 'wl01_waitlist_comite_fields')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    pass


def downgrade() -> None:
    """Downgrade schema."""
    pass
