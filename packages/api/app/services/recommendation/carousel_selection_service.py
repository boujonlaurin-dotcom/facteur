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

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.content import UserContentStatus
from app.services.recommendation.carousel_catalog import (
    MAX_CAROUSEL_ITEMS,
    PHASE_B_ORDER,
    PHASE_B_SPECS,
    CarouselBuildContext,
    CarouselContent,
)

# Story 33.5 — un même article ne doit pas revenir dans le carrousel Essentiel
# à quelques jours d'écart (les builders `saved`/`quiet_sources`/`community`/
# `new_source` sont déterministes : sans action utilisateur, ils renvoient
# systématiquement le même top-N). Constante isolée pour rester ajustable.
ESSENTIEL_CAROUSEL_REPEAT_COOLDOWN_DAYS = 7


async def _fetch_recently_shown_ids(
    session: AsyncSession, user_id: UUID
) -> set[UUID]:
    """Content ids déjà présentés via le carrousel Essentiel dans les
    `ESSENTIEL_CAROUSEL_REPEAT_COOLDOWN_DAYS` derniers jours (colonne
    `essentiel_last_shown_at`, écrite par
    `app.routers.essentiel._enrich_essentiel_carousel` après affichage)."""
    cutoff = datetime.datetime.now(datetime.UTC) - datetime.timedelta(
        days=ESSENTIEL_CAROUSEL_REPEAT_COOLDOWN_DAYS
    )
    rows = (
        (
            await session.execute(
                select(UserContentStatus.content_id).where(
                    UserContentStatus.user_id == user_id,
                    UserContentStatus.essentiel_last_shown_at >= cutoff,
                )
            )
        )
        .scalars()
        .all()
    )
    return set(rows)


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

    Story 33.5 — avant de retenir un type, ses items montrés à l'utilisateur
    dans les 7 derniers jours (`_fetch_recently_shown_ids`) sont retirés
    (`CarouselContent.excluding`) ; si ça fait tomber le type sous son seuil, on
    continue vers le suivant de la rotation plutôt que de re-servir un repeat.
    Essentiel-only : `build_phase_b` (Flâner) n'applique pas ce filtre — les
    builders restent surface-indépendants (exclusion `consumed_ids` seule).
    """
    specs_by_code = {spec.code: spec for spec in PHASE_B_SPECS}
    recently_shown_ids = await _fetch_recently_shown_ids(ctx.session, ctx.user_id)
    for code in _rotation_order(ctx.user_id, target_date):
        spec = specs_by_code[code]
        content = await spec.build(ctx)
        if content is None:
            continue
        if recently_shown_ids:
            content = content.excluding(recently_shown_ids, MAX_CAROUSEL_ITEMS)
        if len(content.items) >= spec.min_items:
            return content
    return None
