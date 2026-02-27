"""Routes sources."""

import re
from uuid import UUID

import structlog
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user_id
from app.models.failed_source_attempt import FailedSourceAttempt
from app.schemas.source import (
    SourceCatalogResponse,
    SourceCreate,
    SourceDetectRequest,
    SourceDetectResponse,
    SourceResponse,
    SourceSearchResponse,
)
from app.services.source_service import SourceService

logger = structlog.get_logger()

router = APIRouter()


@router.get("", response_model=SourceCatalogResponse)
async def get_sources(
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> SourceCatalogResponse:
    """Récupérer toutes les sources (curées + custom)."""
    service = SourceService(db)
    sources = await service.get_all_sources(user_id)

    return sources


@router.get("/catalog", response_model=list[SourceResponse])
async def get_catalog(
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> list[SourceResponse]:
    """Récupérer le catalogue des sources curées."""
    service = SourceService(db)
    sources = await service.get_curated_sources(user_id)

    return sources


@router.get("/trending", response_model=list[SourceResponse])
async def get_trending_sources(
    limit: int = 10,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> list[SourceResponse]:
    """Récupérer les sources les plus populaires de la communauté."""
    service = SourceService(db)
    sources = await service.get_trending_sources(user_id=user_id, limit=limit)
    return sources


@router.post("/custom", response_model=SourceResponse)
async def add_source(
    data: SourceCreate,
    background_tasks: BackgroundTasks,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> SourceResponse:
    """Ajouter une source personnalisée."""
    service = SourceService(db)

    try:
        source = await service.add_custom_source(user_id, str(data.url), data.name)

        # Trigger immediate sync in background after request returns (and DB commits)
        from app.workers.rss_sync import sync_source

        background_tasks.add_task(sync_source, str(source.id))

        return source
    except ValueError as e:
        # Log failed custom source attempt
        attempt = FailedSourceAttempt(
            user_id=UUID(user_id),
            input_text=str(data.url)[:500],
            input_type="url",
            endpoint="custom",
            error_message=str(e)[:1000],
        )
        db.add(attempt)
        await db.flush()
        logger.info(
            "failed_source_attempt", endpoint="custom", input=str(data.url)[:100]
        )
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e),
        )


@router.delete("/{source_id}")
async def delete_source(
    source_id: UUID,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> dict[str, str]:
    """Supprimer une source personnalisée."""
    service = SourceService(db)
    deleted = await service.delete_custom_source(user_id, str(source_id))

    if not deleted:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Source not found or not owned by user",
        )

    return {"status": "deleted"}


@router.post("/detect", response_model=SourceDetectResponse | SourceSearchResponse)
async def detect_source(
    data: SourceDetectRequest,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> SourceDetectResponse | SourceSearchResponse:
    """Détecter le type d'une URL source ou chercher par mot-clé."""
    service = SourceService(db)

    try:
        url_input = data.url.strip()

        # Robust URL detection: checks for protocol or a string that looks like a domain (e.g. domain.tld)
        is_url_like = (
            url_input.startswith("http://")
            or url_input.startswith("https://")
            or "youtube.com" in url_input
            or "youtu.be" in url_input
            or re.match(r"^[\w\.-]+\.[a-z]{2,6}(/.*)?$", url_input.lower())
        )

        if is_url_like and not url_input.startswith("http"):
            url_input = "https://" + url_input

        if is_url_like:
            result = await service.detect_source(url_input)
            return result
        else:
            # It's a keyword search
            results = await service.search_sources(url_input, user_id=user_id)
            return SourceSearchResponse(results=results)
    except ValueError as e:
        # Log failed detect/search attempt
        attempt = FailedSourceAttempt(
            user_id=UUID(user_id),
            input_text=data.url.strip()[:500],
            input_type="url" if is_url_like else "keyword",
            endpoint="detect",
            error_message=str(e)[:1000],
        )
        db.add(attempt)
        await db.flush()
        logger.info(
            "failed_source_attempt", endpoint="detect", input=data.url.strip()[:100]
        )
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e),
        )


@router.post("/{source_id}/trust")
async def trust_source(
    source_id: UUID,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> dict[str, str]:
    """Ajouter une source aux sources de confiance."""
    service = SourceService(db)
    success = await service.trust_source(user_id, str(source_id))

    if not success:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Source not found",
        )

    return {"status": "trusted"}


@router.delete("/{source_id}/trust")
async def untrust_source(
    source_id: UUID,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> dict[str, str]:
    """Retirer une source des sources de confiance."""
    service = SourceService(db)
    success = await service.untrust_source(user_id, str(source_id))

    if not success:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Source not found or not trusted",
        )

    return {"status": "untrusted"}
