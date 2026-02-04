"""Service layer for digest operations (Epic 10).

Provides business logic for:
- Retrieving or generating today's digest
- Tracking user actions (read/save/not_interested)
- Recording digest completions and updating streaks
- Integration with Personalization system for 'not_interested' actions

Safe reuse patterns:
- Uses existing DigestSelector service (from 01-02)
- Uses existing Personalization service for mutes
- Uses existing StreakService for gamification updates
"""

import time
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from typing import Optional, List, Dict, Any
from uuid import UUID, uuid4

import structlog
from sqlalchemy import select, and_, exists
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import selectinload

from app.models.daily_digest import DailyDigest
from app.models.digest_completion import DigestCompletion
from app.models.content import Content, UserContentStatus
from app.models.enums import ContentStatus
from app.models.user_personalization import UserPersonalization
from app.models.user import UserStreak
from app.schemas.digest import DigestItem, DigestResponse, DigestAction
from app.services.digest_selector import DigestSelector
from app.services.streak_service import StreakService

logger = structlog.get_logger()


@dataclass
class EmergencyItem:
    """Dummy DigestItem wrapper for emergency fallback."""
    content: Content
    score: float = 0.5
    rank: int = 0
    reason: str = "Sélection de la rédaction"


class DigestService:
    """Service for digest retrieval, actions, and completion tracking.
    
    This service orchestrates between:
    - DigestSelector: For generating new digests
    - Personalization: For 'not_interested' mutes
    - StreakService: For completion gamification
    """
    
    def __init__(self, session: AsyncSession):
        self.session = session
        self.selector = DigestSelector(session)
        self.streak_service = StreakService(session)
        
    async def get_or_create_digest(
        self, 
        user_id: UUID,
        target_date: Optional[date] = None
    ) -> Optional[DigestResponse]:
        """Retrieves or generates today's digest for a user.
        
        Flow:
        1. Ensure user profile exists (creates if missing)
        2. Check if digest already exists for user + date
        3. If exists, return it with action states populated
        4. If not exists, generate new digest using DigestSelector
        5. Store in database and return
        
        Args:
            user_id: UUID of the user
            target_date: Date for digest (defaults to today)
            
        Returns:
            DigestResponse with 5 items, or None if generation failed
        """
        start_time = time.time()
        
        if target_date is None:
            target_date = date.today()
            
        logger.info("digest_get_or_create", user_id=str(user_id), target_date=str(target_date))
        
        # 0. Ensure user profile exists
        # This prevents 503 errors for new users who don't have a profile yet
        step_start = time.time()
        from app.services.user_service import UserService
        user_service = UserService(self.session)
        await user_service.get_or_create_profile(str(user_id))
        profile_time = time.time() - step_start
        logger.info("digest_step_profile", user_id=str(user_id), duration_ms=round(profile_time * 1000, 2))
        
        # 1. Check for existing digest
        step_start = time.time()
        existing_digest = await self._get_existing_digest(user_id, target_date)
        existing_time = time.time() - step_start
        if existing_digest:
            logger.info("digest_found_existing", user_id=str(user_id), digest_id=str(existing_digest.id), duration_ms=round(existing_time * 1000, 2))
            return await self._build_digest_response(existing_digest, user_id)
        logger.info("digest_no_existing", user_id=str(user_id), duration_ms=round(existing_time * 1000, 2))
        
        # 2. Generate new digest using DigestSelector
        step_start = time.time()
        logger.info("digest_generating_new", user_id=str(user_id))
        digest_items = await self.selector.select_for_user(user_id, limit=5)
        selection_time = time.time() - step_start
        logger.info("digest_step_selection", user_id=str(user_id), item_count=len(digest_items), duration_ms=round(selection_time * 1000, 2))
        
        # Emergency Fallback: If standard selection returns nothing, grab ANY recent curated content
        # This prevents 503 errors when personalization is too restrictive or history is empty
        if not digest_items:
            step_start = time.time()
            logger.warning("digest_generation_standard_failed_attempting_fallback", user_id=str(user_id))
            digest_items = await self._get_emergency_candidates(limit=5)
            fallback_time = time.time() - step_start
            logger.info("digest_step_fallback", user_id=str(user_id), item_count=len(digest_items), duration_ms=round(fallback_time * 1000, 2))
            
        if not digest_items:
            # If even emergency fallback fails, then we truly have a problem (empty DB?)
            logger.error("digest_generation_failed_total", user_id=str(user_id))
            return None
        
        # 3. Store in database
        step_start = time.time()
        digest = await self._create_digest_record(user_id, target_date, digest_items)
        store_time = time.time() - step_start
        
        total_time = time.time() - start_time
        logger.info(
            "digest_created", 
            user_id=str(user_id), 
            digest_id=str(digest.id),
            items_count=len(digest_items),
            store_duration_ms=round(store_time * 1000, 2),
            total_duration_ms=round(total_time * 1000, 2)
        )
        
        return await self._build_digest_response(digest, user_id)

        

    async def _get_emergency_candidates(self, limit: int = 5) -> List[Any]:
        """Last resort: get most recent curated content ignoring constraints.
        
        OPTIMIZATION: Added time window filter to limit query scope.
        Only fetches content from last 7 days instead of full table scan.
        This significantly improves performance when Content table is large.
        """
        from app.models.content import Content
        from app.models.source import Source
        from sqlalchemy import desc
        from sqlalchemy.orm import selectinload
        
        # OPTIMIZATION: Limit query to last 7 days to avoid full table scan
        cutoff_date = datetime.utcnow() - timedelta(days=7)
        
        stmt = (
            select(Content)
            .join(Content.source)
            .options(selectinload(Content.source))
            .where(
                Source.is_curated == True,
                Content.published_at >= cutoff_date  # Add time window filter
            )
            .order_by(Content.published_at.desc())
            .limit(limit)
        )
        
        result = await self.session.execute(stmt)
        contents = result.scalars().all()
        
        return [
            EmergencyItem(content=c, rank=i+1) 
            for i, c in enumerate(contents)
        ]
    
    async def apply_action(
        self,
        digest_id: UUID,
        user_id: UUID,
        content_id: UUID,
        action: DigestAction
    ) -> Dict[str, Any]:
        """Apply an action to a digest item.
        
        Actions:
        - READ: Mark article as consumed in UserContentStatus
        - SAVE: Save article to user's list
        - NOT_INTERESTED: Hide article and trigger personalization mute
        - UNDO: Reset all actions
        
        Args:
            digest_id: ID of the daily digest
            user_id: ID of the user
            content_id: ID of the content/article
            action: Action to apply
            
        Returns:
            Dict with success status and action details
        """
        logger.info(
            "digest_action_apply",
            user_id=str(user_id),
            digest_id=str(digest_id),
            content_id=str(content_id),
            action=action.value
        )
        
        # Get or create UserContentStatus
        status = await self._get_or_create_content_status(user_id, content_id)
        
        if action == DigestAction.READ:
            status.status = ContentStatus.CONSUMED
            status.is_hidden = False
            # Increment regular streak via StreakService
            await self.streak_service.increment_consumption(str(user_id))
            
        elif action == DigestAction.SAVE:
            status.is_saved = True
            status.saved_at = datetime.utcnow()
            status.is_hidden = False
            
        elif action == DigestAction.NOT_INTERESTED:
            status.is_hidden = True
            status.hidden_reason = "not_interested"
            # Trigger personalization mute
            await self._trigger_personalization_mute(user_id, content_id)
            
        elif action == DigestAction.UNDO:
            status.status = ContentStatus.UNSEEN
            status.is_saved = False
            status.is_hidden = False
            status.hidden_reason = None
            
        else:
            raise ValueError(f"Unknown action: {action}")
        
        await self.session.flush()
        
        return {
            "success": True,
            "content_id": content_id,
            "action": action,
            "applied_at": datetime.utcnow()
        }
    
    async def complete_digest(
        self,
        digest_id: UUID,
        user_id: UUID,
        closure_time_seconds: Optional[int] = None
    ) -> Dict[str, Any]:
        """Record completion of a digest.
        
        - Creates DigestCompletion record
        - Updates closure streak via StreakService
        - Returns completion stats and streak info
        
        Args:
            digest_id: ID of the daily digest
            user_id: ID of the user
            closure_time_seconds: Time spent reading digest (optional)
            
        Returns:
            Dict with completion stats and updated streak
        """
        logger.info(
            "digest_complete",
            user_id=str(user_id),
            digest_id=str(digest_id),
            closure_time=closure_time_seconds
        )
        
        # Get digest to determine target_date
        digest = await self.session.get(DailyDigest, digest_id)
        if not digest:
            raise ValueError(f"Digest not found: {digest_id}")
        
        # Get action stats from content statuses
        stats = await self._get_digest_action_stats(user_id, digest)
        
        # Create completion record
        completion = DigestCompletion(
            id=uuid4(),
            user_id=user_id,
            target_date=digest.target_date,
            completed_at=datetime.utcnow(),
            articles_read=stats["read"],
            articles_saved=stats["saved"],
            articles_dismissed=stats["dismissed"],
            closure_time_seconds=closure_time_seconds
        )
        self.session.add(completion)
        
        # Update closure streak
        streak_update = await self._update_closure_streak(user_id)
        
        await self.session.flush()
        
        return {
            "success": True,
            "digest_id": digest_id,
            "completed_at": completion.completed_at,
            "articles_read": stats["read"],
            "articles_saved": stats["saved"],
            "articles_dismissed": stats["dismissed"],
            "closure_time_seconds": closure_time_seconds,
            "closure_streak": streak_update["current"],
            "streak_message": streak_update.get("message")
        }
    
    async def _get_existing_digest(
        self, 
        user_id: UUID, 
        target_date: date
    ) -> Optional[DailyDigest]:
        """Check if digest already exists for user + date."""
        stmt = select(DailyDigest).where(
            and_(
                DailyDigest.user_id == user_id,
                DailyDigest.target_date == target_date
            )
        )
        result = await self.session.execute(stmt)
        return result.scalar_one_or_none()
    
    async def _create_digest_record(
        self,
        user_id: UUID,
        target_date: date,
        digest_items: List[Any]  # List[DigestItem]
    ) -> DailyDigest:
        """Create a new DailyDigest database record."""
        # Build items JSON array
        items_json = []
        for item in digest_items:
            items_json.append({
                "content_id": str(item.content.id),
                "rank": item.rank,
                "reason": item.reason,
                "source_name": item.content.source.name if item.content.source else None,
                "score": float(item.score)
            })
        
        digest = DailyDigest(
            id=uuid4(),
            user_id=user_id,
            target_date=target_date,
            items=items_json,
            generated_at=datetime.utcnow()
        )
        
        self.session.add(digest)
        await self.session.flush()
        
        return digest
    
    async def _build_digest_response(
        self,
        digest: DailyDigest,
        user_id: UUID
    ) -> DigestResponse:
        """Build DigestResponse from database record with action states."""
        # Check for existing completion
        completion = await self.session.scalar(
            select(DigestCompletion).where(
                and_(
                    DigestCompletion.user_id == user_id,
                    DigestCompletion.target_date == digest.target_date
                )
            )
        )
        
        # Build items with their action states
        items = []
        for item_data in digest.items:
            content_id = UUID(item_data["content_id"])
            
            # Fetch content details with eager loading of source
            stmt = select(Content).options(selectinload(Content.source)).where(Content.id == content_id)
            result = await self.session.execute(stmt)
            content = result.scalar_one_or_none()
            if not content:
                logger.warning(
                    "digest_content_not_found",
                    content_id=str(content_id),
                    digest_id=str(digest.id)
                )
                continue
            
            # Get user action state
            action_state = await self._get_item_action_state(user_id, content_id)
            
            # Build DigestItem
            items.append(DigestItem(
                content_id=content_id,
                title=content.title,
                url=content.url,
                thumbnail_url=content.thumbnail_url,
                description=content.description,
                content_type=content.content_type,
                duration_seconds=content.duration_seconds,
                published_at=content.published_at,
                source=content.source,  # SourceMini will be handled by from_attributes
                rank=item_data["rank"],
                reason=item_data["reason"],
                is_read=action_state["is_read"],
                is_saved=action_state["is_saved"],
                is_dismissed=action_state["is_dismissed"]
            ))
        
        return DigestResponse(
            digest_id=digest.id,
            user_id=digest.user_id,
            target_date=digest.target_date,
            generated_at=digest.generated_at,
            items=items,
            is_completed=completion is not None,
            completed_at=completion.completed_at if completion else None
        )
    
    async def _get_item_action_state(
        self, 
        user_id: UUID, 
        content_id: UUID
    ) -> Dict[str, bool]:
        """Get current action state for a digest item."""
        status = await self.session.scalar(
            select(UserContentStatus).where(
                and_(
                    UserContentStatus.user_id == user_id,
                    UserContentStatus.content_id == content_id
                )
            )
        )
        
        if not status:
            return {"is_read": False, "is_saved": False, "is_dismissed": False}
        
        return {
            "is_read": status.status == ContentStatus.CONSUMED,
            "is_saved": status.is_saved,
            "is_dismissed": status.is_hidden
        }
    
    async def _get_or_create_content_status(
        self,
        user_id: UUID,
        content_id: UUID
    ) -> UserContentStatus:
        """Get existing or create new UserContentStatus."""
        status = await self.session.scalar(
            select(UserContentStatus).where(
                and_(
                    UserContentStatus.user_id == user_id,
                    UserContentStatus.content_id == content_id
                )
            )
        )
        
        if not status:
            status = UserContentStatus(
                id=uuid4(),
                user_id=user_id,
                content_id=content_id,
                status=ContentStatus.UNSEEN
            )
            self.session.add(status)
            await self.session.flush()
        
        return status
    
    async def _trigger_personalization_mute(
        self,
        user_id: UUID,
        content_id: UUID
    ):
        """Trigger personalization mute for content's source/theme."""
        # Get content to find source and theme with eager loading
        stmt = select(Content).options(selectinload(Content.source)).where(Content.id == content_id)
        result = await self.session.execute(stmt)
        content = result.scalar_one_or_none()
        if not content or not content.source:
            return
        
        # Mute the source via upsert pattern (same as personalization router)
        from app.services.user_service import UserService
        user_service = UserService(self.session)
        
        # Ensure profile exists for FK constraint
        await user_service.get_or_create_profile(str(user_id))
        await self.session.flush()
        
        # Upsert into UserPersonalization
        from sqlalchemy import func, text
        
        stmt = pg_insert(UserPersonalization).values(
            user_id=user_id,
            muted_sources=[content.source_id]
        ).on_conflict_do_update(
            index_elements=['user_id'],
            set_={
                'muted_sources': func.coalesce(
                    UserPersonalization.muted_sources, 
                    text("'{}'::uuid[]")
                ).op('||')([content.source_id]),
                'updated_at': func.now()
            }
        )
        
        await self.session.execute(stmt)
        
        logger.info(
            "personalization_mute_triggered",
            user_id=str(user_id),
            content_id=str(content_id),
            source_id=str(content.source_id)
        )
    
    async def _get_digest_action_stats(
        self,
        user_id: UUID,
        digest: DailyDigest
    ) -> Dict[str, int]:
        """Count actions taken on digest items."""
        content_ids = [UUID(item["content_id"]) for item in digest.items]
        
        # Get all statuses for these content items
        stmt = select(UserContentStatus).where(
            and_(
                UserContentStatus.user_id == user_id,
                UserContentStatus.content_id.in_(content_ids)
            )
        )
        result = await self.session.execute(stmt)
        statuses = result.scalars().all()
        
        # Count actions
        read_count = sum(1 for s in statuses if s.status == ContentStatus.CONSUMED)
        saved_count = sum(1 for s in statuses if s.is_saved)
        dismissed_count = sum(1 for s in statuses if s.is_hidden)
        
        return {
            "read": read_count,
            "saved": saved_count,
            "dismissed": dismissed_count
        }
    
    async def _update_closure_streak(self, user_id: UUID) -> Dict[str, Any]:
        """Update user's closure streak for digest completion."""
        # Get or create streak record
        streak = await self.session.scalar(
            select(UserStreak).where(UserStreak.user_id == user_id)
        )
        
        if not streak:
            streak = UserStreak(
                id=uuid4(),
                user_id=user_id,
                week_start=date.today() - timedelta(days=date.today().weekday())
            )
            self.session.add(streak)
            await self.session.flush()
        
        today = date.today()
        
        # Update closure streak
        if streak.last_closure_date:
            days_since = (today - streak.last_closure_date).days
            
            if days_since == 0:
                # Already completed today - don't increment
                pass
            elif days_since == 1:
                # Consecutive day - increment
                streak.closure_streak += 1
            else:
                # Streak broken - reset to 1
                streak.closure_streak = 1
        else:
            # First completion
            streak.closure_streak = 1
        
        streak.last_closure_date = today
        
        # Update longest closure streak
        if streak.closure_streak > streak.longest_closure_streak:
            streak.longest_closure_streak = streak.closure_streak
        
        # Generate message
        message = None
        if streak.closure_streak == 1:
            message = "Premier digest complété !"
        elif streak.closure_streak == 7:
            message = "Série de 7 jours ! 🔥"
        elif streak.closure_streak == 30:
            message = "Série de 30 jours ! 🎉"
        elif streak.closure_streak > 1:
            message = f"Série de {streak.closure_streak} jours !"
        
        return {
            "current": streak.closure_streak,
            "longest": streak.longest_closure_streak,
            "message": message
        }
