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

        # Use subtopic weights to scale the score
        # Base: TOPIC_MATCH per match. Weight > 1.0 amplifies, < 1.0 attenuates.
        weights = context.user_subtopic_weights
        matched_list = sorted(list(matches))[:match_count]
        score = 0.0
        boosted_topics = []
        for topic in matched_list:
            w = weights.get(topic, 1.0)
            score += ScoringWeights.TOPIC_MATCH * w
            if w > 1.0:
                boosted_topics.append(topic)

        # Bonus de précision : si le thème (article ou source) est dans les intérêts
        has_theme_match = False
        user_interests_lower = {s.lower().strip() for s in context.user_interests}

        # Tier 1: content.theme (ML-inferred, most precise)
        if hasattr(content, 'theme') and content.theme:
            if content.theme.lower().strip() in user_interests_lower:
                has_theme_match = True

        # Tier 2: source.theme (primary)
        if not has_theme_match and content.source and content.source.theme:
            if content.source.theme.lower().strip() in user_interests_lower:
                has_theme_match = True

        # Tier 3: source.secondary_themes
        if not has_theme_match and content.source and getattr(content.source, 'secondary_themes', None):
            secondary_set = {t.lower().strip() for t in content.source.secondary_themes}
            if secondary_set & user_interests_lower:
                has_theme_match = True

        if has_theme_match:
            score += ScoringWeights.SUBTOPIC_PRECISION_BONUS

        # Add reason for transparency/explainability
        detail = f"Topic match: {', '.join(matched_list)}"
        if has_theme_match:
            detail += " (précis)"
        if boosted_topics:
            detail += f" [liked: {', '.join(boosted_topics)}]"

        context.add_reason(
            content.id,
            self.name,
            score,
            detail
        )

        return score
