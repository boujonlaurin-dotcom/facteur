"""Routes — système d'intérêts unifié (Story 22.1).

Endpoints monté sous `/api/user/interests`. Couvrent l'écran « Mes intérêts »
côté mobile (Thèmes + Sujets + favoris ordonnés). Symétrique pour Sources :
voir `app/routers/user_sources_state.py`.

Cap (3 favoris pour les intérêts) appliqué par le service ; un dépassement
remonte en HTTP 422 avec body `{error: "favorite_cap_reached", cap: 3}`.
"""

from uuid import UUID

import structlog
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.constants import FAVORITE_CAP
from app.database import get_db
from app.dependencies import get_current_user_id
from app.schemas.user_interests import (
    ReorderFavoritesRequest,
    SetInterestStateRequest,
    UserInterestsResponse,
)
from app.services.feed_cache import FEED_CACHE
from app.services.posthog_client import get_posthog_client
from app.services.sources_cache import SOURCES_CACHE
from app.services.user_interests_service import (
    CustomTopicFavoriteForbidden,
    FavoriteCapReached,
    TargetNotFavorite,
    TargetNotFound,
    UserInterestsService,
)

logger = structlog.get_logger(__name__)

router = APIRouter()


def _invalidate_user_caches(user_uuid: UUID) -> None:
    """Le state d'un intérêt influe à la fois sur le feed et sur l'écran sources."""
    FEED_CACHE.invalidate(user_uuid)
    SOURCES_CACHE.invalidate(user_uuid)


@router.get("", response_model=UserInterestsResponse)
async def get_user_interests(
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> UserInterestsResponse:
    """État courant des Thèmes + Sujets + favoris ordonnés."""
    return await UserInterestsService(db).get_interests(UUID(user_id))


@router.patch("", response_model=UserInterestsResponse)
async def set_interest_state(
    body: SetInterestStateRequest,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> UserInterestsResponse:
    user_uuid = UUID(user_id)
    service = UserInterestsService(db)

    try:
        prev_state = await service.set_state(
            user_id=user_uuid,
            kind=body.kind,
            target_id=body.target_id,
            state=body.state,
            position=body.position,
        )
    except CustomTopicFavoriteForbidden as e:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={"error": "custom_topic_favorite_forbidden"},
        ) from e
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
            "kind": body.kind,
            "target_id": body.target_id,
            "new_state": body.state.value,
            "prev_state": prev_state.value if prev_state else None,
        },
    )
    return await service.get_interests(user_uuid)


@router.post("/reorder", response_model=UserInterestsResponse)
async def reorder_favorites(
    body: ReorderFavoritesRequest,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> UserInterestsResponse:
    user_uuid = UUID(user_id)
    service = UserInterestsService(db)

    try:
        await service.reorder_favorites(user_uuid, body.favorites)
    except CustomTopicFavoriteForbidden as e:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={"error": "custom_topic_favorite_forbidden"},
        ) from e
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
        properties={"favorite_count": len(body.favorites), "kind": "interests"},
    )
    return await service.get_interests(user_uuid)
