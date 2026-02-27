from app.models.content import Content
from app.services.recommendation.scoring_engine import BaseScoringLayer, ScoringContext


class BehavioralLayer(BaseScoringLayer):
    """
    Couche gérant le feedback comportemental.
    - Applique les poids dynamiques des intérêts (appris via consommation).
    """

    @property
    def name(self) -> str:
        return "behavioral"

    def _get_effective_theme(
        self, content: Content, context: ScoringContext
    ) -> str | None:
        """Détermine le thème effectif: content.theme > source.theme > secondary_themes."""
        # Tier 1: Article-level theme (ML-inferred)
        if (
            hasattr(content, "theme")
            and content.theme
            and content.theme in context.user_interests
        ):
            return content.theme
        # Tier 2: Source primary theme
        if content.source and content.source.theme in context.user_interests:
            return content.source.theme
        # Tier 3: Source secondary themes
        if content.source and getattr(content.source, "secondary_themes", None):
            matched = set(content.source.secondary_themes) & context.user_interests
            if matched:
                return sorted(matched)[0]
        return None

    def score(self, content: Content, context: ScoringContext) -> float:
        score = 0.0

        # 1. Interest Weight Bonus
        # CoreLayer donne le bonus thème. Ici on ajuste si weight > 1.0 ou < 1.0
        effective_theme = self._get_effective_theme(content, context)
        if effective_theme:
            weight = context.user_interest_weights.get(effective_theme, 1.0)

            if weight > 1.0:
                base_theme_score = 50.0
                bonus = base_theme_score * (weight - 1.0)
                score += bonus
                context.add_reason(
                    content.id,
                    self.name,
                    bonus,
                    f"High interest: {effective_theme} (x{weight:.1f})",
                )

            elif weight < 1.0:
                base_theme_score = 50.0
                malus = base_theme_score * (1.0 - weight)
                score -= malus
                context.add_reason(
                    content.id,
                    self.name,
                    -malus,
                    f"Low interest: {effective_theme} (x{weight:.1f})",
                )

        return score
