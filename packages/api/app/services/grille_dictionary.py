"""Dictionnaire FR de « La Grille du jour » — chargé une fois en mémoire.

L'asset `app/data/grille_words_fr.txt` est lu au premier accès et conservé dans
un `frozenset` (normalisé MAJUSCULES sans accent, exactement 6 lettres). On
évite ainsi un round-trip DB par proposition.
"""

from functools import lru_cache
from pathlib import Path

from app.services.grille_text import normalize_word

# Asset embarqué (1 mot/ligne, `#` = commentaire).
_DICT_PATH = Path(__file__).resolve().parent.parent / "data" / "grille_words_fr.txt"

# Longueur unique gérée par le MVP.
WORD_LENGTH = 6


def _load_words(path: Path) -> frozenset[str]:
    """Charge et normalise le dictionnaire : MAJ, sans accent, 6 lettres A-Z."""
    words: set[str] = set()
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        word = normalize_word(line)
        if len(word) == WORD_LENGTH and word.isalpha() and word.isascii():
            words.add(word)
    return frozenset(words)


@lru_cache(maxsize=1)
def get_dictionary() -> frozenset[str]:
    """Retourne le `frozenset` des mots valides (chargé une seule fois)."""
    return _load_words(_DICT_PATH)


def is_valid_word(word: str) -> bool:
    """True si `word` (déjà normalisé) appartient au dictionnaire."""
    return word in get_dictionary()
