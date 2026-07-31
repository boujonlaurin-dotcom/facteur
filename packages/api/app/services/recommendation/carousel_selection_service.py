"""Sélection partagée des carrousels Phase B + rotation date-seedée (Story 32.1).

Deux surfaces (Flâner `GET /api/feed/` et l'Essentiel `GET /api/essentiel`)
coordonnent le carrousel mis en avant **sans état DB** :

- `build_phase_b(ctx)` : construit TOUS les carrousels Phase B éligibles. Ne fait
  QUE l'exclusion des articles consommés → **surface-indépendant**. Utilisé par
  Flâner, qui rend jusqu'à 3 carrousels.
- `pick_essentiel_type(user, date, eligible)` : type mis en avant dans l'Essentiel,
  choisi de façon déterministe (rotation seedée `(user, date)`). Flâner recalcule
  le **même** type et l'exclut → complémentarité.
- `select_essentiel_carousel(ctx, date)` : variante **paresseuse** pour l'Essentiel,
  qui ne rend qu'UN carrousel — construit les types dans l'ordre de rotation et
  s'arrête au premier éligible (≈ 1/4 du travail DB de `build_phase_b`, sur un
  endpoint sensible à la latence). Résultat identique au couple `build_phase_b` +
  `pick_essentiel_type` (l'éligibilité par type est déterministe dans la requête).
"""

from __future__ import annotations

import datetime
import hashlib
from uuid import UUID

from app.services.recommendation.carousel_catalog import (
    PHASE_B_ORDER,
    PHASE_B_SPECS,
    CarouselBuildContext,
    CarouselContent,
)


def _rotation_order(user_id: UUID | str, target_date: datetime.date) -> tuple[str, ...]:
    """`PHASE_B_ORDER` tournée d'un offset seedé par `(user_id, target_date)`.

    Source unique de la rotation, partagée par `pick_essentiel_type` (Flâner) et
    `select_essentiel_carousel` (Essentiel) → les deux surfaces s'accordent sur le
    même type quel que soit le contexte de requête. La rotation porte sur la liste
    fixe (longueur constante = 4), pas sur `len(eligible)`, pour rester stable dans
    la journée malgré une éligibilité qui varierait (consommation d'articles).
    """
    digest = hashlib.md5(f"{user_id}|{target_date.isoformat()}".encode()).hexdigest()
    offset = int(digest, 16) % len(PHASE_B_ORDER)
    return PHASE_B_ORDER[offset:] + PHASE_B_ORDER[:offset]


async def build_phase_b(
    ctx: CarouselBuildContext,
) -> dict[str, CarouselContent]:
    """Construit tous les carrousels Phase B éligibles (surface-indépendant).

    Retourne `{code: CarouselContent}` pour les types qui atteignent leur seuil
    d'émission. Les items peuvent contenir des articles promus ailleurs (Phase A) :
    c'est à l'appelant de les post-filtrer via `CarouselContent.excluding`.
    """
    contents: dict[str, CarouselContent] = {}
    for spec in PHASE_B_SPECS:
        content = await spec.build(ctx)
        if content is not None and len(content.items) >= spec.min_items:
            contents[spec.code] = content
    return contents


def pick_essentiel_type(
    user_id: UUID | str,
    target_date: datetime.date,
    eligible: set[str] | dict[str, object] | list[str],
) -> str | None:
    """Type du carrousel mis en avant dans l'Essentiel : premier de la rotation
    date-seedée (`_rotation_order`) présent dans `eligible`. Le seed ne dépend que
    de `(user_id, target_date)` → identique sur les deux surfaces."""
    eligible_set = set(eligible)
    for code in _rotation_order(user_id, target_date):
        if code in eligible_set:
            return code
    return None


async def select_essentiel_carousel(
    ctx: CarouselBuildContext,
    target_date: datetime.date,
) -> CarouselContent | None:
    """Construit paresseusement le SEUL carrousel du jour de l'Essentiel.

    Suit `_rotation_order` et retourne le premier type dont le build atteint son
    seuil, sans construire les suivants. Équivalent à
    `pick_essentiel_type(build_phase_b(ctx).keys())` (même définition d'éligibilité,
    même ordre), mais évite de construire les types perdants sur un endpoint
    sensible à la latence.
    """
    specs_by_code = {spec.code: spec for spec in PHASE_B_SPECS}
    for code in _rotation_order(ctx.user_id, target_date):
        spec = specs_by_code[code]
        content = await spec.build(ctx)
        if content is not None and len(content.items) >= spec.min_items:
            return content
    return None
