"""
Tests pour le topic-to-theme mapper (Phase 2 diversité feed).
"""
import pytest

from app.services.ml.topic_theme_mapper import (
    TOPIC_TO_THEME,
    VALID_THEMES,
    infer_theme_from_topics,
)


class TestTopicToThemeMapping:
    """Vérifie la complétude et la cohérence du mapping."""

    def test_all_topics_map_to_valid_themes(self):
        """Chaque topic doit mapper vers un des 8 thèmes valides."""
        for topic, theme in TOPIC_TO_THEME.items():
            assert theme in VALID_THEMES, (
                f"Topic '{topic}' maps to '{theme}' which is not in VALID_THEMES"
            )

    def test_mapping_covers_expected_count(self):
        """Le mapping doit couvrir au moins 40 topics (sur 50)."""
        assert len(TOPIC_TO_THEME) >= 40

    def test_all_8_themes_represented(self):
        """Chaque thème broad doit avoir au moins un topic qui y mappe."""
        themes_used = set(TOPIC_TO_THEME.values())
        for theme in VALID_THEMES:
            assert theme in themes_used, f"Theme '{theme}' has no topics mapping to it"

    def test_key_topic_mappings(self):
        """Vérifie les mappings critiques."""
        assert TOPIC_TO_THEME["ai"] == "tech"
        assert TOPIC_TO_THEME["climate"] == "environment"
        assert TOPIC_TO_THEME["geopolitics"] == "international"
        assert TOPIC_TO_THEME["cinema"] == "culture"
        assert TOPIC_TO_THEME["finance"] == "economy"
        assert TOPIC_TO_THEME["health"] == "society"
        assert TOPIC_TO_THEME["space"] == "science"
        assert TOPIC_TO_THEME["politics"] == "politics"


class TestInferThemeFromTopics:
    """Tests pour la fonction d'inférence de thème."""

    def test_empty_list_returns_none(self):
        assert infer_theme_from_topics([]) is None

    def test_none_returns_none(self):
        # Protection contre un appel avec None (cast implicite)
        result = infer_theme_from_topics(None)
        assert result is None

    def test_unknown_topic_returns_none(self):
        assert infer_theme_from_topics(["zzz_nonexistent"]) is None

    def test_uses_first_topic_only(self):
        """Seul le premier topic (score ML max) détermine le thème."""
        result = infer_theme_from_topics(["ai", "geopolitics", "climate"])
        assert result == "tech"  # "ai" → tech, ignore geopolitics et climate

    def test_case_insensitive(self):
        assert infer_theme_from_topics(["AI"]) == "tech"
        assert infer_theme_from_topics(["Climate"]) == "environment"

    def test_strips_whitespace(self):
        assert infer_theme_from_topics(["  ai  "]) == "tech"

    def test_typical_ml_output(self):
        """Simule un output ML typique avec 3 topics ordonnés par score."""
        # Article sur l'IA et la vie privée
        result = infer_theme_from_topics(["ai", "privacy", "tech"])
        assert result == "tech"

        # Article sur le changement climatique
        result = infer_theme_from_topics(["climate", "energy", "politics"])
        assert result == "environment"

        # Article géopolitique
        result = infer_theme_from_topics(["geopolitics", "economy", "politics"])
        assert result == "international"
