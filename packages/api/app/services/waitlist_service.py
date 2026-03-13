"""Service waitlist — inscription email depuis la landing page."""

import structlog
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.waitlist import WaitlistEntry

logger = structlog.get_logger()


class WaitlistService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def register(self, email: str, source: str = "landing") -> bool:
        """Register email. Returns True if new, False if already exists."""
        entry = WaitlistEntry(email=email.lower().strip(), source=source)
        try:
            self.db.add(entry)
            await self.db.commit()
            logger.info("waitlist_registered", email=email, source=source)
            return True
        except IntegrityError:
            await self.db.rollback()
            logger.info("waitlist_duplicate", email=email)
            return False
