from app.services.recommendation.scoring_engine import BaseScoringLayer, ScoringContext
from app.models.content import Content
from app.services.recommendation.scoring_config import ScoringWeights

class VisualLayer(BaseScoringLayer):
    """
    Booste les contenus avec des images affichables.
    """
    
    @property
    def name(self) -> str:
        return "visual"

    def score(self, content: Content, context: ScoringContext) -> float:
        score = 0.0
        
        # Boost si une vignette est présente
        if content.thumbnail_url and content.thumbnail_url.strip():
            score += ScoringWeights.IMAGE_BOOST
            context.add_reason(content.id, self.name, ScoringWeights.IMAGE_BOOST, "Content with thumbnail")
            
        return score
