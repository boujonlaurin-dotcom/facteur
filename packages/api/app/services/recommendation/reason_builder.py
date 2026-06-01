"""Reason Builder — Construit les raisons de recommandation depuis les résultats piliers.

Centralise la construction des labels pour "Pourquoi cet article ?".
Utilisé par le Feed et le Digest pour une cohérence des labels.
"""

from typing import Callable, TypeVar

from app.schemas.content import RecommendationReason, ScoreContribution
from app.schemas.digest import DigestRecommendationReason, DigestScoreBreakdown
from app.services.recommendation.scoring_engine import PillarScoreResult

# Maximum de raisons affichées dans le breakdown
MAX_BREAKDOWN_ITEMS = 6

_BreakdownItem = TypeVar("_BreakdownItem", ScoreContribution, DigestScoreBreakdown)


def _build_breakdown(
    result: PillarScoreResult,
    item_cls: Callable[..., _BreakdownItem],
) -> list[_BreakdownItem]:
    """Map pillar contributions to breakdown items, sorted by |points| then capped.

    Shared by the feed (:class:`ScoreContribution`) and digest
    (:class:`DigestScoreBreakdown`) builders — both schemas carry the same
    fields (``label`` / ``points`` / ``is_positive`` / ``pillar``), so only the
    target type differs.
    """
    breakdown = [
        item_cls(
            label=contrib["label"],
            points=contrib["points"],
            is_positive=contrib["is_positive"],
            pillar=contrib["pillar"],
        )
        for contrib in result.contributions
    ]
    breakdown.sort(key=lambda x: abs(x.points), reverse=True)
    return breakdown[:MAX_BREAKDOWN_ITEMS]


def build_recommendation_reason(result: PillarScoreResult) -> RecommendationReason:
    """Build a RecommendationReason from a PillarScoreResult.

    Args:
        result: Output of PillarScoringEngine.compute_score().

    Returns:
        RecommendationReason with label, score_total, and breakdown.
    """
    breakdown = _build_breakdown(result, ScoreContribution)

    # Compute top label
    label = _compute_top_label(result, breakdown)

    return RecommendationReason(
        label=label,
        score_total=result.final_score,
        breakdown=breakdown,
    )


def build_digest_recommendation_reason(
    result: PillarScoreResult,
) -> DigestRecommendationReason:
    """Build a DigestRecommendationReason from a PillarScoreResult.

    Digest counterpart of :func:`build_recommendation_reason`. The digest
    schemas (``DigestScoreBreakdown`` / ``DigestRecommendationReason``) carry
    the exact same fields as the feed ones (``label`` / ``points`` /
    ``is_positive`` / ``pillar``), so the mapping is identical — only the
    target type differs. Centralising it here keeps the "Pourquoi cet
    article ?" labels consistent between Feed and Digest.

    ``score_total`` is the engine's combined ``final_score`` (the breakdown
    is for transparency only and is not re-summed).
    """
    breakdown = _build_breakdown(result, DigestScoreBreakdown)

    # `_compute_top_label` only reads `.pillar` / `.label` on the breakdown
    # items and `result.pillar_scores`, so it works on DigestScoreBreakdown
    # as-is.
    label = _compute_top_label(result, breakdown)

    return DigestRecommendationReason(
        label=label,
        score_total=result.final_score,
        breakdown=breakdown,
    )


def _compute_top_label(
    result: PillarScoreResult, breakdown: list[ScoreContribution]
) -> str:
    """Determine the top-level label tag for the recommendation card."""
    # Find dominant pillar (highest normalized score * weight)
    from app.services.recommendation.scoring_config import ScoringWeights

    weighted_scores = {
        name: result.pillar_scores.get(name, 0.0)
        * ScoringWeights.PILLAR_WEIGHTS.get(name, 0.0)
        for name in ScoringWeights.PILLAR_WEIGHTS
    }
    dominant_pillar = max(weighted_scores, key=weighted_scores.get)

    # Default labels per pillar
    pillar_defaults = {
        "pertinence": "Vos centres d'intérêt",
        "source": "Source suivie",
        "fraicheur": "À la une",
        "qualite": "Article de qualité",
    }

    base_label = pillar_defaults.get(dominant_pillar, "Recommandé pour vous")

    # Enrich with specific info from top pertinence reason
    if dominant_pillar == "pertinence":
        pertinence_reasons = [r for r in breakdown if r.pillar == "pertinence"]
        if pertinence_reasons:
            top = pertinence_reasons[0]
            if "Sujet suivi :" in top.label:
                return top.label.replace("Sujet suivi : ", "Vos centres d'intérêt : ")
            if "Sujet :" in top.label:
                return top.label.replace("Sujet : ", "Vos centres d'intérêt : ")
            if "Thème :" in top.label:
                return top.label.replace("Thème : ", "Vos intérêts : ")
            if "Votre sujet :" in top.label:
                return top.label

    if dominant_pillar == "source":
        source_reasons = [r for r in breakdown if r.pillar == "source"]
        if source_reasons:
            top = source_reasons[0]
            if top.label in (
                "Source suivie",
                "Source personnalisée",
                "Source appréciée",
            ):
                return top.label

    return base_label
