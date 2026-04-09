"""create digest_generation_state + editorial_highlights_history

Revision ID: dg01
Revises: td01
Create Date: 2026-04-09

Adds two tables used by the digest reliability fix:

1. `digest_generation_state` — per-user observability for the batch so we
   can answer "why is user X still on yesterday's digest?" without scanning
   logs.

2. `editorial_highlights_history` — remembers recent pépite / coup de cœur
   picks so the writer can avoid re-selecting the same article on
   consecutive days, keeping featured content fresh each morning.

Chained after `td01` (added on main via PR #373) so the alembic history
stays single-headed after merging main into this branch.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "dg01"
down_revision: str | Sequence[str] | None = "td01"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "digest_generation_state",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=True),
            nullable=False,
        ),
        sa.Column("target_date", sa.Date(), nullable=False),
        # Each (user, date) pair has TWO logical variants — pour_vous and
        # serein — tracked as distinct rows so observability queries can
        # tell the difference between "both succeeded", "only one succeeded"
        # and "both failed".
        sa.Column(
            "is_serene",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("false"),
        ),
        sa.Column(
            "status",
            sa.String(length=20),
            nullable=False,
            server_default="pending",
        ),
        sa.Column(
            "attempts",
            sa.Integer(),
            nullable=False,
            server_default="0",
        ),
        sa.Column("last_error", sa.Text(), nullable=True),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("finished_at", sa.DateTime(timezone=True), nullable=True),
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
            name="uq_digest_generation_state_user_date_variant",
        ),
    )
    op.create_index(
        "ix_digest_generation_state_target_date",
        "digest_generation_state",
        ["target_date"],
    )
    op.create_index(
        "ix_digest_generation_state_status",
        "digest_generation_state",
        ["status"],
    )

    # editorial_highlights_history — rotation memory for pépite / coup de cœur
    op.create_table(
        "editorial_highlights_history",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column("kind", sa.String(length=20), nullable=False),
        sa.Column(
            "content_id",
            postgresql.UUID(as_uuid=True),
            nullable=False,
        ),
        sa.Column("target_date", sa.Date(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
    )
    op.create_index(
        "ix_editorial_highlights_history_kind_date",
        "editorial_highlights_history",
        ["kind", "target_date"],
    )
    op.create_index(
        "ix_editorial_highlights_history_content_id",
        "editorial_highlights_history",
        ["content_id"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_editorial_highlights_history_content_id",
        table_name="editorial_highlights_history",
    )
    op.drop_index(
        "ix_editorial_highlights_history_kind_date",
        table_name="editorial_highlights_history",
    )
    op.drop_table("editorial_highlights_history")

    op.drop_index(
        "ix_digest_generation_state_status",
        table_name="digest_generation_state",
    )
    op.drop_index(
        "ix_digest_generation_state_target_date",
        table_name="digest_generation_state",
    )
    op.drop_table("digest_generation_state")
