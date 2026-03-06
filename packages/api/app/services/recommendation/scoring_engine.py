import datetime
from abc import ABC, abstractmethod
from typing import Any
from uuid import UUID

import structlog

from app.models.content import Content
from app.models.user import UserProfile

logger = structlog.get_logger()


class ScoringContext:
    """Contexte passé à toutes les couches de scoring."""

    def __init__(
        self,
        user_profile: UserProfile,
        user_interests: set[str],
        user_interest_weights: dict[str, float],
        followed_source_ids: set[UUID],
        user_prefs: dict[str, Any],
        now: datetime.datetime,
        user_subtopics: set[str] = None,
        user_subtopic_weights: dict[str, float] = None,
        # Story 4.7: Personalization
        muted_sources: set[UUID] = None,
        muted_themes: set[str] = None,
        muted_topics: set[str] = None,
        muted_content_types: set[str] = None,
        custom_source_ids: set[UUID] = None,
        source_affinity_scores: dict[UUID, float] = None,
        # Feed Refresh: impression data {content_id: (timestamp, is_manual)}
        impression_data: dict[UUID, tuple] = None,
        # Epic 11: Custom Topics
        user_custom_topics: list = None,
        # Source Weighting: explicit priority multipliers {source_id: 0.5|1.0|2.0}
        source_priority_multipliers: dict[UUID, float] = None,
    ):
        self.user_profile = user_profile
        self.user_interests = user_interests
        self.user_interest_weights = user_interest_weights
        self.followed_source_ids = followed_source_ids
        self.custom_source_ids = custom_source_ids or set()
        self.source_affinity_scores = source_affinity_scores or {}
        self.user_prefs = user_prefs
        self.now = now
        self.user_subtopics = user_subtopics or set()
        self.user_subtopic_weights = user_subtopic_weights or {}

        # Story 4.7: Personalization malus
        self.muted_sources = muted_sources or set()
        self.muted_themes = muted_themes or set()
        self.muted_topics = muted_topics or set()
        self.muted_content_types = muted_content_types or set()

        # Feed Refresh: {content_id: (last_impressed_at, manually_impressed)}
        self.impression_data = impression_data or {}

        # Epic 11: Custom Topics
        self.user_custom_topics = user_custom_topics or []

        # Source Weighting: explicit priority multipliers
        self.source_priority_multipliers = source_priority_multipliers or {}

        # Diagnostics pour explicabilité
        self.reasons: dict[UUID, dict[str, Any]] = {}

    def add_reason(self, content_id: UUID, layer: str, score: float, details: str):
        if content_id not in self.reasons:
            self.reasons[content_id] = []
        self.reasons[content_id].append(
            {"layer": layer, "score_contribution": score, "details": details}
        )


class BaseScoringLayer(ABC):
    """Interface pour une couche de scoring."""

    @property
    @abstractmethod
    def name(self) -> str:
        pass

    @abstractmethod
    def score(self, content: Content, context: ScoringContext) -> float:
        """Retourne un score additif pour ce contenu."""
        pass


class ScoringEngine:
    """Moteur qui orchestre le calcul du score via plusieurs layers (v1 — legacy)."""

    def __init__(self, layers: list[BaseScoringLayer]):
        self.layers = layers

    def compute_score(self, content: Content, context: ScoringContext) -> float:
        total_score = 0.0

        for layer in self.layers:
            try:
                layer_score = layer.score(content, context)
                total_score += layer_score

                # Optionnel: log debug si score significatif
                # if abs(layer_score) > 0.1:
                #     context.add_reason(content.id, layer.name, layer_score, "")

            except Exception as e:
                logger.error(
                    "start_scoring_layer_error", layer=layer.name, error=str(e)
                )
                # On ne bloque pas tout le scoring pour une erreur de layer
                continue

        return total_score


# ---------------------------------------------------------------------------
# Pillar-based scoring engine (v2)
# ---------------------------------------------------------------------------
from dataclasses import dataclass


@dataclass
class PillarScoreResult:
    """Résultat complet du scoring par piliers pour un article."""

    final_score: float  # Score combiné (0-100 base + pénalités)
    pillar_scores: dict[str, float]  # {pillar_name: normalized_score}
    contributions: list[dict[str, Any]]  # Flat list for reason hydration


class PillarScoringEngine:
    """Moteur v2 qui orchestre le scoring par piliers normalisés.

    Architecture:
    1. Chaque pilier score indépendamment (normalisé 0-100)
    2. Combinaison pondérée des piliers
    3. Application des pénalités absolues (mutes, impressions)

    Le score final est sur une échelle ~0-100 (peut aller en négatif avec pénalités).
    """

    def __init__(self):
        # Lazy imports to avoid circular deps at module level
        from app.services.recommendation.pillars import (
            FraicheurPillar,
            PenaltyPass,
            PertinencePillar,
            QualitePillar,
            SourcePillar,
        )
        from app.services.recommendation.scoring_config import ScoringWeights

        self.pillars = [
            PertinencePillar(),
            SourcePillar(),
            FraicheurPillar(),
            QualitePillar(),
        ]
        self.penalty_pass = PenaltyPass()
        self.weights = ScoringWeights.PILLAR_WEIGHTS

    def compute_score(
        self, content: Content, context: ScoringContext
    ) -> PillarScoreResult:
        """Compute pillar-based score for a content item."""
        pillar_scores: dict[str, float] = {}
        all_contributions: list[dict[str, Any]] = []

        # Score each pillar
        for pillar in self.pillars:
            try:
                result = pillar.score(content, context)
                pillar_scores[pillar.name] = result.normalized_score

                for contrib in result.contributions:
                    all_contributions.append(
                        {
                            "pillar": pillar.name,
                            "pillar_display": pillar.display_name,
                            "label": contrib.label,
                            "points": contrib.points,
                            "is_positive": contrib.is_positive,
                        }
                    )
            except Exception as e:
                logger.error(
                    "pillar_scoring_error", pillar=pillar.name, error=str(e)
                )
                pillar_scores[pillar.name] = 0.0

        # Weighted combination
        base_score = sum(
            pillar_scores.get(name, 0.0) * weight
            for name, weight in self.weights.items()
        )

        # Apply penalties
        try:
            penalty_score, penalty_contribs = self.penalty_pass.compute(
                content, context
            )
            for contrib in penalty_contribs:
                all_contributions.append(
                    {
                        "pillar": self.penalty_pass.name,
                        "pillar_display": self.penalty_pass.display_name,
                        "label": contrib.label,
                        "points": contrib.points,
                        "is_positive": contrib.is_positive,
                    }
                )
        except Exception as e:
            logger.error("penalty_pass_error", error=str(e))
            penalty_score = 0.0

        final_score = base_score + penalty_score

        return PillarScoreResult(
            final_score=final_score,
            pillar_scores=pillar_scores,
            contributions=all_contributions,
        )
