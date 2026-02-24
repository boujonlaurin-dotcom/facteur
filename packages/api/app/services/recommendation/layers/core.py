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

        # 1. Theme Match (3-tier: content.theme > source.theme > source.secondary_themes)
        # All themes and user_interests are normalized slugs (tech, society, etc.)
        theme_matched = False

        # Tier 1: Article-level theme (ML-inferred, most precise)
        if hasattr(content, 'theme') and content.theme:
            if content.theme in context.user_interests:
                score += ScoringWeights.THEME_MATCH
                context.add_reason(
                    content.id, self.name, ScoringWeights.THEME_MATCH,
                    f"Thème article: {content.theme}"
                )
                theme_matched = True

        # Tier 2: Source primary theme
        if not theme_matched and content.source and content.source.theme:
            if content.source.theme in context.user_interests:
                score += ScoringWeights.THEME_MATCH
                context.add_reason(
                    content.id, self.name, ScoringWeights.THEME_MATCH,
                    f"Thème: {content.source.theme}"
                )
                theme_matched = True

        # Tier 3: Source secondary themes (bonus réduit à 70% du principal)
        if not theme_matched and content.source and getattr(content.source, 'secondary_themes', None):
            matched_secondary = set(content.source.secondary_themes) & context.user_interests
            if matched_secondary:
                secondary_bonus = ScoringWeights.THEME_MATCH * ScoringWeights.SECONDARY_THEME_FACTOR
                matched_theme = sorted(matched_secondary)[0]
                score += secondary_bonus
                context.add_reason(
                    content.id, self.name, secondary_bonus,
                    f"Thème secondaire: {matched_theme}"
                )
                theme_matched = True
        
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

        # 2b. Source Affinity Bonus (learned from interactions)
        affinity = context.source_affinity_scores.get(content.source_id, 0.0)
        if affinity > 0:
            affinity_bonus = affinity * ScoringWeights.SOURCE_AFFINITY_MAX_BONUS
            score += affinity_bonus
            context.add_reason(
                content.id, self.name, affinity_bonus,
                f"Affinité source: {affinity:.0%}"
            )

        # 3. Recency Decay (Base)
        # Score = 30 / (hours_old/24 + 1)
        if content.published_at:
            published = content.published_at
            now = context.now
            
            # Ensure both datetimes are timezone-aware for comparison
            if published.tzinfo is None:
                published = published.replace(tzinfo=datetime.timezone.utc)
            if now.tzinfo is None:
                now = now.replace(tzinfo=datetime.timezone.utc)
            
            delta = now - published
            hours_old = max(0, delta.total_seconds() / 3600)
            
            # Formule V1
            recency_score = 30.0 / (hours_old / 24.0 + 1.0)
            score += recency_score
            
            # Diagnostic (optionnel, peut être verbeux)
            # context.add_reason(content.id, self.name, recency_score, f"Recency: {hours_old:.1f}h old")
            
        return score
