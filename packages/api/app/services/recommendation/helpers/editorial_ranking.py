"""Helpers de classement par importance éditoriale.

Récence (paliers `ScoringWeights.RECENT_*`) et polarisation (`divergence_level`)
partagés entre `topic_selector` (Essentiel) et la projection per-user du digest
(`digest_selector::_project_editorial_for_user`). Source de vérité unique pour
que l'« importance éditoriale » se calcule à l'identique des deux côtés.

Cf. bug-actus-du-jour-ranking.md (Partie C).
"""

from __future__ import annotations

from datetime import UTC, datetime

from app.services.recommendation.scoring_config import ScoringWeights


def recency_bonus(published_at: datetime | None) -> float:
    """Bonus de fraîcheur hiérarchisé pour une date de publication.

    Mêmes paliers que `topic_selector._best_recency_bonus` (qui en dérive
    désormais). Retourne 0.0 pour une date absente ou > 168h.
    """
    if published_at is None:
        return 0.0

    published = published_at
    if published.tzinfo is None:
        published = published.replace(tzinfo=UTC)

    hours_old = (datetime.now(UTC) - published).total_seconds() / 3600

    if hours_old < 6:
        return ScoringWeights.RECENT_VERY_BONUS
    if hours_old < 24:
        return ScoringWeights.RECENT_BONUS
    if hours_old < 48:
        return ScoringWeights.RECENT_DAY_BONUS
    if hours_old < 72:
        return ScoringWeights.RECENT_YESTERDAY_BONUS
    if hours_old < 120:
        return ScoringWeights.RECENT_WEEK_BONUS
    if hours_old < 168:
        return ScoringWeights.RECENT_OLD_BONUS
    return 0.0


_POLARIZATION_BONUS: dict[str, float] = {
    "high": ScoringWeights.POLARIZATION_HIGH_BONUS,
    "medium": ScoringWeights.POLARIZATION_MEDIUM_BONUS,
}


def polarization_bonus(divergence_level: str | None) -> float:
    """Bonus d'importance dérivé de `divergence_level`.

    "high" → +12, "medium" → +6, "low"/"none"/None → 0. Aucun recalcul : le
    niveau est déjà porté par le subject (étape 1 via `compute_divergence_level`
    ou l'analyse LLM).
    """
    if not divergence_level:
        return 0.0
    return _POLARIZATION_BONUS.get(divergence_level.lower(), 0.0)
