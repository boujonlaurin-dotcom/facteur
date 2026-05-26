"""drop daily_top3 table (post-unification cleanup)

Le job `daily_top3` (8h00 Paris) et le modèle `DailyTop3` ont été supprimés
lors du cleanup post-unification du flux (PR cleanup-legacy-feed-mistral).
Le briefing Top 3 a été remplacé en pratique par le `/api/digest` qui sert
maintenant tous les usages mobile (FluxContinu / Tournée du jour).

Cette migration drop la table `daily_top3` (et ses index/contraintes
associés). Pas de backfill — les rows sont obsolètes.
"""

import sqlalchemy as sa

from alembic import op

revision: str = "cl01_drop_daily_top3"
down_revision: str | None = "sub01_subscription_idempotency"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    op.drop_table("daily_top3")


def downgrade() -> None:
    # Recrée la table dans son dernier état connu — on n'a aucune donnée à
    # restaurer, c'est juste pour permettre un rollback DDL si nécessaire.
    op.create_table(
        "daily_top3",
        sa.Column("id", sa.dialects.postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "user_id",
            sa.dialects.postgresql.UUID(as_uuid=True),
            nullable=False,
            index=True,
        ),
        sa.Column(
            "content_id",
            sa.dialects.postgresql.UUID(as_uuid=True),
            sa.ForeignKey("contents.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("rank", sa.Integer(), nullable=False),
        sa.Column("top3_reason", sa.String(length=100), nullable=False),
        sa.Column(
            "consumed",
            sa.Boolean(),
            nullable=False,
            server_default=sa.false(),
        ),
        sa.Column(
            "generated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        sa.CheckConstraint("rank >= 1 AND rank <= 3", name="ck_daily_top3_rank_range"),
    )
    op.create_index("ix_daily_top3_user_date", "daily_top3", ["user_id", "generated_at"])
    op.create_index(
        "uq_daily_top3_user_rank_day",
        "daily_top3",
        ["user_id", "rank", sa.text("date(generated_at AT TIME ZONE 'UTC')")],
        unique=True,
    )
