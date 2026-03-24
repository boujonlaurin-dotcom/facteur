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
    ) -> bool:
        """Register email. Returns True if new, False if already exists."""
        entry = WaitlistEntry(
            email=email.lower().strip(),
            source=source,
            utm_source=utm_source,
            utm_medium=utm_medium,
            utm_campaign=utm_campaign,
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
            )
            return True
        except IntegrityError:
            await self.db.rollback()
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
