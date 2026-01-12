from app.services.recommendation.scoring_engine import BaseScoringLayer, ScoringContext
from app.models.content import Content

class BehavioralLayer(BaseScoringLayer):
    """
    Couche gérant le feedback comportemental.
    - Applique les poids dynamiques des intérêts (appris via consommation).
    """
    
    @property
    def name(self) -> str:
        return "behavioral"

    def score(self, content: Content, context: ScoringContext) -> float:
        score = 0.0
        
        # 1. Interest Weight Bonus
        # CoreLayer donne +50 si le thème est présent.
        # Ici on ajoute le "bonus" si weight > 1.0
        # Ex: Weight 1.2 -> Bonus = 50 * 0.2 = 10 points
        if content.source and content.source.theme in context.user_interests:
            weight = context.user_interest_weights.get(content.source.theme, 1.0)
            
            if weight > 1.0:
                base_theme_score = 50.0
                bonus = base_theme_score * (weight - 1.0)
                score += bonus
                context.add_reason(content.id, self.name, bonus, f"High interest: {content.source.theme} (x{weight:.1f})")
                
            elif weight < 1.0:
                # Malus si l'utilisateur semble se désintéresser (weight < 1.0)
                # On retire des points
                base_theme_score = 50.0
                malus = base_theme_score * (1.0 - weight)
                score -= malus
                context.add_reason(content.id, self.name, -malus, f"Low interest: {content.source.theme} (x{weight:.1f})")
                
        return score
