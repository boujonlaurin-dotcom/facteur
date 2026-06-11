"""Modèle RSVP événement (soirée de pré-lancement, etc.)."""

from datetime import UTC, datetime
from uuid import UUID, uuid4

from sqlalchemy import DateTime, String, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class EventRsvp(Base):
    """Confirmation de présence à un événement, depuis la landing.

    Table dédiée — volontairement distincte de la waitlist — pour capturer de
    façon fiable toute personne qui confirme sa présence, y compris les emails
    déjà présents dans la waitlist (que `WaitlistService.register` dédoublonne
    et ignore silencieusement). L'unicité porte sur `(event_slug, email)` : un
    RSVP est idempotent, et `event_slug` permet de réutiliser la table pour de
    futurs événements.
    """

    __tablename__ = "event_rsvps"

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid4
    )
    event_slug: Mapped[str] = mapped_column(
        String(100), nullable=False, default="soiree-prelancement"
    )
    email: Mapped[str] = mapped_column(String(255), nullable=False)
    utm_source: Mapped[str | None] = mapped_column(String(100), nullable=True)
    utm_medium: Mapped[str | None] = mapped_column(String(100), nullable=True)
    utm_campaign: Mapped[str | None] = mapped_column(String(100), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(UTC),
    )

    __table_args__ = (
        UniqueConstraint("event_slug", "email", name="uq_event_rsvps_event_email"),
    )
