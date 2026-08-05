"""Tests unitaires de `matches_word_boundary` (helper Python, pas de DB).

Couvre la sémantique mot-entier (pas de faux positif substring) et le cache
de patterns compilés introduit pour éviter de recompiler la même regex à
chaque appel (cf. docstring du module).
"""

from app.services.recommendation.helpers.keyword_match import (
    _compiled_pattern,
    matches_word_boundary,
)


def test_matches_whole_word_not_substring():
    assert matches_word_boundary("belle", "une belle epoque") is True
    # « poubelle » / « isabelle » contiennent « belle » en milieu de mot ; « belles »
    # a un « s » collé après → pas de frontière de mot après « belle ».
    assert matches_word_boundary("belle", "le tri de la poubelle jaune") is False
    assert matches_word_boundary("belle", "isabelle adjani au festival") is False
    assert matches_word_boundary("belle", "les belles promesses") is False


def test_checks_all_provided_texts():
    assert (
        matches_word_boundary("belle", "titre neutre", "une tres belle initiative")
        is True
    )
    assert matches_word_boundary("belle", "titre neutre", "rien a signaler") is False


def test_blank_keyword_returns_false():
    assert matches_word_boundary("", "belle histoire") is False


def test_repeated_calls_are_consistent_and_use_cache():
    _compiled_pattern.cache_clear()

    assert matches_word_boundary("epoque", "une belle epoque") is True
    hits_before = _compiled_pattern.cache_info().hits

    # Même mot-clé rappelé : le pattern compilé doit venir du cache (hit),
    # pas être recompilé, et le résultat doit rester identique.
    assert matches_word_boundary("epoque", "une belle epoque") is True
    assert _compiled_pattern.cache_info().hits > hits_before
