"""add daily_goal to user_profiles

Objectif journalier de lectures abouties réglable par l'utilisateur (story 30.2).
Calqué sur `weekly_goal`. Colonne **additive** `NOT NULL DEFAULT 2` : Postgres
backfille les lignes existantes via le server_default, donc pas de multi-étape
expand/contract nécessaire (aucun DROP/rename). DB partagée staging/prod :
l'ancien backend prod ignore simplement la colonne → sûr.
"""

import sqlalchemy as sa

from alembic import op

revision: str = "dg01_daily_goal_user_profiles"
down_revision: str | None = "mg04_merge_pt01_rd01"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    op.add_column(
        "user_profiles",
        sa.Column(
            "daily_goal",
            sa.Integer(),
            nullable=False,
            server_default="2",
        ),
    )


def downgrade() -> None:
    op.drop_column("user_profiles", "daily_goal")
