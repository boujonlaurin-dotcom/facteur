"""Matching mot-entier d'un mot-clé dans un texte (titre / description).

Centralise la primitive qui était dupliquée à l'identique dans plusieurs
couches de scoring (UserCustomTopicLayer, pilier Pertinence) : un mot-clé ne
matche que sur une **frontière de mot** (regex `\\b…\\b`), pas en sous-chaîne —
sinon des mots-clés génériques (« titre », « finale », « agent »…) ramènent des
articles hors-sujet (plan veille V0, Problème 3).

L'équivalent SQL (`~*` avec bornes Postgres `\\m…\\M`) vit dans
`services/veille/feed_filter.py` car il produit un prédicat SQLAlchemy, pas un
booléen Python — mais la sémantique est la même.
"""

import re


def matches_word_boundary(keyword_lower: str, *texts_lower: str) -> bool:
    """True si `keyword_lower` apparaît en **mot-entier** dans l'un des `texts_lower`.

    `keyword_lower` et `texts_lower` sont attendus déjà en minuscules (le caller
    normalise une fois). Un mot-clé vide renvoie toujours False.
    """
    if not keyword_lower:
        return False
    pattern = r"\b" + re.escape(keyword_lower) + r"\b"
    return any(re.search(pattern, text) for text in texts_lower)
