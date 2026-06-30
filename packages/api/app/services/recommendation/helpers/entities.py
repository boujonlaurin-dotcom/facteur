"""Parsing partagé des entités nommées d'un article (`Content.entities`).

`Content.entities` est un `ARRAY(Text)` dont chaque élément est une chaîne JSON
`{"name": ..., "type": ...}` produite par la classif LLM (tolérant à un nom en
clair en repli). Plusieurs surfaces en ont besoin (mute, affinité, scoring) ;
cette primitive centralise le parse + la normalisation pour éviter la
divergence (cf. PR2 « affinité entités »).
"""

import json
from collections.abc import Iterator


def iter_entity_names(entities: list[str] | None) -> Iterator[tuple[str, str]]:
    """Yield `(display, key)` pour chaque entité distincte, dans l'ordre article.

    - `display` conserve la **casse live** de l'article (raisons user-facing).
    - `key` = `display.lower()` (clé canonique : stockage == matching).

    Distinct par `key`. Les éléments illisibles ou sans nom sont ignorés.
    """
    seen: set[str] = set()
    for raw in entities or ():
        name = ""
        try:
            parsed = json.loads(raw)
            if isinstance(parsed, dict):
                name = parsed.get("name", "") or ""
        except (ValueError, TypeError):
            # Entité stockée en clair (pas de JSON) — tolérée comme nom.
            name = raw if isinstance(raw, str) else ""
        display = name.strip()
        key = display.lower()
        if not key or key in seen:
            continue
        seen.add(key)
        yield display, key
