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

    async def get_content_detail(self, content_id: UUID, user_id: UUID):
        """Récupère les détails d'un contenu avec le statut utilisateur."""
        from app.models.content import Content
        from app.models.content import UserContentStatus
        from sqlalchemy.orm import selectinload
        
        # Query Content with source
        stmt = select(Content).options(selectinload(Content.source)).where(Content.id == content_id)
        content = await self.session.scalar(stmt)
        
        if not content:
            return None
            
        # Query UserStatus
        stmt_status = select(UserContentStatus).where(
            UserContentStatus.user_id == user_id,
            UserContentStatus.content_id == content_id
        )
        user_status = await self.session.scalar(stmt_status)
        
        # Construct response
        return {
            "id": content.id,
            "title": content.title,
            "url": content.url,
            "thumbnail_url": content.thumbnail_url,
            "description": content.description,
            "html_content": content.html_content,
            "audio_url": content.audio_url,
            "content_type": content.content_type,
            "duration_seconds": content.duration_seconds,
            "published_at": content.published_at,
            "source": content.source,
            "status": user_status.status if user_status else ContentStatus.UNSEEN,
            "is_saved": user_status.is_saved if user_status else False,
            "is_hidden": user_status.is_hidden if user_status else False,
            "hidden_reason": user_status.hidden_reason if user_status else None,
            "time_spent_seconds": user_status.time_spent_seconds if user_status else 0,
        }

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
            
            # Feedback Loop: Adjust Interest Weights based on consumption
            # Axe 3.1 du plan d'amélioration
            await self._adjust_interest_weight(
                user_id, 
                content_id, 
                update_data.time_spent_seconds
            )

        return updated_status

    async def _adjust_interest_weight(self, user_id: UUID, content_id: UUID, time_spent: int | None):
        """
        Ajuste le poids de l'intérêt associé au thème du contenu consommé.
        Learning Rate = 0.05 (progression douce).
        """
        from app.models.content import Content
        from app.models.user import UserInterest
        from sqlalchemy.orm import selectinload
        
        # 1. Fetch content to get theme and duration
        content = await self.session.get(
            Content, 
            content_id, 
            options=[selectinload(Content.source)]
        )
        
        if not content or not content.source or not content.source.theme:
            return
            
        theme_slug = content.source.theme
        
        # 2. Calculate Engagement Factor
        # Base boost just for consuming
        engagement_factor = 1.0 
        
        if time_spent and content.duration_seconds and content.duration_seconds > 0:
            ratio = time_spent / content.duration_seconds
            # Si l'utilisateur reste longtemps (> 80% du temps estimé), boost supplémentaire
            if ratio > 0.8:
                engagement_factor = 1.5
            # Si c'était très rapide (< 10%), peut-être un faux positif ? On réduit l'impact
            elif ratio < 0.1:
                engagement_factor = 0.2
                
        # 3. Update UserInterest
        # Check if interest exists
        stmt = select(UserInterest).where(
            UserInterest.user_id == user_id,
            UserInterest.interest_slug == theme_slug
        )
        interest = await self.session.scalar(stmt)
        
        learning_rate = 0.05
        
        if interest:
            # NewWeight = OldWeight + (Engagement * Rate)
            # On cap le poids max à 3.0 pour éviter l'explosion
            new_weight = interest.weight + (engagement_factor * learning_rate)
            interest.weight = min(new_weight, 3.0)
        else:
            # Create new interest with base weight 1.0 + boost
            # Cela permet de découvrir de nouveaux thèmes via sources généralistes
            new_interest = UserInterest(
                user_id=user_id,
                interest_slug=theme_slug,
                weight=1.0 + (engagement_factor * learning_rate)
            )
            self.session.add(new_interest)

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
