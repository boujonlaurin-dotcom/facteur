"""UserCustomTopicLayer — Explicit Boost for Custom Topics (Epic 11).

Scores content based on user's custom topic profiles.
An article matches if:
1. Its topics[] array contains the custom topic's slug_parent, OR
2. One of the custom topic's keywords appears in the article title/description.

Score = CUSTOM_TOPIC_BASE_BONUS * priority_multiplier (max 1 match per article).
"""

from app.models.content import Content
from app.services.recommendation.scoring_config import ScoringWeights
from app.services.recommendation.scoring_engine import BaseScoringLayer, ScoringContext


class UserCustomTopicLayer(BaseScoringLayer):
    """Couche de scoring pour les Custom Topics suivis par l'utilisateur."""

    @property
    def name(self) -> str:
        return "user_custom_topic"

    def score(self, content: Content, context: ScoringContext) -> float:
        if not context.user_custom_topics:
            return 0.0

        # Normalize content topics for comparison
        content_topics = set()
        if content.topics:
            content_topics = {t.lower().strip() for t in content.topics if t}

        title_lower = (content.title or "").lower()
        desc_lower = (content.description or "").lower()

        best_score = 0.0
        best_topic_name = ""
        best_match_type = ""

        for topic_profile in context.user_custom_topics:
            matched = False
            match_type = ""

            # Match 1: slug_parent in content.topics
            if topic_profile.slug_parent in content_topics:
                matched = True
                match_type = "slug"

            # Match 2: keyword in title or description
            if not matched and topic_profile.keywords:
                for kw in topic_profile.keywords:
                    kw_lower = kw.lower().strip()
                    if not kw_lower:
                        continue
                    if kw_lower in title_lower or kw_lower in desc_lower:
                        matched = True
                        match_type = f"keyword:{kw}"
                        break

            if matched:
                topic_score = (
                    ScoringWeights.CUSTOM_TOPIC_BASE_BONUS
                    * topic_profile.priority_multiplier
                )
                if topic_score > best_score:
                    best_score = topic_score
                    best_topic_name = topic_profile.topic_name
                    best_match_type = match_type

        if best_score > 0:
            detail = f"Custom topic: {best_topic_name} ({best_match_type})"
            context.add_reason(content.id, self.name, best_score, detail)

        return best_score
