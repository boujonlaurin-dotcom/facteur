"""UserCustomTopicLayer — Explicit Boost for Custom Topics (Epic 11).

Scores content based on user's custom topic profiles.
An article matches if:
1. Its topics[] array contains the custom topic's slug_parent, OR
2. One of the custom topic's keywords appears in the article title/description (word-boundary), OR
3. The custom topic's canonical_name matches an entity in the article's entities[].

Score = CUSTOM_TOPIC_BASE_BONUS * priority_multiplier (max 1 match per article).
Entity matches get a 1.5x multiplier bonus (precise match).
"""

import json
import re

from app.models.content import Content
from app.services.recommendation.scoring_config import ScoringWeights
from app.services.recommendation.scoring_engine import BaseScoringLayer, ScoringContext

ENTITY_MATCH_MULTIPLIER = 1.5


def _parse_content_entities(content: Content) -> list[dict]:
    """Parse JSON-string entities from Content.entities array."""
    if not content.entities:
        return []
    parsed: list[dict] = []
    for raw in content.entities:
        try:
            parsed.append(json.loads(raw))
        except (json.JSONDecodeError, TypeError):
            continue
    return parsed


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

        # Lazy-parse entities only if needed
        _content_entities: list[dict] | None = None

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

            # Match 2: keyword in title or description (word-boundary)
            if not matched and topic_profile.keywords:
                for kw in topic_profile.keywords:
                    kw_lower = kw.lower().strip()
                    if not kw_lower:
                        continue
                    pattern = r"\b" + re.escape(kw_lower) + r"\b"
                    if re.search(pattern, title_lower) or re.search(
                        pattern, desc_lower
                    ):
                        matched = True
                        match_type = f"keyword:{kw}"
                        break

            # Match 3: entity canonical_name in content.entities
            if (
                not matched
                and topic_profile.entity_type is not None
                and topic_profile.canonical_name is not None
            ):
                if _content_entities is None:
                    _content_entities = _parse_content_entities(content)
                canonical_lower = topic_profile.canonical_name.lower()
                for entity in _content_entities:
                    entity_name = entity.get("name", "")
                    if (
                        isinstance(entity_name, str)
                        and entity_name.lower() == canonical_lower
                    ):
                        matched = True
                        match_type = f"entity:{topic_profile.canonical_name}"
                        break

            if matched:
                multiplier = (
                    ENTITY_MATCH_MULTIPLIER if match_type.startswith("entity:") else 1.0
                )
                topic_score = (
                    ScoringWeights.CUSTOM_TOPIC_BASE_BONUS
                    * topic_profile.priority_multiplier
                    * multiplier
                )
                if topic_score > best_score:
                    best_score = topic_score
                    best_topic_name = topic_profile.topic_name
                    best_match_type = match_type

        if best_score > 0:
            detail = f"Custom topic: {best_topic_name} ({best_match_type})"
            context.add_reason(content.id, self.name, best_score, detail)

        return best_score
