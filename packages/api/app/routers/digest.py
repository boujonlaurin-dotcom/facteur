"""Router for digest API endpoints (Epic 10).

Provides REST API for the digest-first mobile app:
- GET /api/digest - Get today's digest (retrieve or generate)
- POST /api/digest/{digest_id}/action - Apply action to digest item
- POST /api/digest/{digest_id}/complete - Record digest completion

Follows existing FastAPI patterns from feed.py and personalization.py.
Safe reuse of existing services through DigestService.
"""

import asyncio
import time
from datetime import date
from uuid import UUID

import structlog
from fastapi import APIRouter, Depends, HTTPException, Query, Response
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user_id
from app.schemas.digest import (
    DigestAction,
    DigestActionRequest,
    DigestActionResponse,
    DigestCompletionResponse,
    DigestResponse,
    DualDigestResponse,
)
from app.services.digest_service import DigestService

logger = structlog.get_logger()

router = APIRouter()


class ActionRequest(BaseModel):
    """Simple action request body model."""

    content_id: str
    action: str


@router.get("", response_model=DigestResponse)
async def get_digest(
    response: Response,
    target_date: date | None = Query(
        None, description="Date for digest (default: today)"
    ),
    serein: bool = Query(False, description="Return serene digest variant"),
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """
    Get today's digest for the current user.

    Read-only endpoint: never triggers heavy generation in the request path.
    If today's digest is missing, the most recent cached digest (up to 7 days
    back) is returned instead, while a background task regenerates today's
    digest for the next request. If nothing is cached at all, returns 202 to
    let the mobile retry on a backoff.

    Query Parameters:
    - target_date: Optional specific date (YYYY-MM-DD format). Defaults to today.
    """
    service = DigestService(db)
    user_uuid = UUID(current_user_id)
    start = time.monotonic()

    try:
        digest = await service.get_or_create_digest(
            user_uuid, target_date, is_serene=serein, allow_generation=False
        )
    except Exception:
        elapsed = time.monotonic() - start
        logger.exception(
            "digest_endpoint_unhandled_error",
            user_id=current_user_id,
            elapsed_ms=round(elapsed * 1000, 1),
        )
        raise HTTPException(
            status_code=503,
            detail="Digest generation encountered an unexpected error. Please try again later.",
        )

    elapsed = time.monotonic() - start

    if not digest:
        logger.info(
            "digest_preparing_background",
            user_id=current_user_id,
            elapsed_ms=round(elapsed * 1000, 1),
        )
        response.status_code = 202
        raise HTTPException(
            status_code=202,
            detail="Votre briefing est en cours de préparation. Réessayez dans quelques secondes.",
        )

    logger.info(
        "digest_retrieved",
        user_id=current_user_id,
        elapsed_ms=round(elapsed * 1000, 1),
        items_count=len(digest.items),
        is_completed=digest.is_completed,
    )
    return digest


@router.get("/both", response_model=DualDigestResponse)
async def get_both_digests(
    target_date: date | None = Query(
        None, description="Date for digest (default: today)"
    ),
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """
    Get both digest variants (normal + serene) for instant toggle.

    Read-only endpoint: serves cached content only. Both variants are fetched
    in parallel; if either is missing, the most recent cached one is returned
    while a background task refreshes the cache. Returns 202 if neither
    variant is cached at all.
    """
    service = DigestService(db)
    user_uuid = UUID(current_user_id)
    start = time.monotonic()

    normal, serein, serein_enabled = await asyncio.gather(
        service.get_or_create_digest(
            user_uuid, target_date, is_serene=False, allow_generation=False
        ),
        service.get_or_create_digest(
            user_uuid, target_date, is_serene=True, allow_generation=False
        ),
        service._get_user_serein_enabled(user_uuid),
    )

    elapsed = time.monotonic() - start
    if normal is None and serein is None:
        logger.info(
            "digest_both_preparing_background",
            user_id=current_user_id,
            elapsed_ms=round(elapsed * 1000, 1),
        )
        raise HTTPException(
            status_code=202,
            detail="Votre briefing est en cours de préparation. Réessayez dans quelques secondes.",
        )

    # If only one variant is missing, mirror the available one so the mobile
    # has something to show. The background task will fix it for next time.
    if normal is None:
        normal = serein
    if serein is None:
        serein = normal

    logger.info(
        "digest_both_retrieved",
        user_id=current_user_id,
        elapsed_ms=round(elapsed * 1000, 1),
    )
    return DualDigestResponse(
        normal=normal,
        serein=serein,
        serein_enabled=serein_enabled,
    )


@router.post("/{digest_id}/action", response_model=DigestActionResponse)
async def apply_digest_action(
    digest_id: str,
    request: DigestActionRequest,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """
    Apply an action to an item in the digest.

    Actions:
    - **read**: Mark article as consumed (triggers streak update)
    - **save**: Save article to user's list
    - **not_interested**: Hide article and mute its source (triggers personalization)
    - **undo**: Reset all actions on the item

    Path Parameters:
    - digest_id: ID of the digest

    Request Body:
    - content_id: ID of the content/article
    - action: One of 'read', 'save', 'not_interested', 'undo'

    Note: 'not_interested' automatically adds the source to the user's
    muted sources list (via personalization system).
    """
    service = DigestService(db)
    user_uuid = UUID(current_user_id)
    digest_uuid = UUID(digest_id)
    start = time.monotonic()

    try:
        result = await service.apply_action(
            digest_id=digest_uuid,
            user_id=user_uuid,
            content_id=request.content_id,
            action=request.action,
        )

        elapsed = time.monotonic() - start
        logger.info(
            "digest_action_applied",
            user_id=current_user_id,
            digest_id=digest_id,
            action=request.action.value,
            elapsed_ms=round(elapsed * 1000, 1),
        )

        # Determine message based on action
        messages = {
            DigestAction.READ: "Article marqué comme lu",
            DigestAction.SAVE: "Article sauvegardé",
            DigestAction.LIKE: "Article aimé",
            DigestAction.UNLIKE: "Like retiré",
            DigestAction.NOT_INTERESTED: "Article masqué et source ignorée",
            DigestAction.UNDO: "Action annulée",
        }

        return DigestActionResponse(
            success=result["success"],
            content_id=result["content_id"],
            action=result["action"],
            applied_at=result["applied_at"],
            message=messages.get(request.action, "Action appliquée"),
        )

    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/{digest_id}/complete", response_model=DigestCompletionResponse)
async def complete_digest(
    digest_id: str,
    closure_time_seconds: int | None = Query(
        None, description="Time spent reading in seconds"
    ),
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """
    Record completion of the digest.

    Called when user finishes their daily digest. This endpoint:
    - Records completion stats (read/saved/dismissed counts)
    - Updates closure streak (consecutive days completing digest)
    - Returns updated streak information

    Path Parameters:
    - digest_id: ID of the completed digest

    Query Parameters:
    - closure_time_seconds: Optional time spent in seconds (for analytics)

    Response:
    - success: Whether completion was recorded
    - articles_read: Count of articles marked as read
    - articles_saved: Count of articles saved
    - articles_dismissed: Count dismissed (not interested)
    - closure_streak: Current consecutive completion streak
    - streak_message: Celebration message (e.g., "Série de 7 jours! 🔥")

    Note: Completion is idempotent - calling multiple times for same
    digest on same day won't increment streak multiple times.
    """
    service = DigestService(db)
    user_uuid = UUID(current_user_id)
    digest_uuid = UUID(digest_id)
    start = time.monotonic()

    try:
        result = await service.complete_digest(
            digest_id=digest_uuid,
            user_id=user_uuid,
            closure_time_seconds=closure_time_seconds,
        )

        elapsed = time.monotonic() - start
        logger.info(
            "digest_completed",
            user_id=current_user_id,
            digest_id=digest_id,
            elapsed_ms=round(elapsed * 1000, 1),
            closure_streak=result["closure_streak"],
        )

        return DigestCompletionResponse(
            success=result["success"],
            digest_id=result["digest_id"],
            completed_at=result["completed_at"],
            articles_read=result["articles_read"],
            articles_saved=result["articles_saved"],
            articles_dismissed=result["articles_dismissed"],
            closure_time_seconds=result.get("closure_time_seconds"),
            closure_streak=result["closure_streak"],
            streak_message=result.get("streak_message"),
        )

    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))


@router.post("/generate", response_model=DigestResponse)
async def generate_digest(
    target_date: date | None = Query(
        None, description="Date for digest (default: today)"
    ),
    force: bool = Query(False, description="Force regeneration even if exists"),
    serein: bool = Query(False, description="Generate serene digest variant"),
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """
    Generate a new digest on-demand.

    Explicitly generates a digest for the user. If a digest already exists
    for the date, it will be returned unless force=True.

    Query Parameters:
    - target_date: Optional specific date (default: today)
    - force: If true, regenerates even if digest exists
    - serein: If true, generates the serene variant

    Returns the complete DigestResponse with items (same format as GET endpoint).
    """
    service = DigestService(db)
    user_uuid = UUID(current_user_id)

    # Generate digest, with optional force regeneration
    digest = await service.get_or_create_digest(
        user_uuid,
        target_date,
        force_regenerate=force,
        is_serene=serein,
    )

    if not digest:
        raise HTTPException(status_code=503, detail="Digest generation failed")

    # Return the complete digest response with items
    return digest
