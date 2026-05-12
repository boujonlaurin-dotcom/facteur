"""Create user_notification_preferences table.

Revision ID: np01
Revises: ssq02
Create Date: 2026-04-28

"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "np01"
down_revision: Union[str, Sequence[str]] = "ssq02_host_feed_cache"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "user_notification_preferences",
        sa.Column(
            "user_id",
            sa.dialects.postgresql.UUID(as_uuid=True),
            sa.ForeignKey("user_profiles.user_id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column(
            "push_enabled",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("false"),
        ),
        sa.Column(
            "preset",
            sa.Text(),
            nullable=False,
            server_default=sa.text("'minimaliste'"),
        ),
        sa.Column(
            "time_slot",
            sa.Text(),
            nullable=False,
            server_default=sa.text("'morning'"),
        ),
        sa.Column(
            "timezone",
            sa.Text(),
            nullable=False,
            server_default=sa.text("'Europe/Paris'"),
        ),
        sa.Column(
            "refusal_count",
            sa.Integer(),
            nullable=False,
            server_default=sa.text("0"),
        ),
        sa.Column("last_refusal_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("last_renudge_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "renudge_shown_count",
            sa.Integer(),
            nullable=False,
            server_default=sa.text("0"),
        ),
        sa.Column(
            "modal_seen",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("false"),
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
        sa.CheckConstraint(
            "preset IN ('minimaliste', 'curieux')",
            name="user_notif_prefs_preset_check",
        ),
        sa.CheckConstraint(
            "time_slot IN ('morning', 'evening')",
            name="user_notif_prefs_time_slot_check",
        ),
    )


def downgrade() -> None:
    op.drop_table("user_notification_preferences")
