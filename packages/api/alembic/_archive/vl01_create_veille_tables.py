"""create veille tables

Revision ID: vl01
Revises: en01
Create Date: 2026-05-01

4 tables pour la feature « Ma veille » : configs (1 active par user via partial
UNIQUE WHERE status='active'), topics, sources (FK RESTRICT vers sources —
ingestion à la volée pour les niches absentes du catalogue), deliveries
(idempotent via UNIQUE (veille_config_id, target_date)).
"""

from collections.abc import Sequence

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "vl01"
down_revision: str | Sequence[str] | None = "en01"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # 1. veille_configs
    op.create_table(
        "veille_configs",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("user_profiles.user_id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("theme_id", sa.String(length=50), nullable=False),
        sa.Column("theme_label", sa.String(length=120), nullable=False),
        sa.Column("frequency", sa.String(length=20), nullable=False),
        sa.Column("day_of_week", sa.SmallInteger(), nullable=True),
        sa.Column(
            "delivery_hour",
            sa.SmallInteger(),
            nullable=False,
            server_default=sa.text("7"),
        ),
        sa.Column(
            "timezone",
            sa.Text(),
            nullable=False,
            server_default=sa.text("'Europe/Paris'"),
        ),
        sa.Column(
            "status",
            sa.String(length=20),
            nullable=False,
            server_default=sa.text("'active'"),
        ),
        sa.Column("last_delivered_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("next_scheduled_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
    )
    op.create_index(
        "ix_veille_configs_next_scheduled",
        "veille_configs",
        ["next_scheduled_at"],
        postgresql_where=sa.text("status = 'active'"),
    )
    op.create_index(
        "ix_veille_configs_user_id",
        "veille_configs",
        ["user_id"],
    )
    op.create_index(
        "uq_veille_configs_user_active",
        "veille_configs",
        ["user_id"],
        unique=True,
        postgresql_where=sa.text("status = 'active'"),
    )

    # 2. veille_topics
    op.create_table(
        "veille_topics",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column(
            "veille_config_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("veille_configs.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("topic_id", sa.String(length=80), nullable=False),
        sa.Column("label", sa.String(length=200), nullable=False),
        sa.Column("kind", sa.String(length=20), nullable=False),
        sa.Column("reason", sa.Text(), nullable=True),
        sa.Column(
            "position",
            sa.SmallInteger(),
            nullable=False,
            server_default=sa.text("0"),
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.UniqueConstraint(
            "veille_config_id",
            "topic_id",
            name="uq_veille_topics_config_topic",
        ),
    )

    # 3. veille_sources
    op.create_table(
        "veille_sources",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column(
            "veille_config_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("veille_configs.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "source_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("sources.id", ondelete="RESTRICT"),
            nullable=False,
        ),
        sa.Column("kind", sa.String(length=20), nullable=False),
        sa.Column("why", sa.Text(), nullable=True),
        sa.Column(
            "position",
            sa.SmallInteger(),
            nullable=False,
            server_default=sa.text("0"),
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.UniqueConstraint(
            "veille_config_id",
            "source_id",
            name="uq_veille_sources_config_source",
        ),
    )
    op.create_index(
        "ix_veille_sources_source_id",
        "veille_sources",
        ["source_id"],
    )

    # 4. veille_deliveries
    op.create_table(
        "veille_deliveries",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column(
            "veille_config_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("veille_configs.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("target_date", sa.Date(), nullable=False),
        sa.Column(
            "items",
            postgresql.JSONB(),
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
        sa.Column(
            "generation_state",
            sa.String(length=20),
            nullable=False,
            server_default=sa.text("'pending'"),
        ),
        sa.Column(
            "attempts",
            sa.SmallInteger(),
            nullable=False,
            server_default=sa.text("0"),
        ),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("finished_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("last_error", sa.Text(), nullable=True),
        sa.Column(
            "version",
            sa.SmallInteger(),
            nullable=False,
            server_default=sa.text("1"),
        ),
        sa.Column("generated_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.UniqueConstraint(
            "veille_config_id",
            "target_date",
            name="uq_veille_deliveries_config_target",
        ),
    )
    op.create_index(
        "ix_veille_deliveries_target_date",
        "veille_deliveries",
        ["target_date"],
    )
    op.create_index(
        "ix_veille_deliveries_state",
        "veille_deliveries",
        ["generation_state"],
    )


def downgrade() -> None:
    op.drop_index("ix_veille_deliveries_state", table_name="veille_deliveries")
    op.drop_index("ix_veille_deliveries_target_date", table_name="veille_deliveries")
    op.drop_table("veille_deliveries")

    op.drop_index("ix_veille_sources_source_id", table_name="veille_sources")
    op.drop_table("veille_sources")

    op.drop_table("veille_topics")

    op.drop_index("uq_veille_configs_user_active", table_name="veille_configs")
    op.drop_index("ix_veille_configs_user_id", table_name="veille_configs")
    op.drop_index("ix_veille_configs_next_scheduled", table_name="veille_configs")
    op.drop_table("veille_configs")
