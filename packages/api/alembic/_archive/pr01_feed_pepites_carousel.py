"""feed pepites carousel (Story 13.2)

Revision ID: pr01
Revises: np01
Create Date: 2026-04-21

Adds:
- sources.is_pepite_recommendation (bool, indexed) — flag de curation manuelle
- sources.pepite_for_themes (text[]) — thèmes associés pour priorisation
- user_personalization.pepite_carousel_dismissed_at (timestamptz) — cool-down dismiss
- user_personalization.pepite_carousel_last_shown_at (timestamptz) — rate-limit 1/jour
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "pr01"
down_revision: str = "np01"
branch_labels: Sequence[str] | None = None
depends_on: str | None = None


def upgrade() -> None:
    op.add_column(
        "sources",
        sa.Column(
            "is_pepite_recommendation",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("false"),
        ),
    )
    op.add_column(
        "sources",
        sa.Column("pepite_for_themes", sa.ARRAY(sa.Text()), nullable=True),
    )
    op.create_index(
        "ix_sources_is_pepite_recommendation",
        "sources",
        ["is_pepite_recommendation"],
    )

    op.add_column(
        "user_personalization",
        sa.Column(
            "pepite_carousel_dismissed_at",
            sa.DateTime(timezone=True),
            nullable=True,
        ),
    )
    op.add_column(
        "user_personalization",
        sa.Column(
            "pepite_carousel_last_shown_at",
            sa.DateTime(timezone=True),
            nullable=True,
        ),
    )


def downgrade() -> None:
    op.drop_column("user_personalization", "pepite_carousel_last_shown_at")
    op.drop_column("user_personalization", "pepite_carousel_dismissed_at")
    op.drop_index("ix_sources_is_pepite_recommendation", table_name="sources")
    op.drop_column("sources", "pepite_for_themes")
    op.drop_column("sources", "is_pepite_recommendation")
