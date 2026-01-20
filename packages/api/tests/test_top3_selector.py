"""Tests unitaires pour Top3Selector.

Story 4.4: Top 3 Briefing Quotidien
Valide la sélection du Top 3 avec boosts et contraintes.
"""
import pytest
import uuid
from unittest.mock import MagicMock
from typing import Set

from app.services.briefing.top3_selector import Top3Selector, Top3Item


class TestTop3SelectorHelpers:
    """Helpers pour les tests."""

    @staticmethod
    def create_mock_content(
        title: str = "Test Title",
        source_id: uuid.UUID = None,
        content_id: uuid.UUID = None
    ) -> MagicMock:
        """Crée un mock Content."""
        mock = MagicMock()
        mock.id = content_id or uuid.uuid4()
        mock.source_id = source_id or uuid.uuid4()
        mock.title = title
        mock.guid = str(uuid.uuid4())
        return mock


class TestApplyBoosts:
    """Tests pour l'application des boosts."""

    def test_une_boost_applied(self):
        """Test que le boost Une (+30) est appliqué."""
        selector = Top3Selector()
        
        content = TestTop3SelectorHelpers.create_mock_content("Article Une")
        une_content_ids = {content.id}
        
        scored_contents = [(content, 50.0)]
        
        result = selector.select_top3(
            scored_contents=scored_contents,
            user_followed_sources=set(),
            une_content_ids=une_content_ids,
            trending_content_ids=set()
        )
        
        assert len(result) == 1
        assert result[0].score == 50.0 + 30  # base + BOOST_UNE
        assert result[0].top3_reason == "À la Une"

    def test_trending_boost_applied(self):
        """Test que le boost Trending (+40) est appliqué."""
        selector = Top3Selector()
        
        content = TestTop3SelectorHelpers.create_mock_content("Article Trending")
        trending_content_ids = {content.id}
        
        scored_contents = [(content, 50.0)]
        
        result = selector.select_top3(
            scored_contents=scored_contents,
            user_followed_sources=set(),
            une_content_ids=set(),
            trending_content_ids=trending_content_ids
        )
        
        assert len(result) == 1
        assert result[0].score == 50.0 + 40  # base + BOOST_TRENDING
        assert result[0].top3_reason == "Sujet tendance"

    def test_both_boosts_cumulative(self):
        """Test que les boosts sont cumulatifs."""
        selector = Top3Selector()
        
        content = TestTop3SelectorHelpers.create_mock_content("Article Une + Trending")
        
        scored_contents = [(content, 50.0)]
        
        result = selector.select_top3(
            scored_contents=scored_contents,
            user_followed_sources=set(),
            une_content_ids={content.id},
            trending_content_ids={content.id}
        )
        
        assert len(result) == 1
        # Base + BOOST_UNE + BOOST_TRENDING = 50 + 30 + 40 = 120
        assert result[0].score == 120.0

    def test_no_boost_for_non_matching(self):
        """Test qu'aucun boost n'est appliqué si pas de match."""
        selector = Top3Selector()
        
        content = TestTop3SelectorHelpers.create_mock_content("Article Normal")
        
        scored_contents = [(content, 50.0)]
        
        result = selector.select_top3(
            scored_contents=scored_contents,
            user_followed_sources=set(),
            une_content_ids=set(),
            trending_content_ids=set()
        )
        
        assert len(result) == 1
        assert result[0].score == 50.0  # Pas de boost
        assert result[0].top3_reason == "Recommandé"


class TestMaxOnePerSource:
    """Tests pour la contrainte max 1 article par source."""

    def test_one_per_source_for_top2(self):
        """Test que les slots 1 et 2 ont des sources distinctes."""
        selector = Top3Selector()
        
        source_a = uuid.uuid4()
        source_b = uuid.uuid4()
        
        contents = [
            (TestTop3SelectorHelpers.create_mock_content("A1", source_a), 100.0),
            (TestTop3SelectorHelpers.create_mock_content("A2", source_a), 90.0),  # Même source
            (TestTop3SelectorHelpers.create_mock_content("B1", source_b), 80.0),
        ]
        
        result = selector.select_top3(
            scored_contents=contents,
            user_followed_sources=set(),
            une_content_ids=set(),
            trending_content_ids=set()
        )
        
        # Devrait sélectionner A1 (100) et B1 (80), pas A2 (90 mais même source)
        assert len(result) >= 2
        source_ids = {item.content.source_id for item in result[:2]}
        assert source_a in source_ids
        assert source_b in source_ids

    def test_skips_duplicate_source(self):
        """Test que le 2e article d'une même source est ignoré."""
        selector = Top3Selector()
        
        source_a = uuid.uuid4()
        
        content1 = TestTop3SelectorHelpers.create_mock_content("Article 1", source_a)
        content2 = TestTop3SelectorHelpers.create_mock_content("Article 2", source_a)
        
        contents = [
            (content1, 100.0),
            (content2, 90.0),
        ]
        
        result = selector.select_top3(
            scored_contents=contents,
            user_followed_sources=set(),
            une_content_ids=set(),
            trending_content_ids=set()
        )
        
        # Devrait sélectionner seulement content1
        assert len(result) == 1
        assert result[0].content.id == content1.id


class TestSlot3FollowedSource:
    """Tests pour la réservation du slot #3 aux sources suivies."""

    def test_slot3_is_followed_source(self):
        """Test que le slot #3 est une source suivie."""
        selector = Top3Selector()
        
        source_a = uuid.uuid4()
        source_b = uuid.uuid4()
        source_followed = uuid.uuid4()
        
        content_a = TestTop3SelectorHelpers.create_mock_content("Top 1", source_a)
        content_b = TestTop3SelectorHelpers.create_mock_content("Top 2", source_b)
        content_c = TestTop3SelectorHelpers.create_mock_content("High score but not followed", uuid.uuid4())
        content_followed = TestTop3SelectorHelpers.create_mock_content("From followed", source_followed)
        
        contents = [
            (content_a, 100.0),
            (content_b, 90.0),
            (content_c, 85.0),  # Score plus haut que content_followed
            (content_followed, 50.0),  # Score plus bas mais source suivie
        ]
        
        result = selector.select_top3(
            scored_contents=contents,
            user_followed_sources={source_followed},
            une_content_ids=set(),
            trending_content_ids=set()
        )
        
        assert len(result) == 3
        # Slot #3 devrait être la source suivie
        assert result[2].content.source_id == source_followed
        assert result[2].top3_reason == "Source suivie"

    def test_slot3_fallback_if_no_followed(self):
        """Test le fallback si aucune source suivie disponible."""
        selector = Top3Selector()
        
        source_a = uuid.uuid4()
        source_b = uuid.uuid4()
        source_c = uuid.uuid4()
        
        contents = [
            (TestTop3SelectorHelpers.create_mock_content("Top 1", source_a), 100.0),
            (TestTop3SelectorHelpers.create_mock_content("Top 2", source_b), 90.0),
            (TestTop3SelectorHelpers.create_mock_content("Top 3 fallback", source_c), 80.0),
        ]
        
        result = selector.select_top3(
            scored_contents=contents,
            user_followed_sources=set(),  # Aucune source suivie
            une_content_ids=set(),
            trending_content_ids=set()
        )
        
        assert len(result) == 3
        assert result[2].content.source_id == source_c
        # La raison ne devrait pas être "Source suivie"
        assert result[2].top3_reason != "Source suivie"

    def test_slot3_followed_with_boost(self):
        """Test que le slot #3 suit la source suivie même si elle a un boost."""
        selector = Top3Selector()
        
        source_a = uuid.uuid4()
        source_b = uuid.uuid4()
        source_followed = uuid.uuid4()
        
        content_followed = TestTop3SelectorHelpers.create_mock_content("From followed", source_followed)
        
        contents = [
            (TestTop3SelectorHelpers.create_mock_content("Top 1", source_a), 100.0),
            (TestTop3SelectorHelpers.create_mock_content("Top 2", source_b), 90.0),
            (content_followed, 50.0),  # Source suivie
        ]
        
        # La source suivie est aussi trending
        result = selector.select_top3(
            scored_contents=contents,
            user_followed_sources={source_followed},
            une_content_ids=set(),
            trending_content_ids={content_followed.id}  # +40 boost
        )
        
        assert len(result) == 3
        # Le slot #3 devrait quand même avoir la raison "Source suivie"
        assert result[2].top3_reason == "Source suivie"


class TestEdgeCases:
    """Tests pour les cas limites."""

    def test_empty_input(self):
        """Test avec une liste vide."""
        selector = Top3Selector()
        
        result = selector.select_top3(
            scored_contents=[],
            user_followed_sources=set(),
            une_content_ids=set(),
            trending_content_ids=set()
        )
        
        assert result == []

    def test_single_content(self):
        """Test avec un seul contenu."""
        selector = Top3Selector()
        
        content = TestTop3SelectorHelpers.create_mock_content("Seul article")
        
        result = selector.select_top3(
            scored_contents=[(content, 50.0)],
            user_followed_sources=set(),
            une_content_ids=set(),
            trending_content_ids=set()
        )
        
        assert len(result) == 1

    def test_two_contents(self):
        """Test avec deux contenus."""
        selector = Top3Selector()
        
        source_a = uuid.uuid4()
        source_b = uuid.uuid4()
        
        contents = [
            (TestTop3SelectorHelpers.create_mock_content("A", source_a), 100.0),
            (TestTop3SelectorHelpers.create_mock_content("B", source_b), 90.0),
        ]
        
        result = selector.select_top3(
            scored_contents=contents,
            user_followed_sources=set(),
            une_content_ids=set(),
            trending_content_ids=set()
        )
        
        assert len(result) == 2

    def test_all_same_source(self):
        """Test avec tous les contenus de la même source."""
        selector = Top3Selector()
        
        source = uuid.uuid4()
        
        contents = [
            (TestTop3SelectorHelpers.create_mock_content("A1", source), 100.0),
            (TestTop3SelectorHelpers.create_mock_content("A2", source), 90.0),
            (TestTop3SelectorHelpers.create_mock_content("A3", source), 80.0),
        ]
        
        result = selector.select_top3(
            scored_contents=contents,
            user_followed_sources=set(),
            une_content_ids=set(),
            trending_content_ids=set()
        )
        
        # Devrait sélectionner seulement 1 (contrainte max 1/source)
        assert len(result) == 1
        assert result[0].score == 100.0


class TestSortingByScore:
    """Tests pour le tri par score."""

    def test_highest_score_first(self):
        """Test que le contenu avec le score le plus élevé est premier."""
        selector = Top3Selector()
        
        source_a = uuid.uuid4()
        source_b = uuid.uuid4()
        source_c = uuid.uuid4()
        
        content_low = TestTop3SelectorHelpers.create_mock_content("Low", source_a)
        content_mid = TestTop3SelectorHelpers.create_mock_content("Mid", source_b)
        content_high = TestTop3SelectorHelpers.create_mock_content("High", source_c)
        
        # Ordre inversé pour tester le tri
        contents = [
            (content_low, 30.0),
            (content_mid, 60.0),
            (content_high, 90.0),
        ]
        
        result = selector.select_top3(
            scored_contents=contents,
            user_followed_sources=set(),
            une_content_ids=set(),
            trending_content_ids=set()
        )
        
        assert len(result) == 3
        assert result[0].content.id == content_high.id
        assert result[1].content.id == content_mid.id

    def test_boost_changes_order(self):
        """Test que le boost change l'ordre de sélection."""
        selector = Top3Selector()
        
        source_a = uuid.uuid4()
        source_b = uuid.uuid4()
        
        content_high = TestTop3SelectorHelpers.create_mock_content("High base", source_a)
        content_boosted = TestTop3SelectorHelpers.create_mock_content("Boosted", source_b)
        
        contents = [
            (content_high, 80.0),  # Base élevé
            (content_boosted, 50.0),  # Base plus bas mais sera boosté
        ]
        
        result = selector.select_top3(
            scored_contents=contents,
            user_followed_sources=set(),
            une_content_ids=set(),
            trending_content_ids={content_boosted.id}  # +40 = 90 total
        )
        
        # content_boosted devrait être premier (90 > 80)
        assert result[0].content.id == content_boosted.id
        assert result[0].score == 90.0


class TestGenerateWithReasons:
    """Tests pour generate_top3_with_reasons."""

    def test_returns_dict_format(self):
        """Test que le format dict est correct."""
        selector = Top3Selector()
        
        source = uuid.uuid4()
        content = TestTop3SelectorHelpers.create_mock_content("Test", source)
        
        result = selector.generate_top3_with_reasons(
            scored_contents=[(content, 50.0)],
            user_followed_sources=set(),
            une_content_ids=set(),
            trending_content_ids=set()
        )
        
        assert len(result) == 1
        assert "content_id" in result[0]
        assert "rank" in result[0]
        assert "top3_reason" in result[0]
        assert "score" in result[0]
        assert result[0]["rank"] == 1
