"""essentiel_letters — lettre du jour de l'Essentiel (Story 9.6)

Table additive, backend-only (servie via l'API) : RLS deny-all comme les
tables `sec02`. Idempotente : no-op si la table existe déjà (les deux
backends staging/prod rejouent `upgrade head` au boot).

Revision ID: el01_essentiel_letters
Revises: me01_media_eval_tables
Create Date: 2026-07-13
"""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "el01_essentiel_letters"
down_revision: str | None = "me01_media_eval_tables"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    bind = op.get_bind()
    if sa.inspect(bind).has_table("essentiel_letters"):
        return

    op.create_table(
        "essentiel_letters",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("target_date", sa.Date(), nullable=False),
        sa.Column(
            "is_serene",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("false"),
        ),
        sa.Column("letter", postgresql.JSONB(), nullable=False),
        sa.Column(
            "articles",
            postgresql.JSONB(),
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
        sa.Column("model", sa.String(length=60), nullable=True),
        sa.Column(
            "generated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
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
            "user_id",
            "target_date",
            "is_serene",
            name="uq_essentiel_letters_user_date_serene",
        ),
    )
    op.create_index(
        "ix_essentiel_letters_target_date", "essentiel_letters", ["target_date"]
    )

    # RLS deny-all : table backend-only, jamais lue directement par le client
    # Supabase (pattern sec02).
    op.execute("ALTER TABLE essentiel_letters ENABLE ROW LEVEL SECURITY")
    op.execute("REVOKE ALL ON TABLE essentiel_letters FROM anon, authenticated")


def downgrade() -> None:
    op.drop_index("ix_essentiel_letters_target_date", table_name="essentiel_letters")
    op.drop_table("essentiel_letters")
