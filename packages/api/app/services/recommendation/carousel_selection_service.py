"""Sélection partagée des carrousels Phase B + rotation date-seedée (Story 32.1).

Deux surfaces (Flâner `GET /api/feed/` et l'Essentiel `GET /api/essentiel`)
partagent :

- `build_phase_b(ctx)` : construit tous les carrousels Phase B éligibles. Ne fait
  QUE l'exclusion des articles consommés → **surface-indépendant** (les deux
  surfaces obtiennent le même ensemble éligible).
- `pick_essentiel_type(user, date, eligible)` : choisit de façon déterministe le
  type mis en avant dans l'Essentiel. Comme l'ensemble éligible est
  surface-indépendant et le seed ne dépend que de `(user, date)`, Flâner recalcule
  le **même** type et l'exclut → complémentarité sans état DB.
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
    """Choix déterministe date-seedé du carrousel mis en avant dans l'Essentiel.

    Rotation seedée sur la **liste fixe** `PHASE_B_ORDER` (4 types), pick du premier
    disponible dans `eligible`. Le seed ne dépend que de `(user_id, target_date)` →
    stable dans la journée, varie chaque jour, identique sur les deux surfaces.

    Note : la rotation porte sur la liste fixe (longueur constante = 4), pas sur
    `len(eligible)`, pour rester robuste à une éligibilité qui varierait d'un item
    au fil de la journée (consommation d'articles).
    """
    eligible_set = set(eligible)
    if not eligible_set:
        return None
    digest = hashlib.md5(f"{user_id}|{target_date.isoformat()}".encode()).hexdigest()
    offset = int(digest, 16) % len(PHASE_B_ORDER)
    rotated = PHASE_B_ORDER[offset:] + PHASE_B_ORDER[:offset]
    for code in rotated:
        if code in eligible_set:
            return code
    return None
