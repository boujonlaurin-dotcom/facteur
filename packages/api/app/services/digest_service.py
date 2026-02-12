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
from datetime import date, datetime, timedelta, timezone
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
from app.schemas.digest import (
    DigestItem, 
    DigestResponse, 
    DigestAction, 
    DigestScoreBreakdown, 
    DigestRecommendationReason
)
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
    breakdown: Optional[List[DigestScoreBreakdown]] = None


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
        target_date: Optional[date] = None,
        hours_lookback: int = 168,
        force_regenerate: bool = False,
        mode: Optional[str] = None,
        focus_theme: Optional[str] = None,
    ) -> Optional[DigestResponse]:
        """Retrieves or generates today's digest for a user.

        Flow:
        1. Ensure user profile exists (creates if missing)
        2. Check if digest already exists for user + date
        3. If exists and force_regenerate=False, return existing
        4. If force_regenerate=True, delete existing and regenerate
        5. Generate new digest using DigestSelector
        6. Store in database and return

        Args:
            user_id: UUID of the user
            target_date: Date for digest (defaults to today)
            hours_lookback: Hours to look back for content (default: 168h/7 days)
                Extended window ensures user's followed sources are prioritized
                even if articles are older.
            force_regenerate: If True, delete existing digest and regenerate

        Returns:
            DigestResponse with 7 items, or None if generation failed
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
            if force_regenerate:
                # Delete existing digest and regenerate
                logger.info("digest_force_regenerating", user_id=str(user_id), digest_id=str(existing_digest.id), duration_ms=round(existing_time * 1000, 2))
                await self.session.delete(existing_digest)
                await self.session.flush()
            else:
                logger.info("digest_found_existing", user_id=str(user_id), digest_id=str(existing_digest.id), duration_ms=round(existing_time * 1000, 2))
                return await self._build_digest_response(existing_digest, user_id)
        logger.info("digest_no_existing", user_id=str(user_id), duration_ms=round(existing_time * 1000, 2))
        
        # 2. Determine effective mode (param > user pref > default)
        effective_mode = mode
        if not effective_mode:
            effective_mode = await self._get_user_digest_mode(user_id)
        effective_focus_theme = focus_theme
        if not effective_focus_theme and effective_mode == "theme_focus":
            effective_focus_theme = await self._get_user_focus_theme(user_id)

        # 3. Generate new digest using DigestSelector
        step_start = time.time()
        logger.info("digest_generating_new", user_id=str(user_id), hours_lookback=hours_lookback, mode=effective_mode, focus_theme=effective_focus_theme)
        from app.services.digest_selector import DiversityConstraints
        target_size = DiversityConstraints.TARGET_DIGEST_SIZE
        digest_items = await self.selector.select_for_user(
            user_id, limit=target_size, hours_lookback=hours_lookback,
            mode=effective_mode or "pour_vous", focus_theme=effective_focus_theme,
        )
        selection_time = time.time() - step_start
        logger.info("digest_step_selection", user_id=str(user_id), item_count=len(digest_items), duration_ms=round(selection_time * 1000, 2))
        
        # Emergency Fallback: If standard selection returns nothing, grab from user's sources first
        # This prevents 503 errors when personalization is too restrictive or history is empty
        if not digest_items:
            step_start = time.time()
            logger.warning("digest_generation_standard_failed_attempting_fallback", user_id=str(user_id))
            digest_items = await self._get_emergency_candidates(user_id=user_id, limit=target_size)
            fallback_time = time.time() - step_start
            logger.info("digest_step_fallback", user_id=str(user_id), item_count=len(digest_items), duration_ms=round(fallback_time * 1000, 2))
            
        if not digest_items:
            # If even emergency fallback fails, then we truly have a problem (empty DB?)
            logger.error("digest_generation_failed_total", user_id=str(user_id))
            return None
        
        # 4. Store in database
        step_start = time.time()
        digest = await self._create_digest_record(user_id, target_date, digest_items, mode=effective_mode)
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

        

    async def _get_emergency_candidates(self, user_id: UUID, limit: int = 5) -> List[Any]:
        """Last resort: get most recent content from user's followed sources first.
        
        CRITICAL FIX: Now prioritizes user's followed sources instead of just curated content.
        Falls back to curated sources only if user has no followed sources.
        
        Applies diversity constraints (max 2 per source) and generates minimal
        breakdown data so the personalization sheet can display properly.
        """
        from app.models.content import Content
        from app.models.source import Source
        from sqlalchemy import desc
        from sqlalchemy.orm import selectinload
        from collections import defaultdict
        
        MAX_PER_SOURCE = 2  # Same constraint as DigestSelector
        # Fetch more candidates than needed so we can apply diversity
        fetch_limit = limit * 5  
        
        # Get user's followed sources
        from app.models.source import UserSource
        followed_result = await self.session.execute(
            select(UserSource.source_id).where(UserSource.user_id == user_id)
        )
        followed_source_ids = set(followed_result.scalars().all())
        
        # OPTIMIZATION: Limit query to last 7 days to avoid full table scan
        cutoff_date = datetime.now(timezone.utc) - timedelta(days=7)
        
        all_contents: list = []
        
        # Try user's followed sources first
        if followed_source_ids:
            stmt = (
                select(Content)
                .join(Content.source)
                .options(selectinload(Content.source))
                .where(
                    Content.source_id.in_(list(followed_source_ids)),
                    Content.published_at >= cutoff_date
                )
                .order_by(Content.published_at.desc())
                .limit(fetch_limit)
            )
            
            result = await self.session.execute(stmt)
            all_contents = list(result.scalars().all())
        
        # If not enough from user sources, add curated sources
        if len(all_contents) < fetch_limit:
            existing_ids = {c.id for c in all_contents}
            curated_query = (
                select(Content)
                .join(Content.source)
                .options(selectinload(Content.source))
                .where(
                    Source.is_curated == True,
                    Content.published_at >= cutoff_date,
                )
                .order_by(Content.published_at.desc())
                .limit(fetch_limit - len(all_contents))
            )
            if existing_ids:
                curated_query = curated_query.where(Content.id.notin_(list(existing_ids)))
            stmt = curated_query
            
            result = await self.session.execute(stmt)
            all_contents.extend(result.scalars().all())
        
        # Apply diversity constraint: max 2 articles per source
        selected: list = []
        source_counts: dict = defaultdict(int)
        
        for content in all_contents:
            if len(selected) >= limit:
                break
            
            source_id = content.source_id
            if source_counts[source_id] >= MAX_PER_SOURCE:
                continue
            
            # Generate a minimal breakdown for the personalization sheet
            breakdown_items = []
            
            # Recency info
            hours_old = (datetime.now(timezone.utc) - content.published_at.replace(tzinfo=timezone.utc if content.published_at.tzinfo is None else content.published_at.tzinfo)).total_seconds() / 3600
            if hours_old < 6:
                breakdown_items.append(DigestScoreBreakdown(label="Article très récent (< 6h)", points=30.0, is_positive=True))
            elif hours_old < 24:
                breakdown_items.append(DigestScoreBreakdown(label="Article récent (< 24h)", points=25.0, is_positive=True))
            elif hours_old < 48:
                breakdown_items.append(DigestScoreBreakdown(label="Publié aujourd'hui", points=15.0, is_positive=True))
            elif hours_old < 72:
                breakdown_items.append(DigestScoreBreakdown(label="Publié hier", points=8.0, is_positive=True))
            
            # Source info
            if content.source_id in followed_source_ids:
                breakdown_items.append(DigestScoreBreakdown(label="Source de confiance", points=50.0, is_positive=True))
            elif content.source and content.source.is_curated:
                breakdown_items.append(DigestScoreBreakdown(label="Source qualitative", points=10.0, is_positive=True))
            
            # Theme info
            if content.source and content.source.theme:
                theme_labels = {
                    'tech': 'Tech', 'society': 'Société', 'environment': 'Environnement',
                    'economy': 'Économie', 'politics': 'Politique', 'culture': 'Culture',
                    'science': 'Sciences', 'international': 'International',
                }
                theme_label = theme_labels.get(content.source.theme, content.source.theme.capitalize())
                breakdown_items.append(DigestScoreBreakdown(label=f"Thème : {theme_label}", points=20.0, is_positive=True))
            
            # Build reason — prefer theme info over generic label
            theme_labels = {
                'tech': 'Tech & Innovation', 'society': 'Société', 'environment': 'Environnement',
                'economy': 'Économie', 'politics': 'Politique', 'culture': 'Culture & Idées',
                'science': 'Sciences', 'international': 'Géopolitique', 'geopolitics': 'Géopolitique',
            }
            if content.source and content.source.theme:
                label = theme_labels.get(content.source.theme.lower(), content.source.theme.capitalize())
                reason = f"Thème : {label}"
            elif content.source_id in followed_source_ids:
                reason = "Source suivie"
            else:
                reason = "Sélection de la rédaction"
            
            selected.append(EmergencyItem(
                content=content,
                score=sum(b.points for b in breakdown_items),
                rank=len(selected) + 1,
                reason=reason,
                breakdown=breakdown_items,
            ))
            source_counts[source_id] += 1
        
        # Log diversity stats
        unique_sources = len(set(item.content.source_id for item in selected))
        logger.info(
            "digest_emergency_fallback_with_diversity",
            user_id=str(user_id),
            count=len(selected),
            unique_sources=unique_sources,
            source_distribution={str(k): v for k, v in source_counts.items()},
            had_followed_sources=bool(followed_source_ids)
        )
        
        return selected
    
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
            # Reinforce subtopic weights on bookmark
            from app.services.content_service import ContentService
            content_service = ContentService(self.session)
            from app.services.recommendation.scoring_config import ScoringWeights
            await content_service._adjust_subtopic_weights(
                user_id, content_id, ScoringWeights.BOOKMARK_TOPIC_BOOST
            )

        elif action == DigestAction.LIKE:
            status.is_liked = True
            status.liked_at = datetime.utcnow()
            # Reinforce subtopic weights via ContentService
            from app.services.content_service import ContentService
            content_service = ContentService(self.session)
            from app.services.recommendation.scoring_config import ScoringWeights
            await content_service._adjust_subtopic_weights(
                user_id, content_id, ScoringWeights.LIKE_TOPIC_BOOST
            )

        elif action == DigestAction.UNLIKE:
            status.is_liked = False
            status.liked_at = None
            # Reverse subtopic weight adjustment
            from app.services.content_service import ContentService
            content_service = ContentService(self.session)
            from app.services.recommendation.scoring_config import ScoringWeights
            await content_service._adjust_subtopic_weights(
                user_id, content_id, -ScoringWeights.LIKE_TOPIC_BOOST
            )

        elif action == DigestAction.NOT_INTERESTED:
            status.is_hidden = True
            status.hidden_reason = "not_interested"
            # Trigger personalization mute
            await self._trigger_personalization_mute(user_id, content_id)

        elif action == DigestAction.UNDO:
            status.status = ContentStatus.UNSEEN
            status.is_saved = False
            status.is_liked = False
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
        digest_items: List[Any],  # List[DigestItem]
        mode: Optional[str] = None,
    ) -> DailyDigest:
        """Create a new DailyDigest database record."""
        # Build items JSON array
        items_json = []
        for item in digest_items:
            item_data = {
                "content_id": str(item.content.id),
                "rank": item.rank,
                "reason": item.reason,
                "source_name": item.content.source.name if item.content.source else None,
                "score": float(item.score)
            }
            
            # Store breakdown if available
            # Use getattr for safety: DigestItem (from selector) has .breakdown,
            # but EmergencyItem (fallback) may not always have it as a direct attribute
            breakdown = getattr(item, 'breakdown', None)
            if breakdown:
                logger.info(
                    "storing_breakdown_for_digest_item",
                    content_id=str(item.content.id),
                    content_title=item.content.title[:50] if item.content.title else "",
                    breakdown_count=len(breakdown),
                    breakdown_labels=[b.label for b in breakdown[:3]]
                )
                item_data["breakdown"] = [
                    {
                        "label": b.label,
                        "points": b.points,
                        "is_positive": b.is_positive
                    }
                    for b in breakdown
                ]
            else:
                logger.warning(
                    "no_breakdown_available_for_digest_item",
                    content_id=str(item.content.id),
                    content_title=item.content.title[:50] if item.content.title else "",
                    item_type=type(item).__name__
                )
            
            items_json.append(item_data)
        
        digest = DailyDigest(
            id=uuid4(),
            user_id=user_id,
            target_date=target_date,
            items=items_json,
            mode=mode or "pour_vous",
            generated_at=datetime.utcnow()
        )
        
        self.session.add(digest)
        await self.session.flush()
        
        return digest
    
    def _determine_top_reason(self, breakdown: List[DigestScoreBreakdown]) -> str:
        """Extract the most significant positive reason for the label.
        
        Analyzes the breakdown to generate a user-friendly top-level reason.
        """
        if not breakdown:
            return "Sélectionné pour vous"
        
        positive = [b for b in breakdown if b.is_positive]
        if not positive:
            return "Sélectionné pour vous"
        
        # Sort by points descending
        positive.sort(key=lambda x: x.points, reverse=True)
        top = positive[0]
        
        # Format based on top reason type
        if "Thème" in top.label:
            theme = top.label.split(": ")[1] if ": " in top.label else ""
            return f"Vos intérêts : {theme}"
        elif "Source de confiance" in top.label:
            return "Source suivie"
        elif "Source personnalisée" in top.label:
            return "Ta source personnalisée"
        elif "Renforcé par vos j'aime" in top.label:
            topics = [
                parts[1] for b in positive
                if "Renforcé" in b.label
                for parts in [b.label.split(": ", 1)]
                if len(parts) > 1
            ][:2]
            return f"Renforcé par vos j'aime : {', '.join(topics)}" if topics else "Renforcé par vos j'aime"
        elif "Sous-thème" in top.label:
            topics = [
                parts[1] for b in positive
                if "Sous-thème" in b.label
                for parts in [b.label.split(": ", 1)]
                if len(parts) > 1
            ][:2]
            return f"Vos centres d'intérêt : {', '.join(topics)}" if topics else "Vos centres d'intérêt"
        else:
            return top.label
    
    async def _build_digest_response(
        self,
        digest: DailyDigest,
        user_id: UUID
    ) -> DigestResponse:
        """Build DigestResponse from database record with action states.
        
        Optimized: batch-fetches all content and action states in 3 queries
        instead of 2*N queries (N per content + N per action state).
        """
        # Extract all content IDs upfront
        content_ids = [UUID(item_data["content_id"]) for item_data in digest.items]
        
        # Batch query 1: Check for existing completion
        completion = await self.session.scalar(
            select(DigestCompletion).where(
                and_(
                    DigestCompletion.user_id == user_id,
                    DigestCompletion.target_date == digest.target_date
                )
            )
        )
        
        # Batch query 2: Fetch ALL content with eager-loaded sources in one query
        content_stmt = (
            select(Content)
            .options(selectinload(Content.source))
            .where(Content.id.in_(content_ids))
        )
        content_result = await self.session.execute(content_stmt)
        content_map = {c.id: c for c in content_result.scalars().all()}
        
        # Batch query 3: Fetch ALL action states in one query
        action_states_map = await self._get_batch_action_states(user_id, content_ids)
        
        logger.info(
            "digest_response_batch_loaded",
            digest_id=str(digest.id),
            content_found=len(content_map),
            content_expected=len(content_ids),
            action_states_found=len(action_states_map),
        )
        
        # Build items using pre-fetched data (no more per-item queries)
        items = []
        for item_data in digest.items:
            content_id = UUID(item_data["content_id"])
            content = content_map.get(content_id)
            
            if not content or not content.source:
                logger.warning(
                    "digest_content_or_source_not_found",
                    content_id=str(content_id),
                    digest_id=str(digest.id),
                    content_found=content is not None,
                    source_found=bool(content and content.source)
                )
                continue
            
            # Get action state from pre-fetched map
            action_state = action_states_map.get(
                content_id,
                {"is_read": False, "is_saved": False, "is_liked": False, "is_dismissed": False}
            )
            
            # Rebuild breakdown from stored data if available
            breakdown_data = item_data.get("breakdown") or []
            if not breakdown_data:
                logger.debug(
                    "no_breakdown_data_in_stored_item",
                    content_id=str(content_id),
                    digest_id=str(digest.id),
                    item_rank=item_data.get("rank", 0)
                )
            breakdown = [
                DigestScoreBreakdown(
                    label=b.get("label", ""),
                    points=b.get("points", 0.0),
                    is_positive=b.get("is_positive", True)
                )
                for b in breakdown_data
                if isinstance(b, dict) and b.get("label")
            ] if breakdown_data else []
            
            # Build recommendation_reason if breakdown exists
            recommendation_reason = None
            if breakdown:
                recommendation_reason = DigestRecommendationReason(
                    label=self._determine_top_reason(breakdown),
                    score_total=sum(b.points for b in breakdown),
                    breakdown=breakdown
                )
            
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
                recommendation_reason=recommendation_reason,
                is_read=action_state["is_read"],
                is_saved=action_state["is_saved"],
                is_liked=action_state["is_liked"],
                is_dismissed=action_state["is_dismissed"]
            ))
        
        from app.services.digest_selector import DiversityConstraints
        return DigestResponse(
            digest_id=digest.id,
            user_id=digest.user_id,
            target_date=digest.target_date,
            generated_at=digest.generated_at,
            mode=digest.mode or "pour_vous",
            items=items,
            completion_threshold=DiversityConstraints.COMPLETION_THRESHOLD,
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
            return {"is_read": False, "is_saved": False, "is_liked": False, "is_dismissed": False}

        return {
            "is_read": status.status == ContentStatus.CONSUMED,
            "is_saved": status.is_saved,
            "is_liked": status.is_liked,
            "is_dismissed": status.is_hidden
        }
    
    async def _get_batch_action_states(
        self,
        user_id: UUID,
        content_ids: List[UUID]
    ) -> Dict[UUID, Dict[str, bool]]:
        """Batch-fetch action states for multiple content items in one query.
        
        Optimized replacement for calling _get_item_action_state per item.
        Reduces N queries to 1 query for the entire digest.
        """
        if not content_ids:
            return {}
        
        stmt = select(UserContentStatus).where(
            and_(
                UserContentStatus.user_id == user_id,
                UserContentStatus.content_id.in_(content_ids)
            )
        )
        result = await self.session.execute(stmt)
        statuses = result.scalars().all()
        
        return {
            status.content_id: {
                "is_read": status.status == ContentStatus.CONSUMED,
                "is_saved": status.is_saved,
                "is_liked": status.is_liked,
                "is_dismissed": status.is_hidden
            }
            for status in statuses
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

    async def _get_user_digest_mode(self, user_id: UUID) -> Optional[str]:
        """Lit la préférence digest_mode depuis user_preferences."""
        from app.models.user import UserPreference, UserProfile
        result = await self.session.execute(
            select(UserPreference.preference_value)
            .join(UserProfile, UserPreference.user_id == UserProfile.user_id)
            .where(
                UserProfile.user_id == user_id,
                UserPreference.preference_key == "digest_mode",
            )
        )
        value = result.scalar_one_or_none()
        return value if value else None

    async def _get_user_focus_theme(self, user_id: UUID) -> Optional[str]:
        """Lit la préférence digest_focus_theme depuis user_preferences."""
        from app.models.user import UserPreference, UserProfile
        result = await self.session.execute(
            select(UserPreference.preference_value)
            .join(UserProfile, UserPreference.user_id == UserProfile.user_id)
            .where(
                UserProfile.user_id == user_id,
                UserPreference.preference_key == "digest_focus_theme",
            )
        )
        value = result.scalar_one_or_none()
        return value if value else None
