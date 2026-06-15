"""create event_rsvps table

Revision ID: b75132e0c6b5
Revises: gr02_grille_featured_article
Create Date: 2026-06-11 17:48:04

Table dédiée au RSVP événement (Story 25.1). Distincte de la waitlist pour
capturer chaque participant, y compris les emails déjà inscrits (que la
waitlist dédoublonne et ignore). Unicité (event_slug, email) → RSVP idempotent.

NB: l'autogenerate révèle un drift préexistant entre le baseline et les modèles
(index/NOT NULL/types sur d'autres tables). Ce drift est volontairement hors
périmètre de cette migration, qui ne crée QUE la table event_rsvps.
"""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "b75132e0c6b5"
down_revision: str | None = "gr02_grille_featured_article"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    op.create_table(
        "event_rsvps",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("event_slug", sa.String(length=100), nullable=False),
        sa.Column("email", sa.String(length=255), nullable=False),
        sa.Column("utm_source", sa.String(length=100), nullable=True),
        sa.Column("utm_medium", sa.String(length=100), nullable=True),
        sa.Column("utm_campaign", sa.String(length=100), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("event_slug", "email", name="uq_event_rsvps_event_email"),
    )


def downgrade() -> None:
    op.drop_table("event_rsvps")
