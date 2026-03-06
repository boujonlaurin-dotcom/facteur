"""Pilier Source — Mesure la confiance et affinité avec la source.

Consolide : CoreLayer (source trust, affinity, priority), QualityLayer (reliability).
"""

from app.models.content import Content
from app.models.enums import ReliabilityScore
from app.services.recommendation.pillars.base import BasePillar, PillarContribution
from app.services.recommendation.scoring_config import ScoringWeights
from app.services.recommendation.scoring_engine import ScoringContext


class SourcePillar(BasePillar):
    """Mesure la confiance/qualité de la source de l'article."""

    @property
    def name(self) -> str:
        return "source"

    @property
    def display_name(self) -> str:
        return "Vos sources"

    @property
    def expected_max(self) -> float:
        return ScoringWeights.MAX_SOURCE_RAW

    def compute_raw(
        self, content: Content, context: ScoringContext
    ) -> tuple[float, list[PillarContribution]]:
        score = 0.0
        contributions: list[PillarContribution] = []

        # --- 1. Followed Source Trust ---
        if content.source_id in context.followed_source_ids:
            score += ScoringWeights.TRUSTED_SOURCE
            contributions.append(
                PillarContribution(
                    label="Source suivie", points=ScoringWeights.TRUSTED_SOURCE
                )
            )

            # Custom source bonus (manually added)
            if content.source_id in context.custom_source_ids:
                score += ScoringWeights.CUSTOM_SOURCE_BONUS
                contributions.append(
                    PillarContribution(
                        label="Source personnalisée",
                        points=ScoringWeights.CUSTOM_SOURCE_BONUS,
                    )
                )
        else:
            score += ScoringWeights.STANDARD_SOURCE

        # --- 2. Source Affinity (learned from interactions) ---
        affinity = context.source_affinity_scores.get(content.source_id, 0.0)
        if affinity > 0:
            affinity_bonus = affinity * ScoringWeights.SOURCE_AFFINITY_MAX_BONUS
            score += affinity_bonus
            contributions.append(
                PillarContribution(label="Source appréciée", points=affinity_bonus)
            )

        # --- 3. Source Reliability (FQS) ---
        if content.source:
            reliability = content.source.reliability_score
            if reliability == ReliabilityScore.HIGH:
                score += ScoringWeights.CURATED_SOURCE
                contributions.append(
                    PillarContribution(
                        label="Source qualitative", points=ScoringWeights.CURATED_SOURCE
                    )
                )
            elif reliability == ReliabilityScore.LOW:
                score += ScoringWeights.FQS_LOW_MALUS
                contributions.append(
                    PillarContribution(
                        label="Fiabilité basse",
                        points=ScoringWeights.FQS_LOW_MALUS,
                        is_positive=False,
                    )
                )

        # --- 4. Explicit Source Priority Multiplier ---
        source_multiplier = context.source_priority_multipliers.get(
            content.source_id, 1.0
        )
        if source_multiplier != 1.0:
            multiplier_delta = score * (source_multiplier - 1.0)
            score += multiplier_delta
            if source_multiplier > 1.0:
                contributions.append(
                    PillarContribution(label="Source favorite", points=multiplier_delta)
                )
            else:
                contributions.append(
                    PillarContribution(
                        label="Source réduite",
                        points=multiplier_delta,
                        is_positive=False,
                    )
                )

        return score, contributions
