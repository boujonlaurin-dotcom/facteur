"""Pilier Fraîcheur — Mesure l'actualité du contenu.

Consolide : CoreLayer (recency decay), StaticPreferenceLayer (recency preference).
"""

import datetime

from app.models.content import Content
from app.services.recommendation.pillars.base import BasePillar, PillarContribution
from app.services.recommendation.scoring_config import ScoringWeights
from app.services.recommendation.scoring_engine import ScoringContext


class FraicheurPillar(BasePillar):
    """Mesure à quel point l'article est récent/d'actualité."""

    @property
    def name(self) -> str:
        return "fraicheur"

    @property
    def display_name(self) -> str:
        return "Actualité"

    @property
    def expected_max(self) -> float:
        return ScoringWeights.MAX_FRAICHEUR_RAW

    def compute_raw(
        self, content: Content, context: ScoringContext
    ) -> tuple[float, list[PillarContribution]]:
        score = 0.0
        contributions: list[PillarContribution] = []

        if not content.published_at:
            return 0.0, []

        # Ensure timezone-aware comparison
        published = content.published_at
        now = context.now
        if published.tzinfo is None:
            published = published.replace(tzinfo=datetime.UTC)
        if now.tzinfo is None:
            now = now.replace(tzinfo=datetime.UTC)

        delta = now - published
        hours_old = max(0, delta.total_seconds() / 3600)

        # --- 1. Recency Decay ---
        # Hyperbolic decay: 100 / (hours/24 + 1)
        # At 0h: 100, at 24h: 50, at 72h: 25
        recency_score = ScoringWeights.recency_base / (hours_old / 24.0 + 1.0)
        score += recency_score

        # Add human-readable recency label
        if hours_old < 6:
            label = "Très récent"
        elif hours_old < 24:
            label = "Récent"
        elif hours_old < 48:
            label = "Publié aujourd'hui"
        else:
            label = "Récence"

        contributions.append(PillarContribution(label=label, points=recency_score))

        # --- 2. Recency Preference (onboarding) ---
        recency_pref = context.user_prefs.get("content_recency")

        if recency_pref == "recent" and hours_old < 24:
            bonus = 15.0
            score += bonus
            contributions.append(
                PillarContribution(label="Préférence : contenu récent", points=bonus)
            )
        elif recency_pref == "timeless" and hours_old > 48:
            bonus = 10.0
            score += bonus
            contributions.append(
                PillarContribution(label="Préférence : contenu intemporel", points=bonus)
            )

        return score, contributions
