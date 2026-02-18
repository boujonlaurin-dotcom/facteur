"""onboarding_v2_article_count

Data migration: weekly_goal (5/10/15) → daily article count (3/5/7)

Revision ID: 34cec6ef13a6
Revises: z1a2b3c4d5e6
Create Date: 2026-02-18 01:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '34cec6ef13a6'
down_revision: Union[str, Sequence[str], None] = 'z1a2b3c4d5e6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Data migration: weekly_goal (5/10/15) → daily article count (3/5/7)
    op.execute("UPDATE user_profiles SET weekly_goal = 3 WHERE weekly_goal = 5")
    op.execute("UPDATE user_profiles SET weekly_goal = 5 WHERE weekly_goal = 10")
    op.execute("UPDATE user_profiles SET weekly_goal = 7 WHERE weekly_goal = 15")


def downgrade() -> None:
    # Reverse: daily article count (3/5/7) → weekly_goal (5/10/15)
    op.execute("UPDATE user_profiles SET weekly_goal = 15 WHERE weekly_goal = 7")
    op.execute("UPDATE user_profiles SET weekly_goal = 10 WHERE weekly_goal = 5")
    op.execute("UPDATE user_profiles SET weekly_goal = 5 WHERE weekly_goal = 3")
