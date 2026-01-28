"""Routes sources."""

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user_id
from app.schemas.source import (
    SourceCatalogResponse,
    SourceCreate,
    SourceDetectRequest,
    SourceDetectResponse,
    SourceResponse,
)
from app.services.source_service import SourceService

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


@router.post("/custom", response_model=SourceResponse)
async def add_source(
    data: SourceCreate,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> SourceResponse:
    """Ajouter une source personnalisée."""
    service = SourceService(db)

    try:
        source = await service.add_custom_source(user_id, str(data.url), data.name)
        return source
    except ValueError as e:
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


@router.post("/detect", response_model=SourceDetectResponse)
async def detect_source(
    data: SourceDetectRequest,
    db: AsyncSession = Depends(get_db),
) -> SourceDetectResponse:
    """Détecter le type d'une URL source."""
    service = SourceService(db)

    try:
        result = await service.detect_source(str(data.url))
        return result
    except ValueError as e:
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
