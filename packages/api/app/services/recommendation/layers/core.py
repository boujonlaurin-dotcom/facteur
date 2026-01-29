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
        # Both source.theme and user_interests are guaranteed to be normalized slugs
        # Data alignment: sources_master.csv uses slugs (tech, society, etc.)
        if content.source and content.source.theme:
            # Direct comparison - no normalization needed (data is pre-aligned)
            if content.source.theme in context.user_interests:
                score += ScoringWeights.THEME_MATCH
                context.add_reason(
                    content.id,
                    self.name,
                    ScoringWeights.THEME_MATCH,
                    f"Thème: {content.source.theme}"
                )
        
        # 2. Source Affinity
        if content.source_id in context.followed_source_ids:
            score += ScoringWeights.TRUSTED_SOURCE
            context.add_reason(content.id, self.name, ScoringWeights.TRUSTED_SOURCE, "Source de confiance")
            
            # Bonus +10 pour les sources ajoutées manuellement
            if content.source_id in context.custom_source_ids:
                score += ScoringWeights.CUSTOM_SOURCE_BONUS
                context.add_reason(content.id, self.name, ScoringWeights.CUSTOM_SOURCE_BONUS, "Ta source personnalisée")
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
