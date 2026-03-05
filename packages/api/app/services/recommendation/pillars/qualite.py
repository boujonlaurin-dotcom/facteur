"""Pilier Qualité — Mesure la qualité du contenu pour la lecture in-app.

Consolide : VisualLayer (thumbnail), ContentQualityLayer (texte), QualityLayer (curated).
"""

from app.models.content import Content
from app.services.recommendation.pillars.base import BasePillar, PillarContribution
from app.services.recommendation.scoring_config import ScoringWeights
from app.services.recommendation.scoring_engine import ScoringContext


class QualitePillar(BasePillar):
    """Mesure la qualité de lecture de l'article dans Facteur."""

    @property
    def name(self) -> str:
        return "qualite"

    @property
    def display_name(self) -> str:
        return "Qualité du contenu"

    @property
    def expected_max(self) -> float:
        return ScoringWeights.MAX_QUALITE_RAW

    def compute_raw(
        self, content: Content, context: ScoringContext
    ) -> tuple[float, list[PillarContribution]]:
        score = 0.0
        contributions: list[PillarContribution] = []

        # --- 1. Thumbnail Presence ---
        if content.thumbnail_url and content.thumbnail_url.strip():
            score += ScoringWeights.IMAGE_BOOST
            contributions.append(
                PillarContribution(
                    label="Aperçu disponible", points=ScoringWeights.IMAGE_BOOST
                )
            )

        # --- 2. Content Quality (in-app readability) ---
        quality = getattr(content, "content_quality", None)
        if quality == "full":
            score += ScoringWeights.CONTENT_QUALITY_FULL_BOOST
            contributions.append(
                PillarContribution(
                    label="Lecture complète dans Facteur",
                    points=ScoringWeights.CONTENT_QUALITY_FULL_BOOST,
                )
            )
        elif quality == "partial":
            score += ScoringWeights.CONTENT_QUALITY_PARTIAL_BOOST
            contributions.append(
                PillarContribution(
                    label="Lecture partielle disponible",
                    points=ScoringWeights.CONTENT_QUALITY_PARTIAL_BOOST,
                )
            )

        # --- 3. Curated Source (editorial quality signal) ---
        if content.source and getattr(content.source, "is_curated", False):
            score += ScoringWeights.CURATED_SOURCE
            contributions.append(
                PillarContribution(
                    label="Source éditorialisée", points=ScoringWeights.CURATED_SOURCE
                )
            )

        return score, contributions
