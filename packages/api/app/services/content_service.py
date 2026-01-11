from datetime import datetime
from uuid import UUID

import structlog
from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.content import UserContentStatus
from app.models.enums import ContentStatus, HiddenReason
from app.models.content import UserContentStatus
from app.models.enums import ContentStatus, HiddenReason
from app.schemas.content import ContentStatusUpdate
from app.services.streak_service import StreakService

logger = structlog.get_logger()

class ContentService:
    def __init__(self, session: AsyncSession):
        self.session = session

    async def update_content_status(
        self, user_id: UUID, content_id: UUID, update_data: ContentStatusUpdate
    ) -> UserContentStatus:
        """
        Met à jour le statut d'un contenu pour un utilisateur (Lu, Vu, Sauvegardé).
        Gère l'upsert (création ou mise à jour).
        """
        now = datetime.utcnow()
        
        # Prepare data for upsert
        values = {
            "user_id": user_id,
            "content_id": content_id,
            "updated_at": now,
        }
        
        if update_data.status:
            values["status"] = update_data.status
            # If status becomes SEEN or CONSUMED, mark timestamp
            if update_data.status in [ContentStatus.SEEN, ContentStatus.CONSUMED]:
                values["seen_at"] = now
                
        if update_data.time_spent_seconds is not None:
            values["time_spent_seconds"] = update_data.time_spent_seconds

        # Upsert statement
        stmt = (
            insert(UserContentStatus)
            .values(**values)
            .on_conflict_do_update(
                index_elements=["user_id", "content_id"],
                set_=values,
            )
            .returning(UserContentStatus)
        )
        
        result = await self.session.scalars(stmt)
        updated_status = result.one()
        
        # Trigger Streak if CONSUMED
        if update_data.status == ContentStatus.CONSUMED:
            # We use str(user_id) because StreakService expects a string ID (usually) or modify StreakService to accept UUID
            # Looking at StreakService, it takes str and converts to UUID.
            streak_service = StreakService(self.session)
            await streak_service.increment_consumption(str(user_id))

        return updated_status

    async def set_save_status(
        self, user_id: UUID, content_id: UUID, is_saved: bool
    ) -> UserContentStatus:
        """Met à jour l'état de sauvegarde d'un contenu."""
        now = datetime.utcnow()
        
        values = {
            "user_id": user_id,
            "content_id": content_id,
            "is_saved": is_saved,
            "updated_at": now,
        }
        
        if is_saved:
            values["saved_at"] = now
        
        stmt = (
            insert(UserContentStatus)
            .values(**values)
            .on_conflict_do_update(
                index_elements=["user_id", "content_id"],
                set_=values,
            )
            .returning(UserContentStatus)
        )
        
        result = await self.session.scalars(stmt)
        return result.one()

    async def set_hide_status(
        self, user_id: UUID, content_id: UUID, is_hidden: bool, reason: HiddenReason = None
    ) -> UserContentStatus:
        """Met à jour l'état masqué d'un contenu."""
        now = datetime.utcnow()
        
        values = {
            "user_id": user_id,
            "content_id": content_id,
            "is_hidden": is_hidden,
            "updated_at": now,
        }

        if reason:
            values["hidden_reason"] = reason.value if hasattr(reason, 'value') else reason
        
        stmt = (
            insert(UserContentStatus)
            .values(**values)
            .on_conflict_do_update(
                index_elements=["user_id", "content_id"],
                set_=values,
            )
            .returning(UserContentStatus)
        )
        
        result = await self.session.scalars(stmt)
        return result.one()
