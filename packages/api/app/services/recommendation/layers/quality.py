from app.services.recommendation.scoring_engine import BaseScoringLayer, ScoringContext
from app.models.content import Content
from app.models.enums import ReliabilityScore
from app.services.recommendation.scoring_config import ScoringWeights

class QualityLayer(BaseScoringLayer):
    """
    Encourage la consommation de sources fiables (FQS).
    Story 4.1:
    - High Reliability: Bonus (ScoringWeights.FQS_HIGH_BONUS)
    - Low Reliability: Malus (ScoringWeights.FQS_LOW_MALUS)
    """
    
    @property
    def name(self) -> str:
        return "quality"

    def score(self, content: Content, context: ScoringContext) -> float:
        score = 0.0
        
        if not content.source:
            return 0.0
            
        reliability = content.source.reliability_score
        
        # Bonus/Malus configuré centralement
        if reliability == ReliabilityScore.HIGH:
            score += ScoringWeights.FQS_HIGH_BONUS
            context.add_reason(content.id, self.name, ScoringWeights.FQS_HIGH_BONUS, "High reliability source")
            
        elif reliability == ReliabilityScore.MEDIUM:
            pass
            
        elif reliability == ReliabilityScore.LOW:
            score += ScoringWeights.FQS_LOW_MALUS
            context.add_reason(content.id, self.name, ScoringWeights.FQS_LOW_MALUS, "Low reliability source")
            
        return score
