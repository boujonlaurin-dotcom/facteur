"""Tests unitaires pour PertinencePillar — Theme Mismatch Malus."""
from datetime import datetime
from unittest.mock import MagicMock
from uuid import uuid4

from app.services.recommendation.pillars.pertinence import PertinencePillar
from app.services.recommendation.scoring_config import ScoringWeights
from app.services.recommendation.scoring_engine import ScoringContext


class MockSource:
    def __init__(self, theme=None, secondary_themes=None):
        self.id = uuid4()
        self.theme = theme
        self.secondary_themes = secondary_themes or []


class MockContent:
    def __init__(self, theme=None, source_theme=None, topics=None):
        self.id = uuid4()
        self.title = "Test"
        self.description = ""
        self.theme = theme
        self.topics = topics or []
        self.source = MockSource(theme=source_theme)
        self.source_id = self.source.id
        self.published_at = datetime.now()
        self.content_type = None
        self.duration_seconds = None


def _context(
    user_interests=None, user_subtopics=None, user_custom_topics=None
):
    return ScoringContext(
        user_profile=MagicMock(id=uuid4()),
        user_interests=set(user_interests or []),
        user_interest_weights={},
        followed_source_ids=set(),
        user_prefs={},
        now=datetime.now(),
        user_subtopics=set(user_subtopics or []),
        user_subtopic_weights={},
        user_custom_topics=user_custom_topics or [],
    )


class TestThemeMismatchMalus:
    def test_malus_applied_when_no_match_and_user_has_preferences(self):
        """User a déclaré des thèmes, article ne matche aucun → malus appliqué."""
        content = MockContent(theme="sports", source_theme="sports")
        context = _context(user_interests={"tech", "science"})

        pillar = PertinencePillar()
        raw, contribs = pillar.compute_raw(content, context)

        assert raw == ScoringWeights.THEME_MISMATCH_MALUS
        mismatch_contribs = [c for c in contribs if c.label == "Thème non suivi"]
        assert len(mismatch_contribs) == 1
        assert mismatch_contribs[0].points == ScoringWeights.THEME_MISMATCH_MALUS
        assert mismatch_contribs[0].is_positive is False

    def test_no_malus_when_theme_matches(self):
        """Thème matche → pas de malus."""
        content = MockContent(theme="tech", source_theme="tech")
        context = _context(user_interests={"tech"})

        pillar = PertinencePillar()
        raw, contribs = pillar.compute_raw(content, context)

        assert raw >= ScoringWeights.THEME_MATCH
        assert not any(c.label == "Thème non suivi" for c in contribs)

    def test_no_malus_when_subtopic_matches(self):
        """Sous-thème matche → pas de malus, même si thème ne matche pas."""
        content = MockContent(theme="sports", source_theme="sports", topics=["ai"])
        context = _context(
            user_interests={"tech"}, user_subtopics={"ai"}
        )

        pillar = PertinencePillar()
        raw, contribs = pillar.compute_raw(content, context)

        assert raw > 0
        assert not any(c.label == "Thème non suivi" for c in contribs)

    def test_no_malus_on_cold_start(self):
        """Aucune préférence déclarée → aucun malus."""
        content = MockContent(theme="sports", source_theme="sports")
        context = _context()

        pillar = PertinencePillar()
        raw, contribs = pillar.compute_raw(content, context)

        assert raw == 0.0
        assert contribs == []

    def test_no_malus_when_custom_topic_matches(self):
        """Custom topic matche → pas de malus."""
        topic = MagicMock()
        topic.slug_parent = "ai"
        topic.keywords = []
        topic.topic_name = "IA"
        topic.priority_multiplier = 1.0

        content = MockContent(theme="sports", source_theme="sports", topics=["ai"])
        context = _context(user_interests={"tech"}, user_custom_topics=[topic])

        pillar = PertinencePillar()
        raw, contribs = pillar.compute_raw(content, context)

        assert raw > 0
        assert not any(c.label == "Thème non suivi" for c in contribs)

    def test_malus_normalized_to_zero_when_no_other_signal(self):
        """Un raw négatif est clampé à 0 par _normalize (pas d'exclusion dure)."""
        content = MockContent(theme="sports", source_theme="sports")
        context = _context(user_interests={"tech"})

        pillar = PertinencePillar()
        result = pillar.score(content, context)

        assert result.raw_score == ScoringWeights.THEME_MISMATCH_MALUS
        assert result.normalized_score == 0.0
