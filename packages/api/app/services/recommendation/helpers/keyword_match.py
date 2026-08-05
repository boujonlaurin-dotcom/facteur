"""Matching mot-entier d'un mot-clé dans un texte (titre / description).

Centralise la primitive qui était dupliquée à l'identique dans plusieurs
couches de scoring (UserCustomTopicLayer, pilier Pertinence) : un mot-clé ne
matche que sur une **frontière de mot** (regex `\\b…\\b`), pas en sous-chaîne —
sinon des mots-clés génériques (« titre », « finale », « agent »…) ramènent des
articles hors-sujet (plan veille V0, Problème 3).

L'équivalent SQL (`~*` avec bornes Postgres `\\m…\\M`) vit dans
`services/veille/feed_filter.py` car il produit un prédicat SQLAlchemy, pas un
booléen Python — mais la sémantique est la même.

Le pattern compilé est mis en cache par `keyword_lower` (vocabulaire de
mots-clés petit et borné) pour éviter de recompiler la même regex à chaque
appel — un run `--sensitivity` complet en fait des dizaines de milliers.
"""

import re
from functools import lru_cache

_CACHE_MAXSIZE = 2048


@lru_cache(maxsize=_CACHE_MAXSIZE)
def _compiled_pattern(keyword_lower: str) -> re.Pattern[str]:
    return re.compile(r"\b" + re.escape(keyword_lower) + r"\b")


def matches_word_boundary(keyword_lower: str, *texts_lower: str) -> bool:
    """True si `keyword_lower` apparaît en **mot-entier** dans l'un des `texts_lower`.

    `keyword_lower` et `texts_lower` sont attendus déjà en minuscules (le caller
    normalise une fois). Un mot-clé vide renvoie toujours False.
    """
    if not keyword_lower:
        return False
    pattern = _compiled_pattern(keyword_lower)
    return any(pattern.search(text) for text in texts_lower)
