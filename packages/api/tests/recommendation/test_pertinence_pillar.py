"""Tests unitaires pour PertinencePillar — Theme Mismatch Malus."""

from datetime import datetime
from unittest.mock import MagicMock
from uuid import uuid4

import pytest

from app.services.recommendation.pillars.pertinence import PertinencePillar
from app.services.recommendation.scoring_config import ScoringWeights
from app.services.recommendation.scoring_engine import ScoringContext


class MockSource:
    def __init__(self, theme=None, secondary_themes=None):
        self.id = uuid4()
        self.theme = theme
        self.secondary_themes = secondary_themes or []


class MockContent:
    def __init__(self, theme=None, source_theme=None, topics=None, entities=None):
        self.id = uuid4()
        self.title = "Test"
        self.description = ""
        self.theme = theme
        self.topics = topics or []
        self.entities = entities
        self.source = MockSource(theme=source_theme)
        self.source_id = self.source.id
        self.published_at = datetime.now()
        self.content_type = None
        self.duration_seconds = None


def _context(
    user_interests=None,
    user_subtopics=None,
    user_custom_topics=None,
    user_entity_affinity=None,
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
        user_entity_affinity=user_entity_affinity or {},
    )


def _entity(name, type_="PERSON"):
    """Build a content.entities item (JSON string, as stored by the classifier)."""
    import json

    return json.dumps({"name": name, "type": type_})


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
        context = _context(user_interests={"tech"}, user_subtopics={"ai"})

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


class TestSubtopicPositionWeighting:
    def test_primary_topic_scores_higher_than_secondary_topic(self):
        """A match at topics[0] should outrank the same match at topics[1]."""
        pillar = PertinencePillar()
        context = _context(user_subtopics={"ai"})

        primary = MockContent(topics=["ai", "climate"])
        secondary = MockContent(topics=["climate", "ai"])

        primary_score, _ = pillar._score_subtopics(primary, context)
        secondary_score, _ = pillar._score_subtopics(secondary, context)

        assert primary_score == pytest.approx(ScoringWeights.TOPIC_MATCH)
        assert secondary_score == pytest.approx(
            ScoringWeights.TOPIC_MATCH * ScoringWeights.SUBTOPIC_POSITION_FACTOR
        )
        assert primary_score > secondary_score

    def test_max_matches_keep_article_order_and_position_factor(self):
        """Only the first two matching topics count, with position decay."""
        pillar = PertinencePillar()
        content = MockContent(topics=["ai", "tech", "cybersecurity"])
        context = _context(user_subtopics={"ai", "tech", "cybersecurity"})

        score, contributions = pillar._score_subtopics(content, context)

        expected = ScoringWeights.TOPIC_MATCH * (
            1.0 + ScoringWeights.SUBTOPIC_POSITION_FACTOR
        )
        assert score == pytest.approx(expected)
        assert contributions[0].label == "Sujet : IA, Tech"


class TestEntityAffinity:
    """PR2 — bonus calibré pour les entités nommées lues souvent."""

    def test_bonus_equals_base_times_affinity_above_neutral(self):
        """bonus = BASE * (affinity - 1.0) pour une entité aimée."""
        pillar = PertinencePillar()
        content = MockContent(entities=[_entity("Emmanuel Macron")])
        context = _context(user_entity_affinity={"emmanuel macron": 2.0})

        bonus, contribs = pillar._score_entities(content, context)

        assert bonus == pytest.approx(ScoringWeights.ENTITY_AFFINITY_BASE * 1.0)
        assert len(contribs) == 1
        assert contribs[0].label == "Parce que tu lis souvent Emmanuel Macron"
        assert contribs[0].points == pytest.approx(bonus)

    def test_no_bonus_when_affinity_at_or_below_neutral(self):
        """Affinité <= 1.0 → aucun bonus, aucune raison."""
        pillar = PertinencePillar()
        content = MockContent(entities=[_entity("Emmanuel Macron")])
        context = _context(user_entity_affinity={"emmanuel macron": 1.0})

        bonus, contribs = pillar._score_entities(content, context)

        assert bonus == 0.0
        assert contribs == []

    def test_no_bonus_when_entity_not_in_affinity(self):
        """Entité présente dans l'article mais pas apprise → 0."""
        pillar = PertinencePillar()
        content = MockContent(entities=[_entity("Inconnu")])
        context = _context(user_entity_affinity={"emmanuel macron": 2.5})

        bonus, contribs = pillar._score_entities(content, context)

        assert bonus == 0.0
        assert contribs == []

    def test_bonus_capped_at_max(self):
        """Plusieurs entités très aimées → bonus plafonné à MAX_BONUS."""
        pillar = PertinencePillar()
        content = MockContent(entities=[_entity(f"Entité {i}") for i in range(5)])
        # 5 entités à affinité 3.0 → 5 * BASE * 2.0 = 80, capé à 30.
        affinity = {f"entité {i}": 3.0 for i in range(5)}
        context = _context(user_entity_affinity=affinity)

        bonus, contribs = pillar._score_entities(content, context)

        assert bonus == ScoringWeights.ENTITY_AFFINITY_MAX_BONUS
        assert contribs[0].label.startswith("Parce que tu lis souvent")

    def test_top_entity_is_highest_contributor(self):
        """La raison nomme l'entité au plus gros apport (casse live)."""
        pillar = PertinencePillar()
        content = MockContent(
            entities=[_entity("Petit Acteur"), _entity("Grand Sujet")]
        )
        context = _context(
            user_entity_affinity={"petit acteur": 1.2, "grand sujet": 2.8}
        )

        bonus, contribs = pillar._score_entities(content, context)

        assert contribs[0].label == "Parce que tu lis souvent Grand Sujet"

    def test_no_bonus_without_affinity_context(self):
        """Pas d'affinité chargée (cold start) → 0, même avec des entités."""
        pillar = PertinencePillar()
        content = MockContent(entities=[_entity("Emmanuel Macron")])
        context = _context()

        bonus, contribs = pillar._score_entities(content, context)

        assert bonus == 0.0
        assert contribs == []

    def test_compute_raw_includes_entity_bonus(self):
        """Le bonus entité est bien câblé dans compute_raw."""
        pillar = PertinencePillar()
        content = MockContent(entities=[_entity("Emmanuel Macron")])
        context = _context(user_entity_affinity={"emmanuel macron": 2.0})

        raw, contribs = pillar.compute_raw(content, context)

        assert raw == pytest.approx(ScoringWeights.ENTITY_AFFINITY_BASE * 1.0)
        assert any(
            c.label == "Parce que tu lis souvent Emmanuel Macron" for c in contribs
        )
