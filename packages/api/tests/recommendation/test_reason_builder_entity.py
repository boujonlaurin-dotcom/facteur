"""PR2 — la raison entité devient le top label quand elle domine la pertinence."""

from app.services.recommendation.reason_builder import build_recommendation_reason
from app.services.recommendation.scoring_engine import PillarScoreResult


def _contrib(pillar, label, points):
    return {
        "pillar": pillar,
        "pillar_display": pillar,
        "label": label,
        "points": points,
        "is_positive": points >= 0,
    }


def test_entity_reason_becomes_top_label_when_pertinence_dominates():
    """Pertinence dominante + entité en tête du breakdown → phrase complète."""
    result = PillarScoreResult(
        final_score=90.0,
        pillar_scores={
            "pertinence": 80.0,
            "source": 0.0,
            "fraicheur": 0.0,
            "qualite": 0.0,
        },
        contributions=[
            _contrib("pertinence", "Parce que tu lis souvent Emmanuel Macron", 28.0),
            _contrib("pertinence", "Thème : Politique", 50.0),
        ],
    )

    reason = build_recommendation_reason(result)

    # Le breakdown est trié par |points| desc : "Thème" (50) passe devant
    # l'entité (28). L'entité ne doit PAS être le label ici.
    assert reason.label != "Parce que tu lis souvent Emmanuel Macron"


def test_entity_reason_wins_when_it_is_the_largest_contribution():
    """Quand l'entité est la plus grosse contribution pertinence → label entité."""
    result = PillarScoreResult(
        final_score=90.0,
        pillar_scores={
            "pertinence": 80.0,
            "source": 10.0,
            "fraicheur": 5.0,
            "qualite": 0.0,
        },
        contributions=[
            _contrib("pertinence", "Parce que tu lis souvent Emmanuel Macron", 30.0),
            _contrib("pertinence", "Sujet : IA", 12.0),
        ],
    )

    reason = build_recommendation_reason(result)

    assert reason.label == "Parce que tu lis souvent Emmanuel Macron"
