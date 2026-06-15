"""Router pour `GET /api/essentiel` (Story 9.1).

Renvoie les 5 articles transversaux du jour pour la carte hi-fi "L'Essentiel
du jour" du feed mobile.

Strictement read-only : pas de pipeline LLM au request time. Réutilise la
chaîne de fallback de `/api/digest` via `read_digest_or_fallback`.
"""

import time
from datetime import date
from uuid import UUID

import structlog
from fastapi import APIRouter, Depends, Query
from fastapi.responses import JSONResponse
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user_id
from app.schemas.essentiel import EssentielResponse
from app.services.digest_service import DigestService, read_digest_or_fallback
from app.services.essentiel_service import (
    build_essentiel_response,
    fetch_user_essentiel_context,
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


@router.get("", response_model=EssentielResponse)
async def get_essentiel(
    target_date: date | None = Query(
        None, description="Date for essentiel (default: today)"
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
    serein_enabled = await service.get_user_serein_enabled(user_uuid)
    digest = await read_digest_or_fallback(
        db, user_uuid, effective_date, is_serene=serein_enabled
    )
    if digest is None:
        return _preparing_response()

    # Re-rank user-aware : charge les sources suivies + topics suivis pour
    # promouvoir les articles qui matchent les prefs de l'utilisateur.
    # Pas de pipeline LLM, juste 2 SELECTs courts indexés sur `user_id`.
    user_context = await fetch_user_essentiel_context(db, user_uuid)
    response = build_essentiel_response(digest, user_context=user_context)

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
