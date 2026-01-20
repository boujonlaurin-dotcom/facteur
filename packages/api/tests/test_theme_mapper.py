"""Tests pour le module theme_mapper."""
import pytest
from app.models.source import Source
from app.services.recommendation.theme_mapper import get_user_slugs_for_source, THEME_TO_USER_SLUGS

def test_all_themes_have_mapping():
    """Vérifie que tous les thèmes sources actuels ont un mapping."""
    expected_themes = {
        "Tech & Futur",
        "Société & Climat",
        "Économie",
        "Géopolitique",
        "Culture & Idées",
    }
    
    assert set(THEME_TO_USER_SLUGS.keys()) == expected_themes

def test_mapping_tech():
    """Tech & Futur mappe vers tech et science."""
    source = Source(theme="Tech & Futur")
    result = get_user_slugs_for_source(source)
    assert result == {"tech", "science"}

def test_mapping_society_climate():
    """Société & Climat mappe vers society et environment."""
    source = Source(theme="Société & Climat")
    result = get_user_slugs_for_source(source)
    assert result == {"society", "environment"}

def test_unknown_theme_returns_empty():
    """Un thème inconnu retourne un set vide."""
    source = Source(theme="Thème Inexistant")
    result = get_user_slugs_for_source(source)
    assert result == set()

def test_none_theme_returns_empty():
    """Un thème None retourne un set vide."""
    source = Source(theme=None)
    result = get_user_slugs_for_source(source)
    assert result == set()

def test_mapping_case_insensitive_and_whitespace():
    """Vérifie que le mapping est robuste à la casse et aux espaces."""
    # "  tech & futur " -> "Tech & Futur" -> map
    source = Source(theme="  tech & futur ")
    result = get_user_slugs_for_source(source)
    assert "tech & futur" in result
    assert "tech" in result
    
    # "SOCIété & CLIMAT"
    source2 = Source(theme="SOCIété & CLIMAT")
    result2 = get_user_slugs_for_source(source2)
    assert "société & climat" in result2
    assert "society" in result2
