"""Base class for scoring pillars.

Each pillar scores articles independently on a 0-100 normalized scale,
then pillars are combined via configurable weights.
"""

from abc import ABC, abstractmethod
from dataclasses import dataclass, field

from app.models.content import Content
from app.services.recommendation.scoring_engine import ScoringContext


@dataclass
class PillarContribution:
    """A single scoring factor within a pillar."""

    label: str
    points: float
    is_positive: bool = True


@dataclass
class PillarResult:
    """Result of a pillar's scoring computation."""

    pillar_name: str
    raw_score: float
    normalized_score: float  # 0-100
    contributions: list[PillarContribution] = field(default_factory=list)


class BasePillar(ABC):
    """Abstract base class for a scoring pillar."""

    @property
    @abstractmethod
    def name(self) -> str:
        """Pillar identifier (e.g., 'pertinence', 'source')."""
        ...

    @property
    @abstractmethod
    def display_name(self) -> str:
        """French display name for UI grouping (e.g., 'Vos centres d\\'intérêt')."""
        ...

    @property
    @abstractmethod
    def expected_max(self) -> float:
        """Expected maximum raw score for normalization."""
        ...

    @abstractmethod
    def compute_raw(
        self, content: Content, context: ScoringContext
    ) -> tuple[float, list[PillarContribution]]:
        """Compute raw score and contributions for a content item.

        Returns:
            Tuple of (raw_score, list of contributions for explainability).
        """
        ...

    def score(self, content: Content, context: ScoringContext) -> PillarResult:
        """Compute normalized pillar score (0-100)."""
        raw, contributions = self.compute_raw(content, context)
        normalized = self._normalize(raw)
        return PillarResult(
            pillar_name=self.name,
            raw_score=raw,
            normalized_score=normalized,
            contributions=contributions,
        )

    def _normalize(self, raw: float) -> float:
        """Normalize raw score to 0-100 using soft cap."""
        if raw <= 0:
            return 0.0
        return min(raw / self.expected_max, 1.0) * 100.0
