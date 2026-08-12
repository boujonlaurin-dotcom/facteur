"""Suivi fiable des emails de lien de soutien via Resend."""

import sqlalchemy as sa

from alembic import op

revision: str = "su03_support_link_delivery"
down_revision: str | None = "tr02_widen_triage_via"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    op.create_table(
        "support_link_deliveries",
        sa.Column("id", sa.dialects.postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", sa.dialects.postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("recipient_email", sa.String(length=320), nullable=False),
        sa.Column("status", sa.String(length=32), nullable=False),
        sa.Column("attempts", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("auto_retry_used", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("next_retry_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("error_code", sa.String(length=100), nullable=True),
        sa.Column("last_provider_event_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_support_link_deliveries_user_id", "support_link_deliveries", ["user_id"])
    op.create_index("ix_support_link_deliveries_retry", "support_link_deliveries", ["next_retry_at"])
    op.create_table(
        "support_link_delivery_attempts",
        sa.Column("id", sa.dialects.postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("delivery_id", sa.dialects.postgresql.UUID(as_uuid=True), sa.ForeignKey("support_link_deliveries.id", ondelete="CASCADE"), nullable=False),
        sa.Column("attempt_number", sa.Integer(), nullable=False),
        sa.Column("provider_message_id", sa.String(length=255), nullable=False, unique=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_support_link_delivery_attempts_delivery_id", "support_link_delivery_attempts", ["delivery_id"])
    op.create_table(
        "resend_webhook_events",
        sa.Column("svix_id", sa.String(length=255), primary_key=True),
        sa.Column("event_type", sa.String(length=100), nullable=False),
        sa.Column("received_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )


def downgrade() -> None:
    op.drop_table("resend_webhook_events")
    op.drop_index("ix_support_link_delivery_attempts_delivery_id", table_name="support_link_delivery_attempts")
    op.drop_table("support_link_delivery_attempts")
    op.drop_index("ix_support_link_deliveries_retry", table_name="support_link_deliveries")
    op.drop_index("ix_support_link_deliveries_user_id", table_name="support_link_deliveries")
    op.drop_table("support_link_deliveries")
