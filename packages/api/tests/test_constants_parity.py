"""Parité des constantes produit backend ↔ mobile.

`FAVORITE_CAP` est dupliqué en Dart (`InterestConstants.favoriteCap`) parce que
le mobile en a besoin à la compilation. Rien dans le typage ne relie les deux, et
la désynchronisation est **silencieuse et asymétrique** :

- le plafond d'ajout est appliqué par le backend seul, donc un backend plus
  permissif que le mobile ne casse rien de visible ;
- mais `kTourneeVisibleCap` (cap d'affichage de la Tournée) **dérive** du miroir
  Dart. Monter `FAVORITE_CAP` sans release mobile laisse les apps installées avec
  un cap trop petit, qui coupe la carte « Bonnes Nouvelles » sans erreur ni log.

C'est exactement le piège que la Story 22.8 a failli poser (cap posé à 15 puis
corrigé à 16). Ce test transforme la dérive en CI rouge.
"""

import re
from pathlib import Path

import pytest

from app.constants import FAVORITE_CAP

_DART_CONSTANTS = (
    Path(__file__).resolve().parents[3]
    / "apps"
    / "mobile"
    / "lib"
    / "config"
    / "constants.dart"
)


def _dart_int(source: str, pattern: str) -> int:
    match = re.search(pattern, source)
    assert match is not None, (
        f"constante introuvable dans {_DART_CONSTANTS.name} via /{pattern}/ — "
        "le miroir Dart a été renommé ou déplacé ; mets à jour ce test plutôt "
        "que de le supprimer, il garde les deux caps alignés."
    )
    return int(match.group(1))


@pytest.mark.skipif(
    not _DART_CONSTANTS.is_file(),
    reason="checkout backend-only (mobile absent) — rien à comparer",
)
def test_favorite_cap_matches_mobile_mirror():
    source = _DART_CONSTANTS.read_text(encoding="utf-8")
    dart_cap = _dart_int(source, r"static const int favoriteCap = (\d+);")

    assert dart_cap == FAVORITE_CAP, (
        f"FAVORITE_CAP={FAVORITE_CAP} (backend) != favoriteCap={dart_cap} "
        f"(mobile, {_DART_CONSTANTS}). Les deux doivent bouger dans la MÊME PR : "
        "le cap d'affichage Tournée `kTourneeVisibleCap` dérive du miroir Dart, "
        "donc une hausse backend-only coupe « Bonnes Nouvelles » sur les apps "
        "déjà installées."
    )
