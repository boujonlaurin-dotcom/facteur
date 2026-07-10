"""Tests du pool de qualité éditoriale du mot du jour."""

from app.services.grille_dictionary import is_valid_word
from app.services.grille_quality_pool import (
    get_quality_pool,
    is_quality_word,
)


def test_pool_loads_seed_words():
    pool = get_quality_pool()
    for word in ("CLIMAT", "BUDGET", "SOMMET", "EUROPE", "GUERRE"):
        assert word in pool


def test_pool_words_are_six_letters_upper_ascii():
    for word in get_quality_pool():
        assert len(word) == 6
        assert word.isalpha() and word.isascii()
        assert word.upper() == word


def test_pool_is_subset_of_validity_dictionary():
    # Tout mot de qualité DOIT être tapable par le joueur (sinon jamais choisi).
    for word in get_quality_pool():
        assert is_valid_word(word), f"{word} absent du dictionnaire de validité"


def test_is_quality_word():
    assert is_quality_word("CLIMAT")
    assert not is_quality_word("ZZZZZZ")
    assert not is_quality_word("")
