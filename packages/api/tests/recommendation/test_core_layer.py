"""
Tests unitaires pour CoreLayer - Theme Matching
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
    def __init__(self, theme: str = None, id=None):
        self.theme = theme
        self.id = id or uuid4()


class MockContent:
    """Mock Content pour les tests."""
    def __init__(self, source_theme: str = None, source_id=None, published_at=None):
        self.id = uuid4()
        self.source = MockSource(theme=source_theme, id=source_id) if source_theme else None
        self.source_id = source_id or (self.source.id if self.source else uuid4())
        self.published_at = published_at or datetime.now()


class TestCoreLayerThemeMatching:
    """Tests pour le matching de thèmes dans CoreLayer."""

    def create_context(self, user_interests=None, followed_sources=None, custom_sources=None):
        """Helper pour créer un ScoringContext de test."""
        # Mock du user_profile pour éviter SQLAlchemy
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
        # Arrange
        content = MockContent(source_theme="tech")
        context = self.create_context(user_interests={"tech", "science"})
        layer = CoreLayer()

        # Act
        score = layer.score(content, context)

        # Assert
        assert score >= ScoringWeights.THEME_MATCH
        assert content.id in context.reasons
        reasons = context.reasons[content.id]
        theme_reasons = [r for r in reasons if "Thème" in r.get("details", "")]
        assert len(theme_reasons) == 1
        assert theme_reasons[0]["details"] == "Thème: tech"
        assert theme_reasons[0]["score_contribution"] == ScoringWeights.THEME_MATCH

    def test_theme_match_multiple_interests(self):
        """Vérifie le matching quand plusieurs intérêts sont présents."""
        # Arrange
        content = MockContent(source_theme="society")
        context = self.create_context(user_interests={"tech", "society", "economy"})
        layer = CoreLayer()

        # Act
        score = layer.score(content, context)

        # Assert
        assert score >= ScoringWeights.THEME_MATCH
        reasons = context.reasons.get(content.id, [])
        theme_reasons = [r for r in reasons if "Thème: society" in r.get("details", "")]
        assert len(theme_reasons) == 1

    def test_no_match_different_themes(self):
        """Vérifie qu'il n'y a pas de match quand les thèmes diffèrent."""
        # Arrange
        content = MockContent(source_theme="sports")  # Thème invalide/non matché
        context = self.create_context(user_interests={"tech", "science"})
        layer = CoreLayer()

        # Act
        score = layer.score(content, context)

        # Assert that THEME_MATCH bonus was not added
        # Score should be STANDARD_SOURCE (10) + recency (varies)
        assert score >= ScoringWeights.STANDARD_SOURCE
        assert score < ScoringWeights.STANDARD_SOURCE + 40  # Reasonable recency bound
        # Vérifie qu'aucune raison de thème n'est ajoutée
        reasons = context.reasons.get(content.id, [])
        theme_reasons = [r for r in reasons if "Thème" in r.get("details", "")]
        assert len(theme_reasons) == 0

    def test_no_match_empty_interests(self):
        """Vérifie le comportement quand l'utilisateur n'a pas d'intérêts."""
        # Arrange
        content = MockContent(source_theme="tech")
        context = self.create_context(user_interests=set())
        layer = CoreLayer()

        # Act
        score = layer.score(content, context)

        # Assert
        assert score < ScoringWeights.THEME_MATCH
        reasons = context.reasons.get(content.id, [])
        theme_reasons = [r for r in reasons if "Thème" in r.get("details", "")]
        assert len(theme_reasons) == 0

    def test_no_match_none_theme(self):
        """Vérifie le comportement quand la source n'a pas de thème."""
        # Arrange
        content = MockContent(source_theme=None)
        context = self.create_context(user_interests={"tech"})
        layer = CoreLayer()

        # Act
        score = layer.score(content, context)

        assert score >= ScoringWeights.STANDARD_SOURCE
        assert score < ScoringWeights.STANDARD_SOURCE + 40

    def test_all_valid_themes_matching(self):
        """Test exhaustif de tous les thèmes valides."""
        valid_themes = ["tech", "society", "environment", "economy", 
                       "politics", "culture", "science", "international"]
        
        layer = CoreLayer()
        
        for theme in valid_themes:
            # Arrange
            content = MockContent(source_theme=theme)
            context = self.create_context(user_interests={theme})
            
            # Act
            score = layer.score(content, context)
            
            # Assert
            assert score >= ScoringWeights.THEME_MATCH, f"Theme {theme} should match"
            reasons = context.reasons.get(content.id, [])
            theme_reasons = [r for r in reasons if f"Thème: {theme}" in r.get("details", "")]
            assert len(theme_reasons) == 1, f"Theme {theme} should have a reason"

    def test_theme_match_with_followed_source(self):
        """Vérifie le cumul du bonus thème + source suivie."""
        # Arrange
        source_id = uuid4()
        content = MockContent(source_theme="tech", source_id=source_id)
        context = self.create_context(
            user_interests={"tech"},
            followed_sources={source_id}
        )
        layer = CoreLayer()

        # Act
        score = layer.score(content, context)

        # Assert
        expected_min = ScoringWeights.THEME_MATCH + ScoringWeights.TRUSTED_SOURCE
        assert score >= expected_min
        
        reasons = context.reasons.get(content.id, [])
        details = [r.get("details", "") for r in reasons]
        assert any("Thème" in d for d in details)
        assert any("confiance" in d for d in details)

    def test_theme_match_rate_calculation(self):
        """Calcule le taux de matching sur un échantillon."""
        # Arrange
        layer = CoreLayer()
        user_interests = {"tech", "society", "science"}
        context = self.create_context(user_interests=user_interests)
        
        # 10 articles avec différents thèmes
        test_cases = [
            MockContent(source_theme="tech"),      # Match
            MockContent(source_theme="society"),   # Match
            MockContent(source_theme="science"),   # Match
            MockContent(source_theme="economy"),   # No match
            MockContent(source_theme="culture"),   # No match
            MockContent(source_theme="tech"),      # Match
            MockContent(source_theme="politics"),  # No match
            MockContent(source_theme="tech"),      # Match
            MockContent(source_theme="environment"), # No match
            MockContent(source_theme="society"),   # Match
        ]
        
        # Act
        matches = 0
        for content in test_cases:
            layer.score(content, context)
            reasons = context.reasons.get(content.id, [])
            if any("Thème" in r.get("details", "") for r in reasons):
                matches += 1
        
        # Assert
        match_rate = matches / len(test_cases)
        assert match_rate >= 0.5, f"Match rate {match_rate} should be >= 50%"
        # Target: > 70% selon la story
        print(f"Match rate: {match_rate:.1%} (target: >70%)")
