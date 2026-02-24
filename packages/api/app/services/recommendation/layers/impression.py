"""Layer d'impression — pénalise les articles déjà affichés mais non cliqués."""

from app.services.recommendation.scoring_engine import BaseScoringLayer, ScoringContext
from app.services.recommendation.scoring_config import ScoringWeights
from app.models.content import Content


class ImpressionLayer(BaseScoringLayer):
    """
    Applique un malus temporel aux articles déjà affichés lors d'un refresh.

    Tiers (basés sur l'ancienneté de last_impressed_at) :
    - < 1h  : -100 pts (invisible après refresh)
    - < 24h : -70 pts  (très peu de chances de remonter)
    - < 48h : -40 pts  (remonte si très pertinent)
    - < 72h : -20 pts  (léger handicap)
    - > 72h : 0 pts    (entièrement récupéré)

    Si manually_impressed (option "j'ai déjà vu") : -120 pts permanent.
    """

    @property
    def name(self) -> str:
        return "impression"

    def score(self, content: Content, context: ScoringContext) -> float:
        if not hasattr(context, 'impression_data') or not context.impression_data:
            return 0.0

        data = context.impression_data.get(content.id)
        if data is None:
            return 0.0

        ts, is_manual = data

        # Manual "already seen" — permanent strong penalty
        if is_manual:
            context.add_reason(
                content.id, self.name,
                ScoringWeights.IMPRESSION_MANUAL,
                "Marqué comme déjà vu"
            )
            return ScoringWeights.IMPRESSION_MANUAL

        # Time-based tiered penalty
        hours = (context.now - ts).total_seconds() / 3600

        if hours < 1:
            penalty = ScoringWeights.IMPRESSION_VERY_RECENT
            label = "Affiché très récemment"
        elif hours < 24:
            penalty = ScoringWeights.IMPRESSION_RECENT
            label = f"Affiché il y a {int(hours)}h"
        elif hours < 48:
            penalty = ScoringWeights.IMPRESSION_DAY
            label = "Affiché hier"
        elif hours < 72:
            penalty = ScoringWeights.IMPRESSION_OLD
            label = "Affiché il y a 2-3j"
        else:
            return 0.0  # Fully recovered

        context.add_reason(content.id, self.name, penalty, label)
        return penalty
