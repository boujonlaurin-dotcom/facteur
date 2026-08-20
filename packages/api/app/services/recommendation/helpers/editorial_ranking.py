"""Helpers de classement par importance éditoriale et score mixte sujet.

Récence (paliers `ScoringWeights.RECENT_*`) et polarisation (`divergence_level`)
partagés entre `topic_selector` (Essentiel) et la projection per-user du digest
(`digest_selector::_project_editorial_for_user`). Source de vérité unique pour
que l'« importance éditoriale » se calcule à l'identique des deux côtés.

Le score mixte sujet (PR 4, bug-curation-essentiel-personnalisation) ramène
importance et personnalisation sur une échelle commune 0-100 puis les mélange :
`(1-w)·importance_100 + w·perso_100`, `w = ScoringWeights.SUBJECT_PERSO_WEIGHT`.
Les poids sont lus sur `ScoringWeights` **au call time** (jamais copiés au
niveau module — cf. le contre-exemple documenté `scoring_config.py`, bloc
SCORING_OVERRIDES) pour rester pilotables par override d'env sans redeploy.

Cf. bug-actus-du-jour-ranking.md (Partie C) et
bug-curation-essentiel-personnalisation.md (PR 4).
"""

from __future__ import annotations

from datetime import UTC, datetime

from app.services.recommendation.helpers.coverage_score import compute_coverage_score
from app.services.recommendation.scoring_config import ScoringWeights


def recency_bonus(published_at: datetime | None, now: datetime | None = None) -> float:
    """Bonus de fraîcheur hiérarchisé pour une date de publication.

    Mêmes paliers que `topic_selector._best_recency_bonus` (qui en dérive
    désormais). Retourne 0.0 pour une date absente ou > 168h. `now` fige la
    référence temporelle (rejeu déterministe des snapshots) ; par défaut,
    horloge courante.
    """
    if published_at is None:
        return 0.0

    published = published_at
    if published.tzinfo is None:
        published = published.replace(tzinfo=UTC)

    reference = now or datetime.now(UTC)
    hours_old = (reference - published).total_seconds() / 3600

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


def importance_raw_cap() -> float:
    """Maximum atteignable par `editorial_importance` — lu au call time.

    = COVERAGE_CAP + RECENT_VERY_BONUS + POLARIZATION_HIGH_BONUS (72
    aujourd'hui, jamais figé : un retuning des poids déplace le cap avec lui).
    """
    return (
        ScoringWeights.COVERAGE_CAP
        + ScoringWeights.RECENT_VERY_BONUS
        + ScoringWeights.POLARIZATION_HIGH_BONUS
    )


def editorial_importance(
    source_count: int,
    published_at: datetime | None,
    divergence_level: str | None,
    now: datetime | None = None,
) -> float:
    """Somme brute de l'importance éditoriale : couverture + récence + polarisation."""
    return (
        compute_coverage_score(source_count)
        + recency_bonus(published_at, now=now)
        + polarization_bonus(divergence_level)
    )


def normalized_importance(
    source_count: int,
    published_at: datetime | None,
    divergence_level: str | None,
    now: datetime | None = None,
) -> float:
    """Importance éditoriale projetée sur [0, 100] (0.0 si cap ≤ 0)."""
    cap = importance_raw_cap()
    if cap <= 0:
        return 0.0
    raw = editorial_importance(source_count, published_at, divergence_level, now=now)
    return min(100.0, max(0.0, 100.0 * raw / cap))


def normalized_perso(pillar_score: float | None, neutral: float = 0.0) -> float:
    """Score perso (moteur de piliers) clampé sur [0, 100], `None` → `neutral`.

    Le PenaltyPass peut produire du négatif (malus jusqu'à -80, aucun clamp
    moteur) — sûr ici : mutes/hidden sont déjà écartés en amont, le clamp ne
    fait que borner l'échelle du mélange.
    """
    value = neutral if pillar_score is None else pillar_score
    return min(100.0, max(0.0, value))


def mixed_subject_score(importance_100: float, perso_100: float) -> float:
    """Score mixte sujet : `(1-w)·importance + w·perso`, deux échelles 0-100.

    `w = ScoringWeights.SUBJECT_PERSO_WEIGHT`, lu au call time pour rester
    pilotable par `SCORING_OVERRIDES` (rollback sans redeploy).
    """
    w = ScoringWeights.SUBJECT_PERSO_WEIGHT
    return (1.0 - w) * importance_100 + w * perso_100
