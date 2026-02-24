"""Router collections de sauvegardes."""

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user_id
from app.schemas.collection import (
    CollectionCreate,
    CollectionItemAdd,
    CollectionResponse,
    CollectionUpdate,
    SavedSummaryResponse,
)
from app.services.collection_service import CollectionService

router = APIRouter()


@router.get("/", response_model=list[CollectionResponse])
async def list_collections(
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Liste les collections de l'utilisateur avec métadonnées."""
    service = CollectionService(db)
    user_uuid = UUID(current_user_id)
    return await service.list_collections(user_uuid)


@router.post(
    "/", response_model=CollectionResponse, status_code=status.HTTP_201_CREATED
)
async def create_collection(
    data: CollectionCreate,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Crée une nouvelle collection."""
    service = CollectionService(db)
    user_uuid = UUID(current_user_id)

    try:
        collection = await service.create_collection(user_uuid, data.name)
        await db.commit()
        return {
            "id": collection.id,
            "name": collection.name,
            "position": collection.position,
            "item_count": 0,
            "read_count": 0,
            "thumbnails": [],
            "created_at": collection.created_at,
        }
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))


# IMPORTANT: /saved-summary MUST be before /{collection_id} routes
# to avoid FastAPI interpreting "saved-summary" as a UUID path parameter
@router.get("/saved-summary", response_model=SavedSummaryResponse)
async def get_saved_summary(
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Résumé des sauvegardes pour les nudges."""
    service = CollectionService(db)
    user_uuid = UUID(current_user_id)
    return await service.get_saved_summary(user_uuid)


@router.patch("/{collection_id}", response_model=CollectionResponse)
async def update_collection(
    collection_id: UUID,
    data: CollectionUpdate,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Renomme une collection."""
    service = CollectionService(db)
    user_uuid = UUID(current_user_id)

    try:
        collection = await service.update_collection(
            user_uuid, collection_id, data.name
        )
        await db.commit()
        # Re-fetch full data
        collections = await service.list_collections(user_uuid)
        return next(c for c in collections if c["id"] == collection.id)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(e))


@router.delete("/{collection_id}", status_code=status.HTTP_200_OK)
async def delete_collection(
    collection_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Supprime une collection (les articles restent sauvegardés)."""
    service = CollectionService(db)
    user_uuid = UUID(current_user_id)

    try:
        await service.delete_collection(user_uuid, collection_id)
        await db.commit()
        return {"status": "ok"}
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(e))


@router.get("/{collection_id}/items")
async def get_collection_items(
    collection_id: UUID,
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    sort: str = Query("recent", pattern="^(recent|oldest|source|theme)$"),
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Articles d'une collection paginés."""
    service = CollectionService(db)
    user_uuid = UUID(current_user_id)

    try:
        items = await service.get_collection_items(
            user_uuid, collection_id, limit=limit, offset=offset, sort=sort
        )
        return {"items": items}
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(e))


@router.post("/{collection_id}/items", status_code=status.HTTP_201_CREATED)
async def add_collection_item(
    collection_id: UUID,
    data: CollectionItemAdd,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Ajoute un article à une collection."""
    service = CollectionService(db)
    user_uuid = UUID(current_user_id)

    try:
        item = await service.add_to_collection(
            user_uuid, collection_id, data.content_id
        )
        await db.commit()
        return {"status": "ok", "item_id": str(item.id)}
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(e))


@router.delete("/{collection_id}/items/{content_id}", status_code=status.HTTP_200_OK)
async def remove_collection_item(
    collection_id: UUID,
    content_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Retire un article d'une collection."""
    service = CollectionService(db)
    user_uuid = UUID(current_user_id)

    try:
        await service.remove_from_collection(user_uuid, collection_id, content_id)
        await db.commit()
        return {"status": "ok"}
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(e))
