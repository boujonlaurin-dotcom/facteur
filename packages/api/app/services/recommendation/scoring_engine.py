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
    """Moteur qui orchestre le calcul du score via plusieurs layers."""

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
