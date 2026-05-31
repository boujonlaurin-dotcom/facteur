"""Génère le dictionnaire FR de « La Grille du jour » (mots de 6 lettres).

Source : `words/an-array-of-french-words` (liste FR de référence, ~336k entrées,
licence libre). On garde les mots qui, **après normalisation** (MAJUSCULES, sans
accent), font exactement 6 lettres A-Z (ni tiret, ni apostrophe, ni espace), puis
on union les mots du jour seedés (sécurité contre un nom propre absent de la
source, ex. EUROPE). Sortie triée, 1 mot/ligne, dans `app/data/grille_words_fr.txt`.

Le fichier généré est committé (pas de fetch au runtime). Régénération :

  cd packages/api && python -m scripts.build_grille_dictionary
"""

import json
import unicodedata
import urllib.request
from pathlib import Path

_SOURCE_URL = (
    "https://raw.githubusercontent.com/words/an-array-of-french-words/master/index.json"
)
_OUT_PATH = (
    Path(__file__).resolve().parent.parent / "app" / "data" / "grille_words_fr.txt"
)
_SEED_PATH = (
    Path(__file__).resolve().parent.parent / "app" / "data" / "grille_puzzles_seed.json"
)
WORD_LENGTH = 6


def normalize(word: str) -> str:
    decomposed = unicodedata.normalize("NFKD", word.strip())
    return "".join(c for c in decomposed if not unicodedata.combining(c)).upper()


def _seeded_words() -> set[str]:
    data = json.loads(_SEED_PATH.read_text(encoding="utf-8"))
    return {normalize(p["word"]) for p in data["puzzles"]}


def build() -> list[str]:
    with urllib.request.urlopen(_SOURCE_URL, timeout=60) as resp:  # noqa: S310
        source = json.loads(resp.read().decode("utf-8"))

    words: set[str] = set()
    for raw in source:
        if "-" in raw or "'" in raw or " " in raw:
            continue
        n = normalize(raw)
        if len(n) == WORD_LENGTH and n.isalpha() and n.isascii():
            words.add(n)

    words |= _seeded_words()
    return sorted(words)


_HEADER = """\
# La Grille du jour — dictionnaire FR de validation (mots de 6 lettres).
#
# GÉNÉRÉ — ne pas éditer à la main. Régénérer via :
#   cd packages/api && python -m scripts.build_grille_dictionary
#
# Source : words/an-array-of-french-words (liste FR de référence, licence libre).
# Filtre : après normalisation (MAJUSCULES, sans accent), exactement 6 lettres
# A-Z ; union des mots du jour seedés. Une entrée par ligne ; `#` = commentaire.
# Invariant : chaque mot du jour seedé figure ici (vérifié par le seed).
"""


def main() -> None:
    words = build()
    _OUT_PATH.write_text(_HEADER + "\n" + "\n".join(words) + "\n", encoding="utf-8")
    print(f"Wrote {len(words)} words to {_OUT_PATH}")


if __name__ == "__main__":
    main()
