"""drop CHECK constraints position BETWEEN 0..2 sur les tables favoris (Story 22.2).

La limite de 3 favoris devient un cap d'affichage Tournée du jour, plus une
limite dure DB. La PK composite (user_id, position) reste suffisante pour
garantir l'unicité du slot.

Revision ID: 22a2_drop_favorite_position_cap
Revises: 5de67819bc61
Create Date: 2026-05-18

"""

from alembic import op

revision: str = "22a2_drop_favorite_position_cap"
down_revision: str | None = "5de67819bc61"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    op.drop_constraint(
        "user_favorite_interests_position_range",
        "user_favorite_interests",
        type_="check",
    )
    op.drop_constraint(
        "user_favorite_sources_position_range",
        "user_favorite_sources",
        type_="check",
    )


def downgrade() -> None:
    op.create_check_constraint(
        "user_favorite_interests_position_range",
        "user_favorite_interests",
        "position BETWEEN 0 AND 2",
    )
    op.create_check_constraint(
        "user_favorite_sources_position_range",
        "user_favorite_sources",
        "position BETWEEN 0 AND 2",
    )
