"""
ArticleTopicLayer - Topic-based scoring layer for Story 4.1d.

Scores content based on intersection of content.topics with user_subtopics.
"""

from app.services.recommendation.scoring_engine import BaseScoringLayer, ScoringContext
from app.services.recommendation.scoring_config import ScoringWeights
from app.models.content import Content


class ArticleTopicLayer(BaseScoringLayer):
    """
    Couche de scoring pour les topics granulaires (50-topics taxonomy).
    
    Score: +40 points par topic commun entre content.topics et user_subtopics.
    Maximum: 2 matches = 80 points.
    Bonus: +10 si le thème source est AUSSI matché (précision).
    
    This layer enables fine-grained personalization beyond broad themes,
    allowing users who prefer "AI" to see more AI content from tech sources.
    """
    
    @property
    def name(self) -> str:
        return "article_topic"

    def score(self, content: Content, context: ScoringContext) -> float:
        # Early return si pas de subtopics utilisateur ou pas de topics article
        if not context.user_subtopics or not content.topics:
            return 0.0
        
        # Normalize pour comparaison case-insensitive
        content_topics = {t.lower().strip() for t in content.topics if t}
        user_subtopics = {s.lower().strip() for s in context.user_subtopics}
        
        # Intersection des sets
        matches = content_topics & user_subtopics
        match_count = min(len(matches), ScoringWeights.TOPIC_MAX_MATCHES)
        
        if match_count == 0:
            return 0.0
        
        score = match_count * ScoringWeights.TOPIC_MATCH
        
        # Bonus de précision : si le thème source est AUSSI dans les intérêts utilisateur
        # Cela récompense une correspondance "thème + sous-thème" vs "sous-thème seul"
        has_theme_match = False
        if content.source and content.source.theme:
            source_theme = content.source.theme.lower().strip()
            user_interests = {s.lower().strip() for s in context.user_interests}
            if source_theme in user_interests:
                score += ScoringWeights.SUBTOPIC_PRECISION_BONUS
                has_theme_match = True
        
        # Add reason for transparency/explainability
        matched_list = sorted(list(matches))[:match_count]
        detail = f"Topic match: {', '.join(matched_list)}"
        if has_theme_match:
            detail += " (précis)"
        
        context.add_reason(
            content.id, 
            self.name, 
            score, 
            detail
        )
        
        return score
