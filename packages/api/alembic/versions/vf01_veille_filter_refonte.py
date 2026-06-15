"""Veille refonte (Story 23.1) : drop scheduling, drop deliveries, add keywords.

PR-2/4 de la bascule vers un filtre temps-réel sur le feed :
- DROP TABLE veille_deliveries (l'historique est sacrifié — décision PO Q2)
- ALTER veille_configs DROP colonnes scheduling (frequency, day_of_week,
  delivery_hour, timezone, last_delivered_at, next_scheduled_at) + drop
  purpose_other (consolidé dans purpose via UI)
- CREATE TABLE veille_keywords (max 20/config, normalisé lowercase côté API)

Le downgrade restaure le schéma mais PAS les données (deliveries perdues,
configs voient leur scheduling repeupler avec des défauts génériques).

Revision ID: vf01_veille_filter_refonte
Revises: 22a2_drop_favorite_position_cap
Create Date: 2026-05-19

"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "vf01_veille_filter_refonte"
down_revision: str | None = "22a2_drop_favorite_position_cap"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    op.drop_index("ix_veille_deliveries_state", table_name="veille_deliveries")
    op.drop_index("ix_veille_deliveries_target_date", table_name="veille_deliveries")
    op.drop_table("veille_deliveries")

    op.drop_index(
        "ix_veille_configs_next_scheduled", table_name="veille_configs"
    )
    op.drop_column("veille_configs", "next_scheduled_at")
    op.drop_column("veille_configs", "last_delivered_at")
    op.drop_column("veille_configs", "timezone")
    op.drop_column("veille_configs", "delivery_hour")
    op.drop_column("veille_configs", "day_of_week")
    op.drop_column("veille_configs", "frequency")
    op.drop_column("veille_configs", "purpose_other")

    op.create_table(
        "veille_keywords",
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
        sa.Column("keyword", sa.String(80), nullable=False),
        sa.Column("position", sa.Integer, nullable=False, server_default="0"),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.UniqueConstraint(
            "veille_config_id", "keyword", name="uq_veille_keywords"
        ),
    )
    op.create_index(
        "ix_veille_keywords_config", "veille_keywords", ["veille_config_id"]
    )


def downgrade() -> None:
    op.drop_index("ix_veille_keywords_config", table_name="veille_keywords")
    op.drop_table("veille_keywords")

    op.add_column(
        "veille_configs",
        sa.Column("purpose_other", sa.Text, nullable=True),
    )
    op.add_column(
        "veille_configs",
        sa.Column(
            "frequency",
            sa.String(20),
            nullable=False,
            server_default=sa.text("'weekly'"),
        ),
    )
    op.add_column(
        "veille_configs",
        sa.Column("day_of_week", sa.SmallInteger, nullable=True),
    )
    op.add_column(
        "veille_configs",
        sa.Column(
            "delivery_hour",
            sa.SmallInteger,
            nullable=False,
            server_default=sa.text("7"),
        ),
    )
    op.add_column(
        "veille_configs",
        sa.Column(
            "timezone",
            sa.Text,
            nullable=False,
            server_default=sa.text("'Europe/Paris'"),
        ),
    )
    op.add_column(
        "veille_configs",
        sa.Column(
            "last_delivered_at",
            sa.DateTime(timezone=True),
            nullable=True,
        ),
    )
    op.add_column(
        "veille_configs",
        sa.Column(
            "next_scheduled_at",
            sa.DateTime(timezone=True),
            nullable=True,
        ),
    )
    op.create_index(
        "ix_veille_configs_next_scheduled",
        "veille_configs",
        ["next_scheduled_at"],
        postgresql_where=sa.text("status = 'active'"),
    )

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
        sa.Column("target_date", sa.Date, nullable=False),
        sa.Column(
            "items",
            postgresql.JSONB,
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
        sa.Column(
            "generation_state",
            sa.String(20),
            nullable=False,
            server_default=sa.text("'pending'"),
        ),
        sa.Column(
            "attempts",
            sa.SmallInteger,
            nullable=False,
            server_default=sa.text("0"),
        ),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("finished_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("last_error", sa.Text, nullable=True),
        sa.Column(
            "version",
            sa.SmallInteger,
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
        "ix_veille_deliveries_target_date", "veille_deliveries", ["target_date"]
    )
    op.create_index(
        "ix_veille_deliveries_state", "veille_deliveries", ["generation_state"]
    )
