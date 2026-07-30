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
        # `tech` rendait « Tech » via une table de libellés périmée ; le libellé
        # canonique est « Technologie ». `ai` garde sa forme courte.
        assert contributions[0].label == "Sujet : IA, Technologie"


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


class TestCustomTopicEntityBranch:
    """PR1b2 — `canonical_name` matché contre `content.entities`.

    Le pilier ne lisait ni `content.entities` ni `canonical_name` : le pont
    entité n'existait que dans `layers/user_custom_topics`, une couche de recall
    qui ne s'applique pas aux surfaces scorées par piliers.
    """

    @staticmethod
    def _profile(**overrides):
        import types

        from app.models.enums import InterestState

        base = dict(
            topic_name="Kylian Mbappé",
            slug_parent="",
            keywords=[],
            entity_type="PERSON",
            canonical_name="Kylian Mbappé",
            priority_multiplier=1.0,
            state=InterestState.FOLLOWED,
            is_veille=False,
        )
        base.update(overrides)
        return types.SimpleNamespace(**base)

    def _score(self, content, profile):
        pillar = PertinencePillar()
        return pillar._score_custom_topics(
            content, _context(user_custom_topics=[profile])
        )

    def test_entity_match_scores_with_multiplier(self):
        content = MockContent(entities=[_entity("Kylian Mbappé")])

        score, contribs = self._score(content, self._profile())

        expected = (
            ScoringWeights.CUSTOM_TOPIC_BASE_BONUS
            * 1.0
            * ScoringWeights.ENTITY_MATCH_MULTIPLIER
        )
        assert score == pytest.approx(expected)
        assert contribs[0].label == "Votre sujet : Kylian Mbappé"

    def test_priority_multiplier_still_applies(self):
        content = MockContent(entities=[_entity("Kylian Mbappé")])

        score, _ = self._score(content, self._profile(priority_multiplier=2.0))

        assert score == pytest.approx(
            ScoringWeights.CUSTOM_TOPIC_BASE_BONUS
            * 2.0
            * ScoringWeights.ENTITY_MATCH_MULTIPLIER
        )

    def test_no_match_scores_zero(self):
        content = MockContent(entities=[_entity("Emmanuel Macron")])

        score, contribs = self._score(content, self._profile())

        assert score == 0.0
        assert contribs == []

    @pytest.mark.parametrize(
        "stored,followed",
        [
            ("kylian mbappé", "Kylian Mbappé"),
            ("KYLIAN MBAPPÉ", "kylian mbappé"),
            ("Kylian Mbappé", "  Kylian Mbappé  "),
        ],
    )
    def test_match_is_case_and_whitespace_insensitive(self, stored, followed):
        content = MockContent(entities=[_entity(stored)])

        score, _ = self._score(content, self._profile(canonical_name=followed))

        assert score > 0

    def test_plain_string_entity_is_tolerated(self):
        """`iter_entity_names` accepte une entité stockée hors JSON."""
        content = MockContent(entities=["Kylian Mbappé"])

        score, _ = self._score(content, self._profile())

        assert score > 0

    def test_no_entities_on_content_scores_zero(self):
        score, contribs = self._score(MockContent(entities=None), self._profile())

        assert score == 0.0
        assert contribs == []

    def test_profile_without_entity_type_ignores_branch(self):
        """Un Sujet classique ne doit pas matcher par entité."""
        content = MockContent(entities=[_entity("Kylian Mbappé")])

        score, _ = self._score(
            content, self._profile(entity_type=None, canonical_name=None)
        )

        assert score == 0.0

    def test_slug_and_entity_match_counted_once(self):
        """Garde `if not matched` : pas de double-compte sur un même profil."""
        content = MockContent(topics=["sport"], entities=[_entity("Kylian Mbappé")])

        score, contribs = self._score(content, self._profile(slug_parent="sport"))

        # Le slug matche d'abord → barème plat, sans la prime entité.
        assert score == pytest.approx(ScoringWeights.CUSTOM_TOPIC_BASE_BONUS)
        assert len(contribs) == 1

    def test_best_profile_wins_between_profiles(self):
        content = MockContent(entities=[_entity("Kylian Mbappé")])
        weak = self._profile(topic_name="Faible", priority_multiplier=1.0)
        strong = self._profile(topic_name="Fort", priority_multiplier=2.0)

        pillar = PertinencePillar()
        score, contribs = pillar._score_custom_topics(
            content, _context(user_custom_topics=[weak, strong])
        )

        assert contribs[0].label == "Votre sujet : Fort"
        assert score == pytest.approx(
            ScoringWeights.CUSTOM_TOPIC_BASE_BONUS
            * 2.0
            * ScoringWeights.ENTITY_MATCH_MULTIPLIER
        )


class TestSubtopicLabelInvariant:
    """PR1e — garde-fou contre la re-dérive de la table de libellés.

    Le pilier portait sa propre copie (`SUBTOPIC_LABELS`, 50 entrées) d'une
    taxonomie à 51 slugs : 32 clés fantômes et 33 slugs valides sans libellé,
    donc un `.capitalize()` anglais dans des raisons françaises. Elle est
    supprimée au profit de `SLUG_TO_LABEL` ; ces tests interdisent qu'une
    nouvelle divergence passe en silence.
    """

    def test_every_valid_slug_has_a_french_label(self):
        from app.services.ml.classification_service import (
            SLUG_TO_LABEL,
            VALID_TOPIC_SLUGS,
        )

        assert VALID_TOPIC_SLUGS - set(SLUG_TO_LABEL) == set()

    def test_no_label_for_an_unknown_slug(self):
        from app.services.ml.classification_service import (
            SLUG_TO_LABEL,
            VALID_TOPIC_SLUGS,
        )

        assert set(SLUG_TO_LABEL) - VALID_TOPIC_SLUGS == set()

    @pytest.mark.parametrize(
        "slug,expected",
        [
            ("energy", "Énergie"),
            ("politics", "Politique"),
            ("usa", "États-Unis"),
            ("environment", "Environnement"),
            ("inequality", "Inégalités sociales"),
            ("middleeast", "Moyen-Orient"),
        ],
    )
    def test_most_followed_slugs_render_in_french(self, slug, expected):
        """Ces slugs rendaient « Energy », « Politics », « Usa »…"""
        from app.services.recommendation.pillars.pertinence import _subtopic_label

        assert _subtopic_label(slug) == expected

    def test_unknown_slug_still_falls_back(self):
        from app.services.recommendation.pillars.pertinence import _subtopic_label

        assert _subtopic_label("slug-inexistant") == "Slug-inexistant"

    def test_short_label_overrides_are_valid_slugs(self):
        """La liste d'exceptions courtes ne doit pas devenir une 2e taxonomie."""
        from app.services.ml.classification_service import VALID_TOPIC_SLUGS
        from app.services.recommendation.pillars.pertinence import (
            _SHORT_SUBTOPIC_LABELS,
        )

        assert set(_SHORT_SUBTOPIC_LABELS) <= VALID_TOPIC_SLUGS

    def test_short_label_wins_over_canonical(self):
        from app.services.recommendation.pillars.pertinence import _subtopic_label

        assert _subtopic_label("ai") == "IA"
        assert _subtopic_label("space") == "Spatial"
