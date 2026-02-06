"""Service de gestion du Briefing Quotidien (Essentiels du jour).

Ce service centralise la logique de génération et de récupération du Top 3.
Il permet une stratégie hybride :
1. Génération Batch (via Scheduler @ 8h)
2. Génération Lazy (On-Demand si manquant)
"""
import datetime
from typing import List, Set, Tuple, Optional
from uuid import UUID

import structlog
from sqlalchemy import select, and_
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.content import Content
from app.models.daily_top3 import DailyTop3
from app.models.user import UserProfile
from app.services.briefing.importance_detector import ImportanceDetector
from app.services.briefing.top3_selector import Top3Selector
from app.services.recommendation_service import RecommendationService
from app.services.recommendation.scoring_engine import ScoringContext

# Note: Pour éviter les imports circulaires, on va devoir déplacer fetch_une_guids/get_recent_contents
# VERS ce service ou un helper commun. Pour l'instant, on duplique proprement la logique
# ou on import depuis top3_job si pas de cycle. top3_job importera ce service, donc
# top3_job NE DOIT PAS être importé ici.
# -> On va déplacer les helpers de fetch ici en méthodes statiques ou privées.

import feedparser
import asyncio
from app.models.source import Source

logger = structlog.get_logger()


class BriefingService:
    def __init__(self, session: AsyncSession):
        self.session = session
        self.rec_service = RecommendationService(session)
        self.importance_detector = ImportanceDetector()
        self.top3_selector = Top3Selector()

    async def get_or_create_briefing(self, user_id: UUID) -> List[dict]:
        """Récupère le briefing du jour, ou le génère s'il n'existe pas (Lazy Loading).
        
        Returns:
            Liste des items DailyTop3 (format dict pour API/Schema)
            Structure: [{'rank': 1, 'reason': '...', 'content': Content object, ...}]
        """
        # 1. Tenter de récupérer le briefing existant
        today_start = datetime.datetime.now(datetime.timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
        
        stmt = (
            select(DailyTop3)
            .options(
                selectinload(DailyTop3.content)
                .selectinload(Content.source)
            )
            .where(
                DailyTop3.user_id == user_id,
                DailyTop3.generated_at >= today_start
            )
            .order_by(DailyTop3.rank)
        )
        result = await self.session.execute(stmt)
        rows = result.scalars().all()
        
        if rows:
            # Déjà existant
            # Defensive check: Filter out any briefing items where content is missing
            valid_rows = [row for row in rows if row.content is not None]
            if len(valid_rows) < len(rows):
                logger.warning("briefing_missing_content_detected", 
                               user_id=str(user_id), 
                               total=len(rows), 
                               valid=len(valid_rows))
            
            return [
                {
                    "rank": row.rank,
                    "reason": row.top3_reason,
                    "consumed": row.consumed,
                    "content": row.content,
                    "content_id": row.content_id
                }
                for row in valid_rows
            ]
        
        # 2. Si absent -> Génération On-Demand
        logger.info("briefing_lazy_generation_triggered", user_id=str(user_id))
        return await self.generate_briefing_for_user(user_id)

    async def generate_briefing_for_user(self, user_id: UUID, global_context: dict = None) -> List[dict]:
        """Génère ET persiste le briefing pour un utilisateur spécifique.
        
        Args:
            user_id: ID utilisateur
            global_context: Dict optionnel contenant 'une_ids' et 'trending_ids' (cache)
                            Si None, ils seront calculés (coûteux).
        """
        # A. Global Context (Caching opportunity)
        if not global_context:
            global_context = await self._build_global_context()
            
        une_ids = global_context.get('une_ids', set())
        trending_ids = global_context.get('trending_ids', set())
        
        # B. User Specifics
        # Récupérer sources suivies
        from app.models.source import UserSource
        res = await self.session.execute(
            select(UserSource.source_id).where(UserSource.user_id == user_id)
        )
        followed_source_ids = set(res.scalars().all())
        
        # Récupérer profil (intérêts pour filtrage)
        stmt_profile = (
            select(UserProfile)
            .options(
                selectinload(UserProfile.interests),
                selectinload(UserProfile.preferences)
            )
            .where(UserProfile.user_id == user_id)
        )
        profile_res = await self.session.execute(stmt_profile)
        user_profile = profile_res.scalar_one_or_none()
        
        if not user_profile:
            logger.error("briefing_generation_failed_no_profile", user_id=str(user_id))
            return []

        # C. Fetch Candidates (via RecService)
        # On utilise une limite large pour avoir du choix
        candidates = await self.rec_service._get_candidates(
            user_id=user_id,
            limit_candidates=200,
            followed_source_ids=followed_source_ids
        )
        
        if not candidates:
            return []

        # D. Scoring
        scored_contents = []
        user_interests = {i.interest_slug for i in user_profile.interests}
        
        # Helper context construction (simplifié locale)
        # TODO: Unifier avec RecService.create_context
        context = ScoringContext(
            user_profile=user_profile,
            user_interests=user_interests,
            user_interest_weights={i.interest_slug: i.weight for i in user_profile.interests},
            followed_source_ids=followed_source_ids,
            user_prefs={p.preference_key: p.preference_value for p in user_profile.preferences},
            now=datetime.datetime.now(datetime.timezone.utc),
            # Minimal required fields
            user_subtopics=set(),
            muted_sources=set(),
            muted_themes=set(),
            muted_topics=set(),
            custom_source_ids=set()
        )

        # Filtrage Pertinence (Intérêts OU Sources Suivies)
        filtered_candidates = [
            c for c in candidates
            if (c.source and c.source.theme in user_interests) or 
               (c.source_id in followed_source_ids)
        ]
        
        if len(filtered_candidates) < 10:
             # Fallback si trop restrictif
             filtered_candidates = candidates

        for content in filtered_candidates:
            try:
                score = self.rec_service.scoring_engine.compute_score(content, context)
                scored_contents.append((content, score))
            except Exception as e:
                logger.warning("scoring_failed", content_id=str(content.id), error=str(e))
                pass

        # E. Selection Top 3
        top3_items = self.top3_selector.select_top3(
            scored_contents=scored_contents,
            user_followed_sources=followed_source_ids,
            une_content_ids=une_ids,
            trending_content_ids=trending_ids
        )
        
        # F. Persistence
        generated_at = datetime.datetime.utcnow()
        result_dicts = []
        
        for i, item in enumerate(top3_items):
            # Insert DB
            rank = i + 1
            stmt_insert = insert(DailyTop3).values(
                user_id=user_id,
                content_id=item.content.id,
                rank=rank,
                top3_reason=item.top3_reason,
                generated_at=generated_at,
                consumed=False
            ).on_conflict_do_nothing()
            
            await self.session.execute(stmt_insert)
            
            # Prepare return format
            result_dicts.append({
                "rank": rank,
                "reason": item.top3_reason,
                "consumed": False,
                "content": item.content,
                "content_id": item.content.id
            })
            
        # NOTE: Nous commitons ici explicitement pour assurer que la génération On-Demand 
        # soit immédiatement persistée, évitant des doubles générations sur des requêtes concurrentes.
        await self.session.commit()
        
        return result_dicts

    async def _build_global_context(self) -> dict:
        """Construit le contexte global (Une & Trending) pour la génération."""
        # 1. Fetch Une GUIDs
        # TODO: Mettre en cache Redis/Memory pour éviter de spammer les RSS
        une_guids = await self._fetch_une_guids()
        
        # 2. Fetch Recent Contents
        recent_contents = await self._get_recent_contents(hours=24)
        
        # 3. Detect
        une_ids = self.importance_detector.identify_une_contents(recent_contents, une_guids)
        trending_ids = self.importance_detector.detect_trending_clusters(recent_contents)
        
        return {
            'une_ids': une_ids,
            'trending_ids': trending_ids
        }

    # --- Helpers Private (Extraits de top3_job.py) ---
    
    async def _fetch_une_guids(self) -> Set[str]:
        """Récupère les GUIDs des articles 'À la Une'."""
        stmt = select(Source).where(Source.une_feed_url.is_not(None))
        result = await self.session.execute(stmt)
        sources = result.scalars().all()
        
        if not sources:
            return set()
        
        une_guids: Set[str] = set()
        
        async def parse_feed(url: str) -> List[str]:
            try:
                loop = asyncio.get_event_loop()
                feed = await loop.run_in_executor(None, feedparser.parse, url)
                return [
                    entry.id if hasattr(entry, 'id') else entry.link 
                    for entry in feed.entries[:5]
                ]
            except Exception as e:
                logger.warning("une_feed_parse_failed", url=url, error=str(e))
                return []

        tasks = [parse_feed(source.une_feed_url) for source in sources]
        if not tasks:
            return set()
            
        results = await asyncio.gather(*tasks)
        for guids in results:
            une_guids.update(guids)
            
        return une_guids

    async def _get_recent_contents(self, hours: int = 24) -> List[Content]:
        since = datetime.datetime.utcnow() - datetime.timedelta(hours=hours)
        stmt = (
            select(Content)
            .where(Content.published_at >= since)
            .options(selectinload(Content.source))
        )
        result = await self.session.execute(stmt)
        return list(result.scalars().all())
