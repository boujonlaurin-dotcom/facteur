from datetime import datetime
from uuid import UUID

import structlog
from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.sql import func
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
            "is_liked": user_status.is_liked if user_status else False,
            "is_hidden": user_status.is_hidden if user_status else False,
            "hidden_reason": user_status.hidden_reason if user_status else None,
            "time_spent_seconds": user_status.time_spent_seconds if user_status else 0,
            "note_text": user_status.note_text if user_status else None,
            "note_updated_at": user_status.note_updated_at if user_status else None,
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

    async def _adjust_subtopic_weights(
        self, user_id: UUID, content_id: UUID, delta: float
    ) -> None:
        """
        Ajuste les poids des sous-thèmes utilisateur en fonction d'un signal explicite.
        Réutilisé par like (+0.15) et bookmark (+0.05).
        """
        from app.models.content import Content
        from app.models.user import UserSubtopic
        from sqlalchemy.orm import selectinload

        content = await self.session.get(
            Content,
            content_id,
            options=[selectinload(Content.source)],
        )

        if not content or not content.topics:
            return

        for topic_slug in content.topics:
            stmt = select(UserSubtopic).where(
                UserSubtopic.user_id == user_id,
                UserSubtopic.topic_slug == topic_slug,
            )
            subtopic = await self.session.scalar(stmt)

            if subtopic:
                new_weight = subtopic.weight + delta
                subtopic.weight = max(0.1, min(new_weight, 3.0))
            elif delta > 0:
                new_subtopic = UserSubtopic(
                    user_id=user_id,
                    topic_slug=topic_slug,
                    weight=1.0 + delta,
                )
                self.session.add(new_subtopic)

        # Also adjust interest weight for source theme
        if content.source and content.source.theme:
            from app.models.user import UserInterest
            from app.services.recommendation.scoring_config import ScoringWeights

            theme_slug = content.source.theme
            stmt = select(UserInterest).where(
                UserInterest.user_id == user_id,
                UserInterest.interest_slug == theme_slug,
            )
            interest = await self.session.scalar(stmt)
            learning_rate = ScoringWeights.LIKE_INTEREST_RATE

            if interest:
                new_weight = interest.weight + (learning_rate * (1.0 if delta > 0 else -1.0))
                interest.weight = max(0.1, min(new_weight, 3.0))
            elif delta > 0:
                new_interest = UserInterest(
                    user_id=user_id,
                    interest_slug=theme_slug,
                    weight=1.0 + learning_rate,
                )
                self.session.add(new_interest)

    async def set_like_status(
        self, user_id: UUID, content_id: UUID, is_liked: bool
    ) -> UserContentStatus:
        """Met à jour l'état de like d'un contenu."""
        from app.services.recommendation.scoring_config import ScoringWeights

        now = datetime.utcnow()

        values: dict = {
            "user_id": user_id,
            "content_id": content_id,
            "is_liked": is_liked,
            "updated_at": now,
        }

        if is_liked:
            values["liked_at"] = now

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
        status = result.one()

        # Adjust subtopic weights
        delta = ScoringWeights.LIKE_TOPIC_BOOST if is_liked else -ScoringWeights.LIKE_TOPIC_BOOST
        await self._adjust_subtopic_weights(user_id, content_id, delta)

        return status

    async def set_save_status(
        self, user_id: UUID, content_id: UUID, is_saved: bool
    ) -> UserContentStatus:
        """Met à jour l'état de sauvegarde d'un contenu."""
        from app.services.recommendation.scoring_config import ScoringWeights

        now = datetime.utcnow()

        values: dict = {
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
        status = result.one()

        # Reinforce subtopic weights on bookmark
        if is_saved:
            await self._adjust_subtopic_weights(
                user_id, content_id, ScoringWeights.BOOKMARK_TOPIC_BOOST
            )

        return status

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

    async def upsert_note(
        self, user_id: UUID, content_id: UUID, note_text: str
    ) -> UserContentStatus:
        """Crée ou met à jour une note sur un article. Auto-sauvegarde l'article."""
        from app.services.recommendation.scoring_config import ScoringWeights

        # Check article is not hidden
        existing = await self.session.scalar(
            select(UserContentStatus).where(
                UserContentStatus.user_id == user_id,
                UserContentStatus.content_id == content_id,
            )
        )
        if existing and existing.is_hidden:
            raise ValueError("Cannot add note to hidden article")

        now = datetime.utcnow()

        values: dict = {
            "user_id": user_id,
            "content_id": content_id,
            "note_text": note_text,
            "note_updated_at": now,
            "is_saved": True,
            "saved_at": now,
            "updated_at": now,
        }

        stmt = (
            insert(UserContentStatus)
            .values(**values)
            .on_conflict_do_update(
                index_elements=["user_id", "content_id"],
                set_={
                    "note_text": note_text,
                    "note_updated_at": now,
                    "is_saved": True,
                    "saved_at": func.coalesce(
                        UserContentStatus.saved_at, now
                    ),
                    "updated_at": now,
                },
            )
            .returning(UserContentStatus)
        )

        result = await self.session.scalars(stmt)
        status = result.one()

        # Reinforce subtopic weights (same as bookmark)
        await self._adjust_subtopic_weights(
            user_id, content_id, ScoringWeights.BOOKMARK_TOPIC_BOOST
        )

        return status

    async def delete_note(
        self, user_id: UUID, content_id: UUID
    ) -> UserContentStatus | None:
        """Supprime la note d'un article. L'article reste sauvegardé."""
        now = datetime.utcnow()

        stmt = (
            select(UserContentStatus)
            .where(
                UserContentStatus.user_id == user_id,
                UserContentStatus.content_id == content_id,
            )
        )
        status = await self.session.scalar(stmt)

        if not status:
            return None

        status.note_text = None
        status.note_updated_at = None
        status.updated_at = now

        return status
