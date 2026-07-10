"""Pool de qualité éditoriale de « La Grille du jour » — chargé une fois.

L'asset `app/data/grille_quality_words_fr.txt` liste les noms communs « dignes
du mot du jour » (voix Facteur). Il sert de **filtre éditorial** sur les mots
extraits de l'actu : un candidat n'est retenu que s'il est dans ce pool ET dans
le dictionnaire de validité (`grille_dictionary.is_valid_word`).

Même pattern que `grille_dictionary.py` : lecture unique, `frozenset` normalisé
(MAJUSCULES sans accent, exactement 6 lettres).
"""

from functools import lru_cache
from pathlib import Path

from app.services.grille_dictionary import WORD_LENGTH
from app.services.grille_text import normalize_word

# Asset embarqué (1 mot/ligne, `#` = commentaire).
_POOL_PATH = (
    Path(__file__).resolve().parent.parent / "data" / "grille_quality_words_fr.txt"
)


def _load_words(path: Path) -> frozenset[str]:
    """Charge et normalise le pool : MAJ, sans accent, 6 lettres A-Z."""
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
def get_quality_pool() -> frozenset[str]:
    """Retourne le `frozenset` des mots de qualité (chargé une seule fois)."""
    return _load_words(_POOL_PATH)


def is_quality_word(word: str) -> bool:
    """True si `word` (déjà normalisé) appartient au pool de qualité."""
    return word in get_quality_pool()
