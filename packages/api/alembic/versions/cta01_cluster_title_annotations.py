"""create cluster_title_annotations cache table

Story 7.4 — diff highlighting backend (Sprint 1, phase déterministe).
Lazy cache of spaCy strong_tokens per (cluster_id, content_id), populated on
the first /perspectives panel open and read back by subsequent users opening
the same cluster.
"""

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.dialects.postgresql import UUID as PGUUID

from alembic import op

revision: str = "cta01_cluster_title_annotations"
down_revision: str | None = "ad01_add_is_ad_to_contents"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    op.create_table(
        "cluster_title_annotations",
        sa.Column("cluster_id", PGUUID(as_uuid=True), nullable=False),
        sa.Column("content_id", PGUUID(as_uuid=True), nullable=False),
        sa.Column("strong_tokens", JSONB, nullable=False),
        sa.Column("semantic_equiv", JSONB, nullable=True),
        sa.Column("model_version", sa.String(length=32), nullable=False),
        sa.Column(
            "computed_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        sa.ForeignKeyConstraint(
            ["content_id"], ["contents.id"], ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("cluster_id", "content_id"),
    )
    op.create_index(
        "ix_cta_cluster_id",
        "cluster_title_annotations",
        ["cluster_id"],
    )


def downgrade() -> None:
    op.drop_index("ix_cta_cluster_id", table_name="cluster_title_annotations")
    op.drop_table("cluster_title_annotations")
