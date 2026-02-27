from app.models.content import Content
from app.services.recommendation.scoring_config import ScoringWeights
from app.services.recommendation.scoring_engine import BaseScoringLayer, ScoringContext


class ContentQualityLayer(BaseScoringLayer):
    """
    Booste les contenus avec du texte riche pour la lecture in-app.

    Articles avec content_quality='full' (>500 chars) reçoivent un boost,
    'partial' (100-500 chars) un boost réduit, 'none' ou NULL aucun boost.
    """

    @property
    def name(self) -> str:
        return "content_quality"

    def score(self, content: Content, context: ScoringContext) -> float:
        score = 0.0
        quality = getattr(content, "content_quality", None)

        if quality == "full":
            score += ScoringWeights.CONTENT_QUALITY_FULL_BOOST
            context.add_reason(
                content.id,
                self.name,
                ScoringWeights.CONTENT_QUALITY_FULL_BOOST,
                "Rich content for in-app reading",
            )
        elif quality == "partial":
            score += ScoringWeights.CONTENT_QUALITY_PARTIAL_BOOST
            context.add_reason(
                content.id,
                self.name,
                ScoringWeights.CONTENT_QUALITY_PARTIAL_BOOST,
                "Partial content available",
            )

        return score
