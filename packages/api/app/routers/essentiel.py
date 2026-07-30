"""Router pour `GET /api/essentiel` (Story 9.1).

Renvoie les 5 articles transversaux du jour pour la carte hi-fi "L'Essentiel
du jour" du feed mobile.

Strictement read-only : pas de pipeline LLM au request time. Réutilise la
chaîne de fallback de `/api/digest` via `read_digest_or_fallback`.
"""

import asyncio
import contextlib
import time
from datetime import date
from uuid import UUID

import structlog
from fastapi import APIRouter, Depends, Query
from fastapi.responses import JSONResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db, safe_async_session
from app.dependencies import get_current_user_id
from app.models.content import UserContentStatus
from app.models.enums import ContentStatus
from app.schemas.essentiel import EssentielResponse
from app.schemas.feed import CarouselInfo, CarouselItemBadge
from app.services.digest_service import DigestService, read_digest_or_fallback
from app.services.essentiel_service import (
    ESSENTIEL_MIN_ARTICLES,
    build_essentiel_response_with_supplements,
    fetch_user_essentiel_context,
)
from app.services.recommendation.carousel_catalog import (
    MAX_CAROUSEL_ITEMS,
    CarouselBuildContext,
)
from app.services.recommendation.carousel_selection_service import (
    build_phase_b,
    pick_essentiel_type,
)
from app.utils.time import today_paris

logger = structlog.get_logger()

router = APIRouter()


def _preparing_response() -> JSONResponse:
    return JSONResponse(
        status_code=202,
        content={
            "status": "preparing",
            "message": "Votre essentiel est en cours de préparation...",
        },
    )


# Nombre min d'items du carrousel Essentiel APRÈS retrait des 5 articles déjà
# affichés dans la carte — en-deçà, on n'attache pas de carrousel (évite un
# scroller à 1 item).
_MIN_ESSENTIEL_CAROUSEL_ITEMS = 2


async def _enrich_essentiel_carousel(
    db: AsyncSession,
    user_uuid: UUID,
    response: EssentielResponse,
    effective_date: date,
) -> EssentielResponse:
    """Attache le carrousel semi-éditorialisé du jour à la réponse Essentiel.

    Story 32.1 — mutualise la Phase B des carrousels de Flâner via le catalogue
    partagé. Le type mis en avant est choisi de façon déterministe (rotation
    date-seedée sur `(user, date_paris)`) ; Flâner retire ce même type le même
    jour → complémentarité cross-surface sans état DB.

    Fail-open : toute exception laisse `response` inchangée (le carrousel est une
    surface purement additive, il ne peut jamais casser le chargement de
    l'Essentiel). Skip hors édition du jour (rewind J-7 en lecture seule).
    """
    if effective_date != today_paris():
        return response

    try:
        consumed_ids = set(
            (
                await db.execute(
                    select(UserContentStatus.content_id).where(
                        UserContentStatus.user_id == user_uuid,
                        UserContentStatus.status == ContentStatus.CONSUMED,
                    )
                )
            )
            .scalars()
            .all()
        )
        ctx = CarouselBuildContext(
            session=db,
            session_maker=safe_async_session,
            user_id=user_uuid,
            consumed_ids=consumed_ids,
        )
        contents = await build_phase_b(ctx)
        essentiel_type = pick_essentiel_type(
            user_uuid, effective_date, set(contents.keys())
        )
        content = contents.get(essentiel_type) if essentiel_type else None
        if content is None:
            return response

        # Ne pas re-servir les 5 articles déjà affichés dans la carte Essentiel.
        shown_ids = {a.content_id for a in response.articles}
        content = content.excluding(shown_ids, MAX_CAROUSEL_ITEMS)
        if len(content.items) < _MIN_ESSENTIEL_CAROUSEL_ITEMS:
            return response

        response.carousel = CarouselInfo(
            carousel_type=content.carousel_type,
            title=content.title,
            emoji=content.emoji,
            position=0,  # slot dédié côté mobile ; non pertinent pour l'Essentiel
            items=content.items,
            badges=[CarouselItemBadge(**b) for b in content.badges],
        )
    except Exception:
        logger.exception("essentiel_carousel_enrichment_failed")
        # Mirror `_enrich_community_carousel` (digest.py) : handler fail-open →
        # get_db ne voit jamais le raise, donc on rollback nous-mêmes la session
        # potentiellement salie. Rollback borné : sur une conn tuée par Supabase,
        # asyncpg peut hang indéfiniment (statement_timeout ne couvre pas ROLLBACK)
        # → sur timeout, invalidate force le drop de la conn morte du pool.
        try:
            await asyncio.wait_for(db.rollback(), timeout=2.0)
        except (TimeoutError, Exception) as rb_exc:
            logger.debug("essentiel_carousel_rollback_failed", error=str(rb_exc))
            with contextlib.suppress(Exception):
                await asyncio.wait_for(db.invalidate(), timeout=1.0)

    return response


@router.get("", response_model=EssentielResponse)
async def get_essentiel(
    target_date: date | None = Query(
        None, description="Date for essentiel (default: today)"
    ),
    serein: bool | None = Query(
        None,
        description=(
            "Force le mode serein (true/false). Absent ⇒ lecture de la "
            "préférence DB. Permet au client de demander le bon mode sans "
            "dépendre de la persistance de la préférence au moment du refetch."
        ),
    ),
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Retourne les 5 articles transversaux du jour pour l'utilisateur courant.

    Source de vérité : la `DigestResponse` calculée par la cron nocturne
    (variante `pour_vous`). Projection cross-topic via `build_essentiel_response`.

    Renvoie 202 ``preparing`` si la chaîne de fallback du digest est épuisée.
    """
    user_uuid = UUID(current_user_id)
    effective_date = target_date or today_paris()
    start = time.monotonic()

    service = DigestService(db)
    # Override explicite par le client (symétrie avec `?serein=` du feed) ;
    # fallback DB conservé pour rétrocompat des clients qui ne l'envoient pas.
    serein_enabled = (
        serein
        if serein is not None
        else await service.get_user_serein_enabled(user_uuid)
    )
    digest = await read_digest_or_fallback(
        db, user_uuid, effective_date, is_serene=serein_enabled
    )
    if digest is None:
        return _preparing_response()

    # Re-rank user-aware : charge les sources suivies + topics suivis pour
    # promouvoir les articles qui matchent les prefs de l'utilisateur.
    # Pas de pipeline LLM, juste 2 SELECTs courts indexés sur `user_id`.
    user_context = await fetch_user_essentiel_context(db, user_uuid)
    response = await build_essentiel_response_with_supplements(
        db,
        user_uuid,
        digest,
        user_context=user_context,
        is_serene=serein_enabled,
    )

    # Plancher de qualité : on n'expose jamais une carte Essentiel pauvre
    # (1-2 articles). Si la complétion depuis les sources suivies n'a pas
    # atteint 3 articles, on signale au client que l'essentiel se prépare.
    if len(response.articles) < ESSENTIEL_MIN_ARTICLES:
        return _preparing_response()

    # Carrousel semi-éditorialisé du jour (Story 32.1) — mutualisé avec Flâner.
    # Additif et fail-open : n'altère jamais les 5 articles ni le code de statut.
    response = await _enrich_essentiel_carousel(db, user_uuid, response, effective_date)

    logger.info(
        "essentiel_retrieved",
        user_id=current_user_id,
        elapsed_ms=round((time.monotonic() - start) * 1000, 1),
        articles_count=len(response.articles),
        is_stale_fallback=response.is_stale_fallback,
        serein_enabled=serein_enabled,
        followed_sources_count=len(user_context.followed_source_ids),
        topic_weights_count=len(user_context.topic_weights),
    )
    return response
