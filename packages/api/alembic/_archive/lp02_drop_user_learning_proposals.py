"""drop user_learning_proposals

Revision ID: lp02
Revises: sr01_add_serein_exclusion
Create Date: 2026-04-24

Sprint 2 PR1 — Learning Checkpoint (Epic 13) feature is dead:
 - 0 UI mobile (verified: no `learning_proposal*` imports in apps/mobile/lib).
 - 0 rows produced in prod for weeks.

The sibling table `user_entity_preferences` (created in ln01) stays — it
is actively used by `recommendation_service.py` for muting entities.
"""

from alembic import op
import sqlalchemy as sa

# revision identifiers
revision = "lp02"
down_revision = "sr01_add_serein_exclusion"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.drop_index(
        "idx_learning_proposals_user_pending",
        table_name="user_learning_proposals",
    )
    op.drop_table("user_learning_proposals")


def downgrade() -> None:
    from sqlalchemy.dialects import postgresql

    op.create_table(
        "user_learning_proposals",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("proposal_type", sa.String(30), nullable=False),
        sa.Column("entity_type", sa.String(20), nullable=False),
        sa.Column("entity_id", sa.Text(), nullable=False),
        sa.Column("entity_label", sa.Text(), nullable=False),
        sa.Column("current_value", sa.Text(), nullable=True),
        sa.Column("proposed_value", sa.Text(), nullable=False),
        sa.Column("signal_strength", sa.Float(), nullable=False),
        sa.Column("signal_context", postgresql.JSONB(), nullable=False),
        sa.Column(
            "shown_count", sa.Integer(), server_default="0", nullable=False
        ),
        sa.Column(
            "status", sa.String(20), server_default="pending", nullable=False
        ),
        sa.Column("user_chosen_value", sa.Text(), nullable=True),
        sa.Column(
            "computed_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column("shown_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("resolved_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
    )
    op.create_index(
        "idx_learning_proposals_user_pending",
        "user_learning_proposals",
        ["user_id", "status"],
        postgresql_where=sa.text("status = 'pending'"),
    )
