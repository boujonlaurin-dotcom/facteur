"""Diversification générique 1-(ou N)-par-clé.

Sert à la fois :
- au round 1 de l'Essentiel (1 article max par topic),
- à la passe finale du feed thématique (top 3 sur 3 clusters distincts).

L'algorithme préserve l'ordre d'entrée (déjà trié par score décroissant
par les appelants) et bascule en mode "souple" si on n'a pas assez de
clés distinctes : on autorise alors la réutilisation pour compléter au
lieu de retourner une liste plus courte (l'UI top 3 doit toujours avoir
3 cartes).
"""

from collections.abc import Callable, Hashable, Iterable


def diversify[T](
    items: Iterable[T],
    key_fn: Callable[[T], Hashable | None],
    *,
    target_size: int | None = None,
    max_per_key: int = 1,
    fallback_ok: bool = True,
) -> list[T]:
    """Retourne `items` filtrés à au plus `max_per_key` éléments par clé.

    Args:
        items: itérable trié par score décroissant.
        key_fn: extrait la clé de diversification (cluster_id, topic_slug…).
            Une clé `None` est traitée comme "pas de groupement" — l'élément
            est gardé sans compter dans aucun groupe.
        target_size: si fourni et qu'on n'atteint pas cette taille en mode
            strict, on bascule en mode souple (cf. `fallback_ok`).
        max_per_key: nombre max d'éléments autorisés par clé en mode strict.
        fallback_ok: si True et `target_size` non atteint, on rajoute les
            éléments écartés par ordre original jusqu'à atteindre la cible.

    Returns:
        Liste filtrée. Ordre d'entrée préservé.
    """
    items_list = list(items)
    if not items_list:
        return []

    counts: dict[Hashable, int] = {}
    picked: list[T] = []
    skipped: list[T] = []

    for item in items_list:
        key = key_fn(item)
        if key is None:
            picked.append(item)
            continue
        if counts.get(key, 0) < max_per_key:
            picked.append(item)
            counts[key] = counts.get(key, 0) + 1
        else:
            skipped.append(item)

    if target_size is not None and fallback_ok and len(picked) < target_size:
        for item in skipped:
            picked.append(item)
            if len(picked) >= target_size:
                break

    return picked
