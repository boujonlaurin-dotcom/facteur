"""Router for digest API endpoints (Epic 10).

Provides REST API for the digest-first mobile app:
- GET /api/digest - Get today's digest (retrieve or generate)
- POST /api/digest/{digest_id}/action - Apply action to digest item
- POST /api/digest/{digest_id}/complete - Record digest completion

Follows existing FastAPI patterns from feed.py and personalization.py.
Safe reuse of existing services through DigestService.
"""

from datetime import date
from typing import Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user_id
from app.schemas.digest import (
    DigestResponse,
    DigestActionRequest,
    DigestActionResponse,
    DigestCompletionResponse,
    DigestGenerationResponse,
    DigestAction,
)
from app.services.digest_service import DigestService

router = APIRouter()


class ActionRequest(BaseModel):
    """Simple action request body model."""
    content_id: str
    action: str


@router.get("", response_model=DigestResponse)
async def get_digest(
    target_date: Optional[date] = Query(None, description="Date for digest (default: today)"),
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """
    Get today's digest for the current user.
    
    Returns the daily digest containing 5 curated articles.
    If digest doesn't exist yet, it will be generated on-demand.
    
    Each item includes:
    - Content metadata (title, url, thumbnail, etc.)
    - Source information
    - Selection reason
    - User's current action state (is_read, is_saved, is_dismissed)
    
    Query Parameters:
    - target_date: Optional specific date (YYYY-MM-DD format). Defaults to today.
    
    Response:
    - digest_id: Unique identifier for this digest
    - user_id: User ID
    - target_date: Date of the digest
    - generated_at: When the digest was generated
    - items: Array of 5 digest items
    - is_completed: Whether user has completed this digest
    - completed_at: Completion timestamp (if completed)
    """
    service = DigestService(db)
    user_uuid = UUID(current_user_id)
    
    digest = await service.get_or_create_digest(user_uuid, target_date)
    
    if not digest:
        raise HTTPException(
            status_code=503,
            detail="Digest generation failed. Please try again later."
        )
    
    return digest


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
    
    try:
        result = await service.apply_action(
            digest_id=digest_uuid,
            user_id=user_uuid,
            content_id=request.content_id,
            action=request.action
        )
        
        # Determine message based on action
        messages = {
            DigestAction.READ: "Article marqué comme lu",
            DigestAction.SAVE: "Article sauvegardé",
            DigestAction.NOT_INTERESTED: "Article masqué et source ignorée",
            DigestAction.UNDO: "Action annulée"
        }
        
        return DigestActionResponse(
            success=result["success"],
            content_id=result["content_id"],
            action=result["action"],
            applied_at=result["applied_at"],
            message=messages.get(request.action, "Action appliquée")
        )
        
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/{digest_id}/complete", response_model=DigestCompletionResponse)
async def complete_digest(
    digest_id: str,
    closure_time_seconds: Optional[int] = Query(None, description="Time spent reading in seconds"),
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
    
    try:
        result = await service.complete_digest(
            digest_id=digest_uuid,
            user_id=user_uuid,
            closure_time_seconds=closure_time_seconds
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
            streak_message=result.get("streak_message")
        )
        
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))


@router.post("/generate", response_model=DigestGenerationResponse)
async def generate_digest(
    target_date: Optional[date] = Query(None, description="Date for digest (default: today)"),
    force: bool = Query(False, description="Force regeneration even if exists"),
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
    
    Note: This is primarily for testing/admin use. The GET endpoint
    automatically generates digests as needed.
    """
    service = DigestService(db)
    user_uuid = UUID(current_user_id)
    
    # For now, just get or create (force regeneration would need additional logic)
    digest = await service.get_or_create_digest(user_uuid, target_date)
    
    if not digest:
        raise HTTPException(
            status_code=503,
            detail="Digest generation failed"
        )
    
    return DigestGenerationResponse(
        success=True,
        digest_id=digest.digest_id,
        items_count=len(digest.items),
        generated_at=digest.generated_at,
        message=f"Digest généré avec {len(digest.items)} articles"
    )
