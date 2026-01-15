"""Service pour la gestion des analytics."""

from datetime import date, timedelta, datetime
from typing import Dict, Any
from uuid import UUID

import structlog
from sqlalchemy import select, func, text, desc
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.analytics import AnalyticsEvent

logger = structlog.get_logger()


class AnalyticsService:
    def __init__(self, session: AsyncSession):
        self.session = session

    async def log_event(
        self, 
        user_id: UUID, 
        event_type: str, 
        event_data: Dict[str, Any],
        device_id: str | None = None
    ) -> AnalyticsEvent:
        """Log un nouvel événement analytique."""
        event = AnalyticsEvent(
            user_id=user_id,
            event_type=event_type,
            event_data=event_data,
            device_id=device_id
        )
        self.session.add(event)
        # Commit automatique pour s'assurer que l'event est persisté immédiatement
        # Note: Dans une architecture à fort trafic, on utiliserait un buffer ou une queue
        await self.session.commit()
        return event

    async def get_dau(self, target_date: date = None) -> int:
        """Récupère le nombre d'utilisateurs actifs journaliers (DAU)."""
        if target_date is None:
            target_date = datetime.utcnow().date()
            
        stmt = select(func.count(func.distinct(AnalyticsEvent.user_id))).where(
            AnalyticsEvent.event_type == 'session_start',
            func.date(AnalyticsEvent.created_at) == target_date
        )
        result = await self.session.scalar(stmt)
        return result or 0

    async def get_recent_events(self, limit: int = 50) -> list[AnalyticsEvent]:
        """Récupère les derniers événements pour le dashboard."""
        stmt = select(AnalyticsEvent).order_by(desc(AnalyticsEvent.created_at)).limit(limit)
        result = await self.session.scalars(stmt)
        return list(result.all())
