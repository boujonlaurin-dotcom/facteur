"""Tests unitaires purs de La Grille du jour (états, normalisation, dico, rollover)."""

from datetime import datetime
from zoneinfo import ZoneInfo

from app.services.grille_dictionary import get_dictionary, is_valid_word
from app.services.grille_service import next_rollover_seconds
from app.services.grille_text import compute_tiles, normalize_word

PARIS = ZoneInfo("Europe/Paris")


# ----- compute_tiles --------------------------------------------------------


def test_compute_tiles_nominal():
    # CLIMAT vs PLACER : P absent · L bien placé (place) · A present · C present
    # · E absent · R absent.
    assert compute_tiles("CLIMAT", "PLACER") == [
        "absent",
        "place",
        "present",
        "present",
        "absent",
        "absent",
    ]


def test_compute_tiles_all_placed():
    assert compute_tiles("CLIMAT", "CLIMAT") == ["place"] * 6


def test_compute_tiles_double_letter_not_over_colored():
    # Réponse ALLEES (2x L, 2x E). Guess avec 3x E et 2x L mal placés :
    # le comptage d'occurrences ne doit pas sur-colorer en 'present'.
    answer = "ALLEES"  # A L L E E S
    guess = "EEELLL"  # E E E L L L
    tiles = compute_tiles(answer, guess)
    # positions 3,4 de answer = E,E ; guess[3]=L, guess[4]=L → pas place.
    # 'E' présent 2x dans answer : seulement 2 des 3 E du guess → present.
    assert tiles.count("present") + tiles.count("place") <= 4
    # exactement 2 E peuvent être colorés (present) + 2 L (present), reste absent
    assert tiles == ["present", "present", "absent", "present", "present", "absent"]


def test_compute_tiles_duplicate_in_guess_single_in_answer():
    # Réponse avec un seul 'A', guess avec deux 'A' : un seul coloré.
    answer = "CLIMAT"  # un seul A (index 4)
    guess = "AABBBB"
    tiles = compute_tiles(answer, guess)
    assert tiles[0] == "present"  # premier A capte l'unique stock
    assert tiles[1] == "absent"  # second A : stock épuisé


# ----- normalize_word -------------------------------------------------------


def test_normalize_word_strips_accents_and_uppercases():
    assert normalize_word("  élève ") == "ELEVE"
    assert normalize_word("plaçÉr") == "PLACER"
    assert normalize_word("forêts") == "FORETS"


# ----- dictionnaire ---------------------------------------------------------


def test_dictionary_loaded_and_six_letters_only():
    words = get_dictionary()
    assert len(words) > 0
    assert all(len(w) == 6 and w.isalpha() and w.isascii() for w in words)


def test_dictionary_contains_seeded_word():
    assert is_valid_word("CLIMAT")
    assert not is_valid_word("ZZZZZZ")


# ----- next_rollover_seconds ------------------------------------------------


def test_next_rollover_before_730_same_day():
    now = datetime(2026, 5, 30, 6, 0, tzinfo=PARIS)
    # 6:00 → 7:30 = 1h30 = 5400s
    assert next_rollover_seconds(now) == 5400


def test_next_rollover_after_730_next_day():
    now = datetime(2026, 5, 30, 18, 10, tzinfo=PARIS)
    secs = next_rollover_seconds(now)
    # 18:10 → lendemain 7:30 = 13h20 = 48000s (cf. maquette GDejaJoue)
    assert secs == 48000


def test_next_rollover_is_non_negative():
    now = datetime(2026, 5, 30, 7, 30, tzinfo=PARIS)
    assert next_rollover_seconds(now) > 0
