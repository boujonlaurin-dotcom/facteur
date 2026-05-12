"""create user_learning_proposals + user_entity_preferences

Revision ID: ln01
Revises: dg01
Create Date: 2026-04-11

Epic 13 — Learning Checkpoint:
1. `user_learning_proposals` — propositions d'ajustement generees par l'algo
2. `user_entity_preferences` — preferences follow/mute sur entites nommees
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers
revision = "ln01"
down_revision = "dg01"
branch_labels = None
depends_on = None


def upgrade() -> None:
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
        sa.Column("shown_count", sa.Integer(), server_default="0", nullable=False),
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

    # Partial index for efficient lookup of pending proposals per user
    op.create_index(
        "idx_learning_proposals_user_pending",
        "user_learning_proposals",
        ["user_id", "status"],
        postgresql_where=sa.text("status = 'pending'"),
    )

    op.create_table(
        "user_entity_preferences",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("entity_canonical", sa.Text(), nullable=False),
        sa.Column("preference", sa.String(10), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.UniqueConstraint(
            "user_id",
            "entity_canonical",
            name="uq_user_entity_pref_user_entity",
        ),
    )

    # Partial index for the hot path: loading a user's muted entities during
    # feed recommendation (see recommendation_service.py). Filtering on
    # preference = 'mute' in the index avoids a seq scan / filter step once
    # users accumulate both mute and follow rows.
    op.create_index(
        "idx_entity_prefs_user_mute",
        "user_entity_preferences",
        ["user_id"],
        postgresql_where=sa.text("preference = 'mute'"),
    )

    # Secondary composite index for generic (user_id, preference) lookups
    # (e.g. settings screen listing all preferences grouped by type).
    op.create_index(
        "idx_entity_prefs_user_pref",
        "user_entity_preferences",
        ["user_id", "preference"],
    )


def downgrade() -> None:
    op.drop_index(
        "idx_entity_prefs_user_pref", table_name="user_entity_preferences"
    )
    op.drop_index(
        "idx_entity_prefs_user_mute", table_name="user_entity_preferences"
    )
    op.drop_table("user_entity_preferences")
    op.drop_index(
        "idx_learning_proposals_user_pending", table_name="user_learning_proposals"
    )
    op.drop_table("user_learning_proposals")
