"""supporter messages — mot laissé par un soutien (mur public, modéré).

Table neuve, purement additive (expand-contract, DB partagée staging/prod). Le
message est saisi sur `/soutenir`, transporté via les métadonnées Stripe, puis
persisté ici au webhook `checkout.session.completed` (donc seulement pour un
paiement réellement engagé). `published=false` par défaut : rien n'apparaît
publiquement sans modération explicite.
"""

import sqlalchemy as sa

from alembic import op

revision: str = "st02_supporter_messages"
down_revision: str | None = "st01_stripe_support"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    op.create_table(
        "supporter_messages",
        sa.Column("id", sa.dialects.postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "user_id", sa.dialects.postgresql.UUID(as_uuid=True), nullable=True
        ),
        sa.Column("message", sa.Text(), nullable=False),
        sa.Column("display_name", sa.String(length=120), nullable=True),
        sa.Column("stripe_session_id", sa.String(length=255), nullable=True),
        sa.Column(
            "published",
            sa.Boolean(),
            server_default=sa.text("false"),
            nullable=False,
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )
    op.create_index(
        "ix_supporter_messages_user_id", "supporter_messages", ["user_id"]
    )
    # Index partiel : le mur public ne lit que les messages publiés, récents d'abord.
    op.create_index(
        "ix_supporter_messages_published_created",
        "supporter_messages",
        ["created_at"],
        postgresql_where=sa.text("published"),
    )


def downgrade() -> None:
    op.drop_index(
        "ix_supporter_messages_published_created", table_name="supporter_messages"
    )
    op.drop_index("ix_supporter_messages_user_id", table_name="supporter_messages")
    op.drop_table("supporter_messages")
