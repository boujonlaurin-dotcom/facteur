"""Routes — état déclaré des Sources (Story 22.1).

Endpoints monté sous `/api/user/sources` (distinct du router `sources.py` monté
sous `/api/sources` qui sert le catalogue + endpoints legacy `PUT /weight`).
Couvre l'écran « Mes sources » côté mobile (liste + favoris ordonnés, cap=5
indépendant des intérêts).
"""

from uuid import UUID

import structlog
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.constants import FAVORITE_CAP
from app.database import get_db
from app.dependencies import get_current_user_id
from app.schemas.user_interests import (
    ReorderSourceFavoritesRequest,
    SetSourceStateRequest,
    UserSourcesStateResponse,
)
from app.services.feed_cache import FEED_CACHE
from app.services.posthog_client import get_posthog_client
from app.services.sources_cache import SOURCES_CACHE
from app.services.user_interests_service import (
    FavoriteCapReached,
    TargetNotFavorite,
    TargetNotFound,
    UserSourcesStateService,
)

logger = structlog.get_logger(__name__)

router = APIRouter()


def _invalidate_user_caches(user_uuid: UUID) -> None:
    FEED_CACHE.invalidate(user_uuid)
    SOURCES_CACHE.invalidate(user_uuid)


@router.get("", response_model=UserSourcesStateResponse)
async def get_user_sources_state(
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> UserSourcesStateResponse:
    return await UserSourcesStateService(db).get_sources_state(UUID(user_id))


@router.patch("", response_model=UserSourcesStateResponse)
async def set_source_state(
    body: SetSourceStateRequest,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> UserSourcesStateResponse:
    user_uuid = UUID(user_id)
    service = UserSourcesStateService(db)

    try:
        prev_state = await service.set_state(
            user_id=user_uuid,
            source_id=body.source_id,
            state=body.state,
            position=body.position,
        )
    except FavoriteCapReached as e:
        get_posthog_client().capture(
            user_id=user_uuid,
            event="interest_cap_blocked",
            properties={
                "kind": e.kind,
                "target_id": e.target_id,
                "current_count": e.current_count,
            },
        )
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={"error": "favorite_cap_reached", "cap": FAVORITE_CAP},
        ) from e
    except TargetNotFound as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(e)) from e

    _invalidate_user_caches(user_uuid)
    get_posthog_client().capture(
        user_id=user_uuid,
        event="interest_state_changed",
        properties={
            "kind": "source",
            "target_id": str(body.source_id),
            "new_state": body.state.value,
            "prev_state": prev_state.value if prev_state else None,
        },
    )
    return await service.get_sources_state(user_uuid)


@router.post("/reorder", response_model=UserSourcesStateResponse)
async def reorder_source_favorites(
    body: ReorderSourceFavoritesRequest,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> UserSourcesStateResponse:
    user_uuid = UUID(user_id)
    service = UserSourcesStateService(db)

    try:
        await service.reorder_favorites(user_uuid, body.favorites)
    except TargetNotFavorite as e:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(e)
        ) from e
    except TargetNotFound as e:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(e)) from e

    _invalidate_user_caches(user_uuid)
    get_posthog_client().capture(
        user_id=user_uuid,
        event="interest_favorite_reordered",
        properties={"favorite_count": len(body.favorites), "kind": "sources"},
    )
    return await service.get_sources_state(user_uuid)
