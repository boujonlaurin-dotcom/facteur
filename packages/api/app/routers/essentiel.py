"""Router pour `GET /api/essentiel` (Story 9.1).

Renvoie les 5 articles transversaux du jour pour la carte hi-fi "L'Essentiel
du jour" du feed mobile.

Strictement read-only : pas de pipeline LLM au request time. Réutilise la
chaîne de fallback de `/api/digest` via `read_digest_or_fallback`.
"""

import asyncio
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
from app.schemas.essentiel_letter import EssentielLetter
from app.services.digest_service import DigestService, read_digest_or_fallback
from app.services.essentiel_letter_service import (
    generate_letter,
    load_letter_row,
    rehydrate_snapshot,
    store_letter,
)
from app.services.essentiel_service import (
    ESSENTIEL_MIN_ARTICLES,
    EssentielUserContext,
    build_essentiel_response_with_supplements,
    fetch_user_essentiel_context,
)
from app.utils.time import today_paris

logger = structlog.get_logger()

router = APIRouter()

# Budget on-demand pour la lettre (précédent : budget LLM 8s de l'onboarding).
# Timeout/échec → `letter=None`, la réponse actuelle part inchangée.
ESSENTIEL_LETTER_ON_DEMAND_TIMEOUT_S = 8.0


async def _letter_response_from_row(
    db: AsyncSession,
    user_uuid: UUID,
    effective_date: date,
    row,
) -> EssentielResponse:
    """Projette une ligne `essentiel_letters` en réponse complète.

    La lettre est figée pour la journée : `articles` = son snapshot, seuls
    les flags de statut (is_read/is_saved/…) sont réhydratés.
    """
    return EssentielResponse(
        target_date=effective_date,
        generated_at=row.generated_at,
        articles=await rehydrate_snapshot(db, user_uuid, row.articles),
        letter=EssentielLetter.model_validate(row.letter),
    )


async def _serve_stored_letter(
    db: AsyncSession,
    user_uuid: UUID,
    effective_date: date,
    serein_enabled: bool,
) -> EssentielResponse | None:
    """Chemin nominal après 08h : sert la lettre stockée `(user, date, serein)`.

    Court-circuite entièrement la reconstruction de l'essentiel (digest,
    re-rank user-aware, suppléments) — le snapshot de la lettre est la source
    de vérité de la journée. None si aucune lettre stockée.
    """
    row = await load_letter_row(db, user_uuid, effective_date, serein_enabled)
    if row is None:
        return None
    return await _letter_response_from_row(db, user_uuid, effective_date, row)


async def _attach_letter_on_demand(
    db: AsyncSession,
    user_uuid: UUID,
    effective_date: date,
    serein_enabled: bool,
    response: EssentielResponse,
    user_context: EssentielUserContext,
) -> EssentielResponse:
    """Génération on-demand de la lettre (Story 9.6), en secours du job.

    Uniquement pour la date du jour hors fallback stale ; dates passées =
    lecture seule (gérée en amont par `_serve_stored_letter`). Race avec le
    job → ON CONFLICT DO NOTHING + re-read. Tout échec/timeout est avalé :
    `letter=None` et la réponse actuelle part inchangée (fallback carte 5
    articles côté mobile).
    """
    if effective_date != today_paris() or response.is_stale_fallback:
        return response
    try:
        # Seul l'appel LLM (pur, sans session DB) est sous timeout : le
        # stockage reste hors budget pour ne jamais annuler un commit.
        letter = await asyncio.wait_for(
            generate_letter(
                response.articles,
                followed_themes=user_context.followed_themes_by_weight(),
                is_serene=serein_enabled,
            ),
            timeout=ESSENTIEL_LETTER_ON_DEMAND_TIMEOUT_S,
        )
    except TimeoutError:
        logger.info(
            "essentiel_letter_on_demand_timeout",
            user_id=str(user_uuid),
            serein=serein_enabled,
        )
        return response
    except Exception:
        logger.exception("essentiel_letter_on_demand_failed", user_id=str(user_uuid))
        return response
    if letter is None:
        return response
    await store_letter(
        db,
        user_id=user_uuid,
        target_date=effective_date,
        is_serene=serein_enabled,
        letter=letter,
        articles=response.articles,
    )
    # Re-read : en cas de course avec le job nocturne, la ligne gagnante
    # (ON CONFLICT DO NOTHING) est la source de vérité.
    row = await load_letter_row(db, user_uuid, effective_date, serein_enabled)
    if row is None:
        return response
    return await _letter_response_from_row(db, user_uuid, effective_date, row)


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

    # Lettre du jour (Story 9.6) : si elle est stockée, elle EST la réponse
    # (snapshot figé + flags réhydratés) — on court-circuite le rebuild
    # digest/re-rank/suppléments. Tout échec retombe sur le chemin actuel.
    try:
        stored = await _serve_stored_letter(
            db, user_uuid, effective_date, serein_enabled
        )
    except Exception:
        stored = None
        logger.exception("essentiel_letter_read_failed", user_id=current_user_id)
    if stored is not None:
        logger.info(
            "essentiel_retrieved",
            user_id=current_user_id,
            elapsed_ms=round((time.monotonic() - start) * 1000, 1),
            articles_count=len(stored.articles),
            is_stale_fallback=False,
            serein_enabled=serein_enabled,
            letter_served="stored",
        )
        return stored

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

    # Pas de lettre stockée : génération on-demand bornée (date du jour only).
    # Tout échec laisse `letter=None` → le mobile rend la carte actuelle.
    try:
        response = await _attach_letter_on_demand(
            db, user_uuid, effective_date, serein_enabled, response, user_context
        )
    except Exception:
        logger.exception("essentiel_letter_attach_failed", user_id=current_user_id)

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
