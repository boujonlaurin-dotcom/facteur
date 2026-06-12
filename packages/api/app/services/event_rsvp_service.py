"""Service RSVP événement — confirmation de présence depuis la landing."""

import structlog
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.event_rsvp import EventRsvp

logger = structlog.get_logger()


class EventRsvpService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def get_count(self, event_slug: str = "soiree-prelancement") -> int:
        """Nombre de RSVP pour un événement."""
        result = await self.db.execute(
            select(func.count())
            .select_from(EventRsvp)
            .where(EventRsvp.event_slug == event_slug)
        )
        return result.scalar_one()

    async def register(
        self,
        email: str,
        event_slug: str = "soiree-prelancement",
        utm_source: str | None = None,
        utm_medium: str | None = None,
        utm_campaign: str | None = None,
    ) -> bool:
        """Enregistre un RSVP. Retourne True si nouveau, False si déjà présent.

        Idempotent : l'unicité `(event_slug, email)` garantit qu'un 2e RSVP du
        même email ne crée pas de doublon. Contrairement à la waitlist, cette
        table est indépendante : un email déjà inscrit à la waitlist est bien
        enregistré ici comme participant.
        """
        entry = EventRsvp(
            email=email.lower().strip(),
            event_slug=event_slug,
            utm_source=utm_source,
            utm_medium=utm_medium,
            utm_campaign=utm_campaign,
        )
        try:
            self.db.add(entry)
            await self.db.commit()
            logger.info(
                "event_rsvp_registered",
                email=email,
                event_slug=event_slug,
                utm_source=utm_source,
            )
            return True
        except IntegrityError:
            await self.db.rollback()
            logger.info("event_rsvp_duplicate", email=email, event_slug=event_slug)
            return False
