"""api_usage_events — log append-only des appels API externes (Mistral / Brave)

Migration **additive** (enabler observabilité scaling, WP-E). Crée la table
`api_usage_events` (1 ligne par appel API externe) + 2 index. Aucune contrainte
d'unicité → pas de hot-row contention. Non destructif, rollback trivial
(`drop_table`).

Head précédent : gr02_grille_featured_article. Après : 1 seul head (au01).
"""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "au01_api_usage_events"
down_revision: str | None = "gr02_grille_featured_article"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    op.create_table(
        "api_usage_events",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("provider", sa.String(length=16), nullable=False),
        sa.Column("model", sa.String(length=48), nullable=True),
        sa.Column("call_site", sa.String(length=48), nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("latency_ms", sa.Integer(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_api_usage_events_created_at",
        "api_usage_events",
        ["created_at"],
    )
    op.create_index(
        "ix_api_usage_events_provider_created",
        "api_usage_events",
        ["provider", "created_at"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_api_usage_events_provider_created", table_name="api_usage_events"
    )
    op.drop_index("ix_api_usage_events_created_at", table_name="api_usage_events")
    op.drop_table("api_usage_events")
