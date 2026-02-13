"""
Tests unitaires pour CoreLayer - Theme Matching (Phase 1 + Phase 2 diversité)
"""
import pytest
from datetime import datetime, timedelta
from uuid import uuid4
from unittest.mock import MagicMock

from app.services.recommendation.layers.core import CoreLayer
from app.services.recommendation.scoring_engine import ScoringContext
from app.services.recommendation.scoring_config import ScoringWeights


class MockSource:
    """Mock Source pour les tests."""
    def __init__(self, theme: str = None, id=None, secondary_themes=None):
        self.theme = theme
        self.id = id or uuid4()
        self.secondary_themes = secondary_themes


class MockContent:
    """Mock Content pour les tests."""
    def __init__(
        self,
        source_theme: str = None,
        source_id=None,
        published_at=None,
        secondary_themes=None,
        theme=None,
    ):
        self.id = uuid4()
        self.theme = theme  # Article-level ML theme
        self.source = MockSource(
            theme=source_theme, id=source_id,
            secondary_themes=secondary_themes
        ) if source_theme is not None else None
        self.source_id = source_id if source_id else (self.source.id if self.source else None)
        self.published_at = published_at or datetime.now()


class TestCoreLayerThemeMatching:
    """Tests pour le matching de thèmes dans CoreLayer."""

    def create_context(self, user_interests=None, followed_sources=None, custom_sources=None):
        """Helper pour créer un ScoringContext de test."""
        user_profile = MagicMock()
        user_profile.id = uuid4()

        return ScoringContext(
            user_profile=user_profile,
            user_interests=set(user_interests or []),
            user_interest_weights={},
            followed_source_ids=set(followed_sources or []),
            user_prefs={},
            now=datetime.now(),
            user_subtopics=set(),
            custom_source_ids=set(custom_sources or [])
        )

    def test_theme_match_with_aligned_taxonomy(self):
        """Vérifie que le matching fonctionne quand les données sont alignées (slugs)."""
        content = MockContent(source_theme="tech")
        context = self.create_context(user_interests={"tech", "science"})
        layer = CoreLayer()

        score = layer.score(content, context)

        assert score >= ScoringWeights.THEME_MATCH
        assert content.id in context.reasons
        reasons = context.reasons[content.id]
        theme_reasons = [r for r in reasons if "Thème" in r.get("details", "")]
        assert len(theme_reasons) == 1
        assert theme_reasons[0]["details"] == "Thème: tech"
        assert theme_reasons[0]["score_contribution"] == ScoringWeights.THEME_MATCH

    def test_theme_match_multiple_interests(self):
        """Vérifie le matching quand plusieurs intérêts sont présents."""
        content = MockContent(source_theme="society")
        context = self.create_context(user_interests={"tech", "society", "economy"})
        layer = CoreLayer()

        score = layer.score(content, context)

        assert score >= ScoringWeights.THEME_MATCH
        reasons = context.reasons.get(content.id, [])
        theme_reasons = [r for r in reasons if "Thème: society" in r.get("details", "")]
        assert len(theme_reasons) == 1

    def test_no_match_different_themes(self):
        """Vérifie qu'il n'y a pas de match quand les thèmes diffèrent."""
        content = MockContent(source_theme="sports")
        context = self.create_context(user_interests={"tech", "science"})
        layer = CoreLayer()

        score = layer.score(content, context)

        assert score >= ScoringWeights.STANDARD_SOURCE
        assert score < ScoringWeights.STANDARD_SOURCE + 40
        reasons = context.reasons.get(content.id, [])
        theme_reasons = [r for r in reasons if "Thème" in r.get("details", "")]
        assert len(theme_reasons) == 0

    def test_no_match_empty_interests(self):
        """Vérifie le comportement quand l'utilisateur n'a pas d'intérêts."""
        content = MockContent(source_theme="tech")
        context = self.create_context(user_interests=set())
        layer = CoreLayer()

        score = layer.score(content, context)

        assert score < ScoringWeights.THEME_MATCH
        reasons = context.reasons.get(content.id, [])
        theme_reasons = [r for r in reasons if "Thème" in r.get("details", "")]
        assert len(theme_reasons) == 0

    def test_no_match_none_theme(self):
        """Vérifie le comportement quand la source n'a pas de thème."""
        content = MockContent(source_theme=None)
        context = self.create_context(user_interests={"tech"})
        layer = CoreLayer()

        score = layer.score(content, context)

        assert score >= ScoringWeights.STANDARD_SOURCE
        assert score < ScoringWeights.STANDARD_SOURCE + 40

    def test_all_valid_themes_matching(self):
        """Test exhaustif de tous les thèmes valides."""
        valid_themes = ["tech", "society", "environment", "economy",
                       "politics", "culture", "science", "international"]

        layer = CoreLayer()

        for theme in valid_themes:
            content = MockContent(source_theme=theme)
            context = self.create_context(user_interests={theme})

            score = layer.score(content, context)

            assert score >= ScoringWeights.THEME_MATCH, f"Theme {theme} should match"
            reasons = context.reasons.get(content.id, [])
            theme_reasons = [r for r in reasons if f"Thème: {theme}" in r.get("details", "")]
            assert len(theme_reasons) == 1, f"Theme {theme} should have a reason"

    def test_theme_match_with_followed_source(self):
        """Vérifie le cumul du bonus thème + source suivie."""
        source_id = uuid4()
        content = MockContent(source_theme="tech", source_id=source_id)
        context = self.create_context(
            user_interests={"tech"},
            followed_sources={source_id}
        )
        layer = CoreLayer()

        score = layer.score(content, context)

        expected_min = ScoringWeights.THEME_MATCH + ScoringWeights.TRUSTED_SOURCE
        assert score >= expected_min

        reasons = context.reasons.get(content.id, [])
        details = [r.get("details", "") for r in reasons]
        assert any("Thème" in d for d in details)
        assert any("confiance" in d for d in details)

    def test_theme_match_rate_calculation(self):
        """Calcule le taux de matching sur un échantillon."""
        layer = CoreLayer()
        user_interests = {"tech", "society", "science"}
        context = self.create_context(user_interests=user_interests)

        test_cases = [
            MockContent(source_theme="tech"),
            MockContent(source_theme="society"),
            MockContent(source_theme="science"),
            MockContent(source_theme="economy"),
            MockContent(source_theme="culture"),
            MockContent(source_theme="tech"),
            MockContent(source_theme="politics"),
            MockContent(source_theme="tech"),
            MockContent(source_theme="environment"),
            MockContent(source_theme="society"),
        ]

        matches = 0
        for content in test_cases:
            layer.score(content, context)
            reasons = context.reasons.get(content.id, [])
            if any("Thème" in r.get("details", "") for r in reasons):
                matches += 1

        match_rate = matches / len(test_cases)
        assert match_rate >= 0.5, f"Match rate {match_rate} should be >= 50%"


class TestCoreLayerSecondaryThemes:
    """Tests Phase 1: Secondary theme matching."""

    def create_context(self, user_interests=None, followed_sources=None, custom_sources=None):
        user_profile = MagicMock()
        user_profile.id = uuid4()
        return ScoringContext(
            user_profile=user_profile,
            user_interests=set(user_interests or []),
            user_interest_weights={},
            followed_source_ids=set(followed_sources or []),
            user_prefs={},
            now=datetime.now(),
            user_subtopics=set(),
            custom_source_ids=set(custom_sources or [])
        )

    def test_secondary_theme_match(self):
        """Source international avec secondary tech → match tech users à 70%."""
        content = MockContent(
            source_theme="international",
            secondary_themes=["tech", "economy"]
        )
        context = self.create_context(user_interests={"tech"})
        layer = CoreLayer()

        score = layer.score(content, context)

        expected_secondary = ScoringWeights.THEME_MATCH * ScoringWeights.SECONDARY_THEME_FACTOR
        reasons = context.reasons.get(content.id, [])
        secondary_reasons = [r for r in reasons if "secondaire" in r.get("details", "")]
        assert len(secondary_reasons) == 1
        assert secondary_reasons[0]["score_contribution"] == pytest.approx(expected_secondary)

    def test_primary_takes_precedence_over_secondary(self):
        """Le thème principal doit avoir priorité sur le secondaire."""
        content = MockContent(
            source_theme="tech",
            secondary_themes=["science", "economy"]
        )
        context = self.create_context(user_interests={"tech", "science"})
        layer = CoreLayer()

        score = layer.score(content, context)

        reasons = context.reasons.get(content.id, [])
        # Doit avoir un match primary "Thème: tech", pas "Thème secondaire"
        primary_reasons = [r for r in reasons if r.get("details", "") == "Thème: tech"]
        secondary_reasons = [r for r in reasons if "secondaire" in r.get("details", "")]
        assert len(primary_reasons) == 1
        assert len(secondary_reasons) == 0

    def test_secondary_themes_null(self):
        """secondary_themes=None → pas de crash, comportement inchangé."""
        content = MockContent(source_theme="sports", secondary_themes=None)
        context = self.create_context(user_interests={"tech"})
        layer = CoreLayer()

        score = layer.score(content, context)

        reasons = context.reasons.get(content.id, [])
        theme_reasons = [r for r in reasons if "Thème" in r.get("details", "")]
        assert len(theme_reasons) == 0

    def test_secondary_themes_empty(self):
        """secondary_themes=[] → pas de match secondaire."""
        content = MockContent(source_theme="international", secondary_themes=[])
        context = self.create_context(user_interests={"tech"})
        layer = CoreLayer()

        score = layer.score(content, context)

        reasons = context.reasons.get(content.id, [])
        secondary_reasons = [r for r in reasons if "secondaire" in r.get("details", "")]
        assert len(secondary_reasons) == 0

    def test_secondary_only_one_bonus(self):
        """Même si plusieurs secondaires matchent, un seul bonus est donné."""
        content = MockContent(
            source_theme="international",
            secondary_themes=["tech", "science", "economy"]
        )
        context = self.create_context(user_interests={"tech", "science", "economy"})
        layer = CoreLayer()

        score = layer.score(content, context)

        reasons = context.reasons.get(content.id, [])
        secondary_reasons = [r for r in reasons if "secondaire" in r.get("details", "")]
        assert len(secondary_reasons) == 1  # Un seul bonus, pas 3


class TestCoreLayerContentTheme:
    """Tests Phase 2: Article-level content.theme matching."""

    def create_context(self, user_interests=None, followed_sources=None, custom_sources=None):
        user_profile = MagicMock()
        user_profile.id = uuid4()
        return ScoringContext(
            user_profile=user_profile,
            user_interests=set(user_interests or []),
            user_interest_weights={},
            followed_source_ids=set(followed_sources or []),
            user_prefs={},
            now=datetime.now(),
            user_subtopics=set(),
            custom_source_ids=set(custom_sources or [])
        )

    def test_content_theme_takes_precedence(self):
        """content.theme="tech" sur source international → match tech."""
        content = MockContent(source_theme="international", theme="tech")
        context = self.create_context(user_interests={"tech"})
        layer = CoreLayer()

        score = layer.score(content, context)

        reasons = context.reasons.get(content.id, [])
        article_theme_reasons = [r for r in reasons if "Thème article" in r.get("details", "")]
        assert len(article_theme_reasons) == 1
        assert article_theme_reasons[0]["score_contribution"] == ScoringWeights.THEME_MATCH

    def test_content_theme_none_falls_to_source(self):
        """content.theme=None → fallback vers source.theme."""
        content = MockContent(source_theme="tech", theme=None)
        context = self.create_context(user_interests={"tech"})
        layer = CoreLayer()

        score = layer.score(content, context)

        reasons = context.reasons.get(content.id, [])
        source_theme_reasons = [r for r in reasons if r.get("details", "") == "Thème: tech"]
        assert len(source_theme_reasons) == 1

    def test_content_theme_mismatch_falls_to_secondary(self):
        """content.theme="culture" (non matché) → fallback secondary "tech"."""
        content = MockContent(
            source_theme="international",
            secondary_themes=["tech"],
            theme="culture"
        )
        context = self.create_context(user_interests={"tech"})
        layer = CoreLayer()

        score = layer.score(content, context)

        reasons = context.reasons.get(content.id, [])
        secondary_reasons = [r for r in reasons if "secondaire" in r.get("details", "")]
        assert len(secondary_reasons) == 1

    def test_content_theme_mismatch_falls_to_source_primary(self):
        """content.theme="culture" (non matché) → fallback source.theme="tech"."""
        content = MockContent(source_theme="tech", theme="culture")
        context = self.create_context(user_interests={"tech"})
        layer = CoreLayer()

        score = layer.score(content, context)

        reasons = context.reasons.get(content.id, [])
        source_reasons = [r for r in reasons if r.get("details", "") == "Thème: tech"]
        assert len(source_reasons) == 1

    def test_three_tier_priority_order(self):
        """content.theme (tier 1) > source.theme (tier 2) > secondary (tier 3)."""
        # Tous les tiers matchent, seul tier 1 doit être retenu
        content = MockContent(
            source_theme="science",
            secondary_themes=["economy"],
            theme="tech"
        )
        context = self.create_context(user_interests={"tech", "science", "economy"})
        layer = CoreLayer()

        score = layer.score(content, context)

        reasons = context.reasons.get(content.id, [])
        theme_reasons = [r for r in reasons if "Thème" in r.get("details", "")]
        assert len(theme_reasons) == 1
        assert "Thème article: tech" in theme_reasons[0]["details"]


class TestScoringWeightsRebalance:
    """Vérifie les nouvelles valeurs de poids Phase 2."""

    def test_theme_match_reduced(self):
        assert ScoringWeights.THEME_MATCH == 50.0

    def test_trusted_source_reduced(self):
        assert ScoringWeights.TRUSTED_SOURCE == 35.0

    def test_standard_source_increased(self):
        assert ScoringWeights.STANDARD_SOURCE == 15.0

    def test_custom_source_bonus_increased(self):
        assert ScoringWeights.CUSTOM_SOURCE_BONUS == 12.0

    def test_topic_match_reduced(self):
        assert ScoringWeights.TOPIC_MATCH == 45.0

    def test_subtopic_precision_reduced(self):
        assert ScoringWeights.SUBTOPIC_PRECISION_BONUS == 18.0

    def test_fqs_low_malus_softened(self):
        assert ScoringWeights.FQS_LOW_MALUS == -20.0

    def test_image_boost_increased(self):
        assert ScoringWeights.IMAGE_BOOST == 12.0

    def test_secondary_theme_factor(self):
        assert ScoringWeights.SECONDARY_THEME_FACTOR == 0.7

    def test_secondary_theme_effective_points(self):
        """Le score secondaire effectif doit être 35 pts (50 * 0.7)."""
        expected = ScoringWeights.THEME_MATCH * ScoringWeights.SECONDARY_THEME_FACTOR
        assert expected == pytest.approx(35.0)
