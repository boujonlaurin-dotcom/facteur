"""Génère le dictionnaire FR de « La Grille du jour » (mots de 6 lettres).

Sources unionnées :
- `words/an-array-of-french-words` (liste FR de référence, ~336k entrées,
  licence libre) — **déjà inflectée** : couvre les conjugaisons (vérifié :
  FINIES, COURUS, IRIONS, AURAIT, MANGES… présents). Pas besoin d'une 2ᵉ source
  de flexions (on évite Lexique383, sous CC BY-SA share-alike, peu compatible
  avec un asset embarqué dans une app fermée).
- `app/data/grille_proper_nouns_fr.txt` — assets **curés** committés : noms
  propres quasi absents de la source libre (pays, nationalités, régions,
  capitales/villes, prénoms courants), ex. ITALIE, RUSSIE — c'est le correctif
  du bug « mots valides refusés ».
- Les mots du jour seedés (sécurité contre un mot absent des deux sources).

On garde les mots qui, **après normalisation** (MAJUSCULES, sans accent), font
exactement 6 lettres A-Z (ni tiret, ni apostrophe, ni espace). Sortie triée,
1 mot/ligne, dans `app/data/grille_words_fr.txt`.

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
_PROPER_NOUNS_PATH = (
    Path(__file__).resolve().parent.parent
    / "app"
    / "data"
    / "grille_proper_nouns_fr.txt"
)
WORD_LENGTH = 6


def normalize(word: str) -> str:
    decomposed = unicodedata.normalize("NFKD", word.strip())
    return "".join(c for c in decomposed if not unicodedata.combining(c)).upper()


def _seeded_words() -> set[str]:
    data = json.loads(_SEED_PATH.read_text(encoding="utf-8"))
    return {normalize(p["word"]) for p in data["puzzles"]}


def _proper_nouns() -> set[str]:
    """Noms propres curés (1 mot/ligne, `#` = commentaire), normalisés.

    L'auteur écrit en clair (accents OK, casse libre) ; on normalise (MAJ, sans
    accent) et on ne garde que les entrées de 6 lettres A-Z — les autres sont
    ignorées en silence (garde-fou contre une faute de longueur dans l'asset).
    """
    words: set[str] = set()
    for raw in _PROPER_NOUNS_PATH.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        n = normalize(line)
        if len(n) == WORD_LENGTH and n.isalpha() and n.isascii():
            words.add(n)
    return words


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

    words |= _proper_nouns()
    words |= _seeded_words()
    return sorted(words)


_HEADER = """\
# La Grille du jour — dictionnaire FR de validation (mots de 6 lettres).
#
# GÉNÉRÉ — ne pas éditer à la main. Régénérer via :
#   cd packages/api && python -m scripts.build_grille_dictionary
#
# Sources : words/an-array-of-french-words (liste FR de référence, déjà inflectée,
# licence libre) + app/data/grille_proper_nouns_fr.txt (noms propres curés) +
# mots du jour seedés.
# Filtre : après normalisation (MAJUSCULES, sans accent), exactement 6 lettres
# A-Z. Une entrée par ligne ; `#` = commentaire.
# Invariants (vérifiés par les tests) : chaque mot du jour seedé et chaque nom
# propre curé figure ici.
"""


def main() -> None:
    words = build()
    _OUT_PATH.write_text(_HEADER + "\n" + "\n".join(words) + "\n", encoding="utf-8")
    print(f"Wrote {len(words)} words to {_OUT_PATH}")


if __name__ == "__main__":
    main()
