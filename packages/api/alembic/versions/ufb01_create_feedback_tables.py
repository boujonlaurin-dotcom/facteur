"""Crée les tables du système de feedback utilisateur (Epic 13, story 13.1).

Migration **additive** : deux nouvelles tables, aucune modification de
l'existant. Non destructif, rollback trivial (`drop_table`).

- `digest_sentiments` : micro-feedback emoji (😴/🙂/🔥) capté en fin de Tournée
  du jour, une réponse par (user, jour), upsert.
- `feedback_invites` : état de l'invitation au call qualitatif (pilote
  l'affichage segmenté/unique de la carte côté mobile).

S'applique automatiquement au démarrage de chaque conteneur Railway via
`alembic upgrade head` (Dockerfile) — aucune action SQL manuelle.

Head précédent : au02_api_usage_tokens (head courant de main). Après : 1 seul
head (ufb01).
"""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "ufb01"
down_revision: str | None = "au02_api_usage_tokens"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    op.create_table(
        "digest_sentiments",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("digest_date", sa.Date(), nullable=False),
        sa.Column("sentiment", sa.String(length=10), nullable=False),
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
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "user_id", "digest_date", name="uq_digest_sentiments_user_date"
        ),
    )
    op.create_index(
        "ix_digest_sentiments_user_id", "digest_sentiments", ["user_id"]
    )
    op.create_index(
        "ix_digest_sentiments_digest_date", "digest_sentiments", ["digest_date"]
    )

    op.create_table(
        "feedback_invites",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column(
            "status",
            sa.String(length=20),
            server_default="pending",
            nullable=False,
        ),
        sa.Column("segment", sa.String(length=20), nullable=True),
        sa.Column(
            "shown_count",
            sa.Integer(),
            server_default="0",
            nullable=False,
        ),
        sa.Column("last_shown_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("snoozed_until", sa.DateTime(timezone=True), nullable=True),
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
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", name="uq_feedback_invites_user"),
    )


def downgrade() -> None:
    op.drop_table("feedback_invites")
    op.drop_index("ix_digest_sentiments_digest_date", table_name="digest_sentiments")
    op.drop_index("ix_digest_sentiments_user_id", table_name="digest_sentiments")
    op.drop_table("digest_sentiments")
