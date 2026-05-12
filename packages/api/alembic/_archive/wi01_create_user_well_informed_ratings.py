"""create user_well_informed_ratings

Revision ID: wi01
Revises: lp02
Create Date: 2026-04-24

Story 14.3 — self-reported "well-informed" score (1-10).
Prompt inline dans digest (cooldown 14j/5j côté client). Table sert de
source de vérité longitudinale ; event analytics mirroré en parallèle.
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers
revision = "wi01"
down_revision = "lp02"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "user_well_informed_ratings",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            nullable=False,
        ),
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=True),
            nullable=False,
        ),
        sa.Column("score", sa.Integer(), nullable=False),
        sa.Column(
            "context",
            sa.String(length=32),
            nullable=False,
            server_default="digest_inline",
        ),
        sa.Column("device_id", sa.String(length=255), nullable=True),
        sa.Column(
            "submitted_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.CheckConstraint(
            "score >= 1 AND score <= 10",
            name="ck_well_informed_ratings_score_range",
        ),
    )
    op.create_index(
        "ix_well_informed_ratings_user_id",
        "user_well_informed_ratings",
        ["user_id"],
    )
    op.create_index(
        "ix_well_informed_ratings_submitted_at",
        "user_well_informed_ratings",
        ["submitted_at"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_well_informed_ratings_submitted_at",
        table_name="user_well_informed_ratings",
    )
    op.drop_index(
        "ix_well_informed_ratings_user_id",
        table_name="user_well_informed_ratings",
    )
    op.drop_table("user_well_informed_ratings")
