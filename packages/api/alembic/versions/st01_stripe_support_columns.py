"""stripe support (prix libre) — additive columns + stripe_events idempotency.

Fondations du parcours « Soutien à prix libre » (Stripe direct + grant
RevenueCat promotionnel). Purement ADDITIF / nullable : `main` (staging) et
`production` (prod) partagent la DB Supabase de prod, donc cette migration doit
pouvoir tourner sous l'ancien code prod sans rien casser (expand-contract).

- `user_subscriptions` : 4 colonnes nullables décrivant le miroir Stripe.
  `provider` reste NULL pour l'existant (RevenueCat historique) ; la nouvelle
  chaîne écrit `'stripe'`.
- `stripe_events` : table d'idempotence globale des webhooks Stripe (INSERT
  ... ON CONFLICT DO NOTHING avant traitement).
"""

import sqlalchemy as sa

from alembic import op

revision: str = "st01_stripe_support"
down_revision: str | None = "sa02_alerts_v2"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    op.add_column(
        "user_subscriptions",
        sa.Column("stripe_customer_id", sa.String(length=255), nullable=True),
    )
    op.add_column(
        "user_subscriptions",
        sa.Column("stripe_subscription_id", sa.String(length=255), nullable=True),
    )
    op.add_column(
        "user_subscriptions",
        sa.Column("support_amount_cents", sa.Integer(), nullable=True),
    )
    op.add_column(
        "user_subscriptions",
        sa.Column("provider", sa.String(length=20), nullable=True),
    )
    op.create_index(
        "ix_user_subscriptions_stripe_subscription_id",
        "user_subscriptions",
        ["stripe_subscription_id"],
    )
    op.create_index(
        "ix_user_subscriptions_stripe_customer_id",
        "user_subscriptions",
        ["stripe_customer_id"],
    )

    op.create_table(
        "stripe_events",
        sa.Column("event_id", sa.String(length=255), primary_key=True),
        sa.Column("event_type", sa.String(length=100), nullable=True),
        sa.Column(
            "received_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )


def downgrade() -> None:
    op.drop_table("stripe_events")
    op.drop_index(
        "ix_user_subscriptions_stripe_customer_id",
        table_name="user_subscriptions",
    )
    op.drop_index(
        "ix_user_subscriptions_stripe_subscription_id",
        table_name="user_subscriptions",
    )
    op.drop_column("user_subscriptions", "provider")
    op.drop_column("user_subscriptions", "support_amount_cents")
    op.drop_column("user_subscriptions", "stripe_subscription_id")
    op.drop_column("user_subscriptions", "stripe_customer_id")
