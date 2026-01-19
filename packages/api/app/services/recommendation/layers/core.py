from typing import Set
from uuid import UUID
import datetime

from app.services.recommendation.scoring_engine import BaseScoringLayer, ScoringContext
from app.services.recommendation.scoring_config import ScoringWeights
from app.models.content import Content

class CoreLayer(BaseScoringLayer):
    """
    Couche de base reprenant la logique V1 :
    - Theme Match
    - Source Affinity
    - Recency Decay (Formule standard)
    """
    
    @property
    def name(self) -> str:
        return "core_v1"

    def score(self, content: Content, context: ScoringContext) -> float:
        score = 0.0
        
        # 1. Theme Match (Single Taxonomy)
        # Source theme is guaranteed to be a slug in DB (via import_sources.py)
        if content.source and content.source.theme:
            # Normalize source slug
            source_slug = content.source.theme.lower().strip()
            
            # Normalize user interests
            def _norm(s): return s.lower().strip() if s else ""
            user_interest_slugs = {_norm(s) for s in context.user_interests}
            
            if source_slug in user_interest_slugs:
                match_score = ScoringWeights.THEME_MATCH
                score += match_score
                context.add_reason(content.id, self.name, match_score, f"Theme match: {source_slug}")
        
        # 2. Source Affinity
        if content.source_id in context.followed_source_ids:
            score += ScoringWeights.FOLLOWED_SOURCE
            context.add_reason(content.id, self.name, ScoringWeights.FOLLOWED_SOURCE, "Followed source")
        else:
            score += ScoringWeights.STANDARD_SOURCE
            
        # 3. Recency Decay (Base)
        # Score = 30 / (hours_old/24 + 1)
        if content.published_at:
            published = content.published_at
            if published.tzinfo:
                published = published.replace(tzinfo=None)
            
            delta = context.now - published
            hours_old = max(0, delta.total_seconds() / 3600)
            
            # Formule V1
            recency_score = 30.0 / (hours_old / 24.0 + 1.0)
            score += recency_score
            
            # Diagnostic (optionnel, peut être verbeux)
            # context.add_reason(content.id, self.name, recency_score, f"Recency: {hours_old:.1f}h old")
            
        return score
