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
from datetime import date, timedelta
from uuid import UUID

import structlog
from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import async_session_maker, get_db
from app.dependencies import get_current_user_id
from app.models.daily_digest import DailyDigest
from app.schemas.digest import (
    DigestAction,
    DigestActionRequest,
    DigestActionResponse,
    DigestCompletionResponse,
    DigestResponse,
    DualDigestResponse,
)
from app.services.community_recommendation_service import (
    CommunityRecommendationService,
)
from app.services.digest_service import DigestService
from app.services.generation_state import is_generation_running
from app.utils.time import today_paris

logger = structlog.get_logger()

router = APIRouter()

# Timeouts for /digest/both — exported as module-level constants so they can
# be monkeypatched in tests. Cf. docs/bugs/bug-infinite-load-requests.md.
# Each variant gets its own bound, and an outer bound protects against a hang
# that slips past the inner one (e.g. a blocking DB fetch outside the inner
# wait_for scope).
DIGEST_BOTH_VARIANT_TIMEOUT_S = 25.0
DIGEST_BOTH_GATHER_TIMEOUT_S = 30.0


class ActionRequest(BaseModel):
    """Simple action request body model."""

    content_id: str
    action: str


async def _enrich_community_carousel(
    db: AsyncSession,
    user_uuid: UUID,
    digest: DigestResponse,
) -> DigestResponse:
    """Add community 🌻 carousel to digest response.

    Fails open: any exception returns `digest` unchanged so the community
    carousel is a purely additive surface and can never break digest loading.
    """
    import datetime

    from app.models.content import UserContentStatus
    from app.schemas.community import CommunityCarouselItem

    try:
        community_service = CommunityRecommendationService(db)
        recent_items = await community_service.get_recent_recommendations(limit=8)

        if not recent_items:
            return digest

        # Build carousel items with user status
        all_ids = [item["content"].id for item in recent_items]
        user_statuses: dict = {}
        if all_ids:
            rows = (
                (
                    await db.execute(
                        select(UserContentStatus).where(
                            UserContentStatus.user_id == user_uuid,
                            UserContentStatus.content_id.in_(all_ids),
                        )
                    )
                )
                .scalars()
                .all()
            )
            for row in rows:
                user_statuses[row.content_id] = {
                    "is_liked": row.is_liked,
                    "is_saved": row.is_saved,
                }

        carousel_items = []
        for item in recent_items:
            content = item["content"]
            if content.source is None:
                continue
            status = user_statuses.get(content.id, {})
            content_type = content.content_type
            source_type = content.source.source_type
            try:
                carousel_items.append(
                    CommunityCarouselItem(
                        content_id=content.id,
                        title=content.title or "",
                        url=content.url or "",
                        thumbnail_url=content.thumbnail_url,
                        description=content.description,
                        content_type=(
                            content_type.value
                            if hasattr(content_type, "value")
                            else str(content_type)
                        ),
                        duration_seconds=content.duration_seconds,
                        # Fallback to now() if null — schema requires a value
                        published_at=(
                            content.published_at or datetime.datetime.now(datetime.UTC)
                        ),
                        source={
                            "id": content.source.id,
                            "name": content.source.name,
                            "logo_url": content.source.logo_url,
                            "type": (
                                source_type.value
                                if hasattr(source_type, "value")
                                else str(source_type)
                            ),
                            "theme": content.source.theme,
                        },
                        sunflower_count=item.get("sunflower_count", 0),
                        is_liked=status.get("is_liked", False),
                        is_saved=status.get("is_saved", False),
                        topics=content.topics or [],
                    )
                )
            except Exception:
                logger.exception(
                    "community_carousel_item_skipped",
                    content_id=str(content.id),
                )

        digest.community_carousel = carousel_items

    except Exception:
        logger.exception("community_carousel_enrichment_failed")

    return digest


@router.get("", response_model=DigestResponse)
async def get_digest(
    target_date: date | None = Query(
        None, description="Date for digest (default: today)"
    ),
    serein: bool = Query(False, description="Return serene digest variant"),
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
    start = time.monotonic()

    # If batch generation is running and no digest exists yet, return 202
    # so the mobile app retries with backoff instead of blocking for 30s+
    if is_generation_running():
        effective_date = target_date or today_paris()
        existing = await db.scalar(
            select(DailyDigest.id).where(
                DailyDigest.user_id == user_uuid,
                DailyDigest.target_date == effective_date,
                DailyDigest.is_serene == serein,
            )
        )
        if not existing:
            logger.info(
                "digest_202_batch_running",
                user_id=current_user_id,
                target_date=str(effective_date),
            )
            return JSONResponse(
                status_code=202,
                content={
                    "status": "preparing",
                    "message": "Votre briefing est en cours de préparation...",
                },
            )

    try:
        digest = await service.get_or_create_digest(
            user_uuid, target_date, is_serene=serein
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
        logger.warning(
            "digest_generation_returned_none",
            user_id=current_user_id,
            elapsed_ms=round(elapsed * 1000, 1),
        )
        raise HTTPException(
            status_code=503, detail="Digest generation failed. Please try again later."
        )

    # Enrich with community carousel
    digest = await _enrich_community_carousel(db, user_uuid, digest)

    logger.info(
        "digest_retrieved",
        user_id=current_user_id,
        elapsed_ms=round(elapsed * 1000, 1),
        items_count=len(digest.items),
        is_completed=digest.is_completed,
        community_carousel_count=len(digest.community_carousel),
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

    Returns both digests in a single response so the mobile app
    can switch between them without a network round-trip.
    """
    user_uuid = UUID(current_user_id)

    # If batch generation is running and no digest exists yet, return 202
    if is_generation_running():
        effective_date = target_date or today_paris()
        existing = await db.scalar(
            select(DailyDigest.id).where(
                DailyDigest.user_id == user_uuid,
                DailyDigest.target_date == effective_date,
                DailyDigest.is_serene.is_(False),
            )
        )
        if not existing:
            logger.info(
                "digest_202_batch_running_both",
                user_id=current_user_id,
                target_date=str(effective_date),
            )
            return JSONResponse(
                status_code=202,
                content={
                    "status": "preparing",
                    "message": "Votre briefing est en cours de préparation...",
                },
            )

    # Generate both variants in parallel with separate DB sessions
    # to avoid SQLAlchemy session conflicts and halve on-demand latency.
    #
    # BUG FIX (bug-infinite-load-requests.md) — each variant is bounded by
    # DIGEST_BOTH_VARIANT_TIMEOUT_S; the whole gather is bounded by
    # DIGEST_BOTH_GATHER_TIMEOUT_S. Without these, a slow upstream (Mistral
    # LLM, Google News RSS, Supabase) hangs the request forever, holds 2 DB
    # sessions, and rapidly exhausts the pool — making *every* other endpoint
    # appear to "load indefinitely".
    async def _gen_variant(is_serene: bool) -> DigestResponse | None:
        async with async_session_maker() as session:
            svc = DigestService(session)
            return await asyncio.wait_for(
                svc.get_or_create_digest(
                    user_uuid, target_date, is_serene=is_serene
                ),
                timeout=DIGEST_BOTH_VARIANT_TIMEOUT_S,
            )

    try:
        normal, serein = await asyncio.wait_for(
            asyncio.gather(
                _gen_variant(False),
                _gen_variant(True),
            ),
            timeout=DIGEST_BOTH_GATHER_TIMEOUT_S,
        )
    except asyncio.TimeoutError:
        logger.warning(
            "digest_both_timeout",
            user_id=current_user_id,
            variant_timeout_s=DIGEST_BOTH_VARIANT_TIMEOUT_S,
            gather_timeout_s=DIGEST_BOTH_GATHER_TIMEOUT_S,
            hint="Upstream hang detected — sessions released to protect pool.",
        )
        raise HTTPException(
            status_code=503,
            detail="digest_generation_timeout",
        )

    # Use the original session for the lightweight preference read
    service = DigestService(db)
    serein_enabled = await service._get_user_serein_enabled(user_uuid)

    # Enrich both variants with community carousel
    if normal:
        normal = await _enrich_community_carousel(db, user_uuid, normal)
    if serein:
        serein = await _enrich_community_carousel(db, user_uuid, serein)

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
            DigestAction.LIKE: "Article recommandé 🌻",
            DigestAction.UNLIKE: "Recommandation retirée",
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


@router.get("/diag")
async def digest_diagnostics(
    target_date: date | None = Query(
        None, description="Date for digest (default: today)"
    ),
    serein: bool = Query(False, description="Check the serene variant"),
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
) -> dict:
    """Diagnostic snapshot for the authenticated user's digest pipeline.

    Returns in a single request everything needed to answer "why is my
    digest broken?":

    - ``today_digest`` / ``yesterday_digest``: existence + format_version
    - ``state``: rows from ``digest_generation_state`` for today (both
      variants). Returns ``"table_missing"`` if migration dg01 isn't applied.
    - ``render_test``: actually invokes ``_build_digest_response`` on the
      existing digest, reporting whether it renders and if not, the
      exception type + message. This is the key signal for detecting a
      corrupted JSONB payload that would otherwise cause a 503 loop.
    - ``migrations``: current alembic revision + presence of the 3
      migration-sensitive tables/columns (td01, dg01, mg03).

    Scoped to the authenticated user only — never accepts a user_id query
    parameter — so this is safe to leave on in production.
    """
    user_uuid = UUID(current_user_id)
    effective_date = target_date or today_paris()
    yesterday = effective_date - timedelta(days=1)

    async def _digest_snapshot(d: date, is_serene: bool) -> dict:
        row = await db.scalar(
            select(DailyDigest).where(
                DailyDigest.user_id == user_uuid,
                DailyDigest.target_date == d,
                DailyDigest.is_serene == is_serene,
            )
        )
        if row is None:
            return {"exists": False}
        return {
            "exists": True,
            "digest_id": str(row.id),
            "format_version": row.format_version,
            "is_serene": row.is_serene,
            "generated_at": row.generated_at.isoformat() if row.generated_at else None,
        }

    today_digest = await _digest_snapshot(effective_date, serein)
    yesterday_digest = await _digest_snapshot(yesterday, serein)

    # State table: may not exist if migration dg01 isn't applied.
    state_info: dict | list
    try:
        from app.models.digest_generation_state import DigestGenerationState

        state_rows = (
            (
                await db.execute(
                    select(DigestGenerationState).where(
                        DigestGenerationState.user_id == user_uuid,
                        DigestGenerationState.target_date == effective_date,
                    )
                )
            )
            .scalars()
            .all()
        )
        state_info = [
            {
                "is_serene": s.is_serene,
                "status": s.status,
                "attempts": s.attempts,
                "last_error": (s.last_error[:200] if s.last_error else None),
                "started_at": s.started_at.isoformat() if s.started_at else None,
                "finished_at": s.finished_at.isoformat() if s.finished_at else None,
            }
            for s in state_rows
        ]
    except Exception as e:
        state_info = {"error": type(e).__name__, "detail": str(e)[:200]}

    # Render test: actually try to build the response from the existing
    # digest so callers can see the exact exception type instead of
    # guessing from a generic 503.
    render_test: dict = {"attempted": False}
    if today_digest.get("exists"):
        render_test = {"attempted": True, "ok": False}
        try:
            svc = DigestService(db)
            digest_row = await db.scalar(
                select(DailyDigest).where(
                    DailyDigest.id == UUID(today_digest["digest_id"])
                )
            )
            if digest_row is not None:
                await svc._build_digest_response(digest_row, user_uuid)
                render_test["ok"] = True
        except Exception as e:
            render_test["error_type"] = type(e).__name__
            render_test["error"] = str(e)[:500]

    # Migration probes: best-effort, degrade gracefully.
    migrations: dict = {}
    try:
        version_row = await db.execute(
            text("SELECT version_num FROM alembic_version LIMIT 1")
        )
        migrations["alembic_version"] = version_row.scalar_one_or_none()
    except Exception as e:
        migrations["alembic_version_error"] = f"{type(e).__name__}: {str(e)[:120]}"

    for table_name, column_name, label in (
        ("sources", "tone", "td01_sources_tone"),
        ("sources", "serein_default", "td01_sources_serein_default"),
        ("digest_generation_state", None, "dg01_digest_generation_state"),
        ("editorial_highlights_history", None, "dg01_editorial_highlights_history"),
    ):
        try:
            if column_name:
                probe = await db.execute(
                    text(
                        "SELECT 1 FROM information_schema.columns "
                        "WHERE table_name = :t AND column_name = :c"
                    ),
                    {"t": table_name, "c": column_name},
                )
            else:
                probe = await db.execute(
                    text(
                        "SELECT 1 FROM information_schema.tables WHERE table_name = :t"
                    ),
                    {"t": table_name},
                )
            migrations[label] = probe.scalar_one_or_none() is not None
        except Exception as e:
            migrations[label] = f"error: {type(e).__name__}"
            logger.warning(
                "digest_diag_migration_probe_failed",
                label=label,
                error=str(e),
            )

    return {
        "user_id": current_user_id,
        "target_date": str(effective_date),
        "serein": serein,
        "today_digest": today_digest,
        "yesterday_digest": yesterday_digest,
        "state": state_info,
        "render_test": render_test,
        "migrations": migrations,
    }
