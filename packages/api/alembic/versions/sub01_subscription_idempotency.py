"""subscription webhook idempotency — last_event_id on user_subscriptions.

Stores the last RevenueCat webhook event_id processed for each subscription.
Used by the webhook handler to skip duplicate events (RevenueCat retries
non-2xx responses, so the same event can arrive multiple times).
"""

import sqlalchemy as sa

from alembic import op

revision: str = "sub01_subscription_idempotency"
down_revision: str | None = "lg02_source_language_user_pref"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    op.add_column(
        "user_subscriptions",
        sa.Column("last_event_id", sa.String(length=100), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("user_subscriptions", "last_event_id")
