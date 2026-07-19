"""Service waitlist — inscription email depuis la landing page."""

import structlog
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.waitlist import WaitlistEntry
from app.models.waitlist_survey import WaitlistSurveyResponse

logger = structlog.get_logger()


class WaitlistService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def get_count(self) -> int:
        """Return total number of waitlist entries."""
        result = await self.db.execute(select(func.count()).select_from(WaitlistEntry))
        return result.scalar_one()

    async def register(
        self,
        email: str,
        source: str = "landing",
        utm_source: str | None = None,
        utm_medium: str | None = None,
        utm_campaign: str | None = None,
        motivation: str | None = None,
        methode_complete: bool | None = None,
    ) -> bool:
        """Register email. Returns True if new, False if already exists.

        Sur doublon, si des champs « comité de revue » sont fournis, ils sont
        mis à jour sur la ligne existante : un inscrit waitlist peut rejoindre
        le comité plus tard sans créer de doublon.
        """
        normalized = email.lower().strip()
        entry = WaitlistEntry(
            email=normalized,
            source=source,
            utm_source=utm_source,
            utm_medium=utm_medium,
            utm_campaign=utm_campaign,
            motivation=motivation,
            methode_complete=methode_complete,
        )
        try:
            self.db.add(entry)
            await self.db.commit()
            logger.info(
                "waitlist_registered",
                email=email,
                source=source,
                utm_source=utm_source,
                utm_medium=utm_medium,
                utm_campaign=utm_campaign,
                methode_complete=methode_complete,
            )
            return True
        except IntegrityError:
            await self.db.rollback()
            if motivation is not None or methode_complete:
                result = await self.db.execute(
                    select(WaitlistEntry).where(WaitlistEntry.email == normalized)
                )
                existing = result.scalar_one_or_none()
                if existing:
                    if motivation is not None:
                        existing.motivation = motivation
                    if methode_complete:
                        existing.methode_complete = True
                    await self.db.commit()
                    logger.info(
                        "waitlist_comite_updated",
                        email=email,
                        methode_complete=methode_complete,
                    )
            logger.info("waitlist_duplicate", email=email)
            return False

    async def submit_survey(
        self,
        email: str,
        info_source: str,
        main_pain: str,
        willingness: str,
    ) -> bool:
        """Store survey responses. Returns True if saved, False if entry not found."""
        normalized = email.lower().strip()
        result = await self.db.execute(
            select(WaitlistEntry).where(WaitlistEntry.email == normalized)
        )
        entry = result.scalar_one_or_none()
        if not entry:
            logger.warning("survey_no_entry", email=email)
            return False

        survey = WaitlistSurveyResponse(
            waitlist_entry_id=entry.id,
            info_source=info_source,
            main_pain=main_pain,
            willingness=willingness,
        )
        self.db.add(survey)
        await self.db.commit()
        logger.info(
            "survey_submitted",
            email=email,
            info_source=info_source,
            main_pain=main_pain,
            willingness=willingness,
        )
        return True
