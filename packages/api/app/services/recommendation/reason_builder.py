"""Reason Builder — Construit les raisons de recommandation depuis les résultats piliers.

Centralise la construction des labels pour "Pourquoi cet article ?".
Utilisé par le Feed et le Digest pour une cohérence des labels.
"""

from app.schemas.content import RecommendationReason, ScoreContribution
from app.services.recommendation.scoring_engine import PillarScoreResult


# Maximum de raisons affichées dans le breakdown
MAX_BREAKDOWN_ITEMS = 6


def build_recommendation_reason(result: PillarScoreResult) -> RecommendationReason:
    """Build a RecommendationReason from a PillarScoreResult.

    Args:
        result: Output of PillarScoringEngine.compute_score().

    Returns:
        RecommendationReason with label, score_total, and breakdown.
    """
    # Build breakdown list from contributions
    breakdown: list[ScoreContribution] = []
    for contrib in result.contributions:
        breakdown.append(
            ScoreContribution(
                label=contrib["label"],
                points=contrib["points"],
                is_positive=contrib["is_positive"],
                pillar=contrib["pillar"],
            )
        )

    # Sort by absolute contribution (highest first)
    breakdown.sort(key=lambda x: abs(x.points), reverse=True)

    # Limit to MAX_BREAKDOWN_ITEMS
    breakdown = breakdown[:MAX_BREAKDOWN_ITEMS]

    # Compute top label
    label = _compute_top_label(result, breakdown)

    return RecommendationReason(
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
        name: result.pillar_scores.get(name, 0.0) * ScoringWeights.PILLAR_WEIGHTS.get(name, 0.0)
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
            if top.label in ("Source suivie", "Source personnalisée", "Source appréciée"):
                return top.label

    return base_label
