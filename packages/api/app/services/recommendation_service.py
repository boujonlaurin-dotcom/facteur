import datetime
from typing import List, Optional, Set
from uuid import UUID

import structlog
from sqlalchemy import select, desc, func
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.content import Content, UserContentStatus
from app.models.source import Source, UserSource
from app.models.user import UserInterest, UserProfile
from app.models.enums import ContentStatus

logger = structlog.get_logger()

class RecommendationService:
    def __init__(self, session: AsyncSession):
        self.session = session

    async def get_feed(self, user_id: UUID, limit: int = 20, offset: int = 0, content_type: Optional[str] = None, saved_only: bool = False) -> List[Content]:
        """
        Génère un feed personnalisé pour l'utilisateur.
        
        Algorithme V1:
        1. Récupérer les candidats (contenus récents non vus, non masqués, NON SAUVEGARDÉS).
        2. Scorer chaque candidat (Thème + Source + Récence).
        3. Appliquer la pénalité de fatigue de source (Diversité).
        4. Trier et paginer.
        """
        # 1. Fetch user profile with interests and followed sources
        user_profile = await self.session.scalar(
            select(UserProfile)
            .options(selectinload(UserProfile.interests))
            .where(UserProfile.user_id == user_id)
        )
        
        followed_sources_result = await self.session.scalars(
            select(UserSource.source_id).where(UserSource.user_id == user_id)
        )
        followed_source_ids = set(followed_sources_result.all())
        
        user_interests = {i.interest_slug for i in user_profile.interests} if user_profile else set()
        
        if saved_only:
             # Fetch saved items directly
             stmt = (
                 select(UserContentStatus)
                 .options(selectinload(UserContentStatus.content).options(selectinload(Content.source)))
                 .where(
                     UserContentStatus.user_id == user_id,
                     UserContentStatus.is_saved == True
                 )
                 .order_by(desc(func.coalesce(UserContentStatus.saved_at, UserContentStatus.updated_at)))
                 .offset(offset)
                 .limit(limit)
             )
             
             statuses = await self.session.scalars(stmt)
             results = []
             for st in statuses:
                 content = st.content
                 # Populate transient fields
                 content.is_saved = True
                 content.is_hidden = st.is_hidden
                 content.hidden_reason = st.hidden_reason
                 content.status = st.status
                 results.append(content)
                 
             return results
        
        # 2. Get Candidates (Top 500 recent unseen contents)
        # 500 is heuristic to ensure we have enough diversity after scoring, 
        # but small enough to sort in memory quickly.
        candidates = await self._get_candidates(
            user_id, 
            limit_candidates=500,
            content_type=content_type
        )
        
        # 3. Score Candidates
        scored_candidates = []
        now = datetime.datetime.utcnow()
        
        for content in candidates:
            score = self._score_content(content, user_interests, followed_source_ids, now)
            scored_candidates.append((content, score))
            
        # 4. Sort by score DESC
        scored_candidates.sort(key=lambda x: x[1], reverse=True)
        
        # 4b. Diversity Re-ranking (Source Fatigue)
        # Apply a cumulative penalty for multiple items from the same source
        # to ensure a diverse top-of-feed.
        final_list = []
        source_counts = {}
        decay_factor = 0.85 # Each subsequent item from same source loses 15% score
        
        for content, base_score in scored_candidates:
             source_id = content.source_id
             count = source_counts.get(source_id, 0)
             
             # FinalScore = BaseScore * (decay_factor ^ count)
             final_score = base_score * (decay_factor ** count)
             
             final_list.append((content, final_score))
             source_counts[source_id] = count + 1
             
        # Sort again with diversity penalties applied to find the new Top-N
        final_list.sort(key=lambda x: x[1], reverse=True)
        
        # 5. Paginate
        scored_candidates = final_list
        start = offset
        end = offset + limit
        # Check bounds
        if start >= len(scored_candidates):
            return []
            
        result = [item[0] for item in scored_candidates[start:end]]
        
        # 6. Hydrate with User Status (is_saved, etc)
        content_ids = [c.id for c in result]
        if content_ids:
            # Fetch statuses for these contents
            stmt = select(UserContentStatus).where(
                UserContentStatus.user_id == user_id,
                UserContentStatus.content_id.in_(content_ids)
            )
            statuses = await self.session.scalars(stmt)
            status_map = {s.content_id: s for s in statuses}
            
            for content in result:
                st = status_map.get(content.id)
                # Attach temporary attributes for Pydantic serialization
                content.is_saved = st.is_saved if st else False
                content.is_hidden = st.is_hidden if st else False
                content.hidden_reason = st.hidden_reason if st else None
                content.status = st.status if st else ContentStatus.UNSEEN
        
        return result

    async def _get_candidates(self, user_id: UUID, limit_candidates: int, content_type: Optional[str] = None) -> List[Content]:
        """Récupère les N contenus les plus récents que l'utilisateur n'a pas encore vus/consommés et qui ne sont pas masqués."""
        from sqlalchemy import or_

        # Candidates to EXCLUDE:
        # 1. is_hidden == True
        # OR
        # 2. is_saved == True (Triaged to watch later)
        # OR
        # 3. status IN (SEEN, CONSUMED)
        
        exclude_query = select(UserContentStatus.content_id).where(
            UserContentStatus.user_id == user_id,
            or_(
                UserContentStatus.is_hidden == True,
                UserContentStatus.is_saved == True,
                UserContentStatus.status.in_([ContentStatus.SEEN, ContentStatus.CONSUMED])
            )
        )
        
        query = (
            select(Content)
            .options(selectinload(Content.source)) # CRITICAL: Eager load source for Theme access
            .where(Content.id.notin_(exclude_query))
        )
        
        # Apply content_type filter if provided
        if content_type:
             query = query.where(Content.content_type == content_type)
        
        query = (
            query
            .order_by(Content.published_at.desc())
            .limit(limit_candidates)
        )
        
        result = await self.session.scalars(query)
        return result.all()

    def _score_content(
        self, 
        content: Content, 
        user_interests: Set[str], 
        followed_source_ids: Set[UUID], 
        now: datetime.datetime
    ) -> float:
        """Calcule le score de pertinence d'un contenu."""
        score = 0.0
        
        # 1. Theme Match (+50)
        # content.source est loaded grâce au selectinload
        if content.source and content.source.theme in user_interests: 
             score += 50.0
        
        # 2. Source Affinity (Trusted: +30 vs Standard: +10)
        # "Following" a source makes it a trusted source in our model currently
        if content.source_id in followed_source_ids:
            score += 30.0
        else:
            score += 10.0
            
        # 3. Recency Decay (0-30)
        # Score = 30 / (hours_old/24 + 1)
        # Freshness bonus.
        if content.published_at:
            # Handle naive datetime -> assume UTC if naive for consistency with DB defaults
            published = content.published_at
            if published.tzinfo:
                 # convert to naive utc
                 published = published.replace(tzinfo=None)
            
            delta = now - published
            hours_old = max(0, delta.total_seconds() / 3600)
            recency_score = 30.0 / (hours_old / 24.0 + 1.0)
            score += recency_score
            
        return score
