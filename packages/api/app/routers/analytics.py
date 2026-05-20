"""Router pour les analytics."""

from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, BackgroundTasks, Depends, Header
from pydantic import BaseModel, Field
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db, safe_async_session
from app.dependencies import get_current_user_id
from app.services.analytics_service import AnalyticsService

router = APIRouter(tags=["Analytics"])


class EventCreate(BaseModel):
    """Schéma de création d'événement."""

    event_type: str = Field(..., description="Type d'événement (ex: session_start)")
    event_data: dict = Field(default_factory=dict, description="Données de l'événement")
    device_id: str | None = Field(None, description="Identifiant unique du device")


async def _update_app_version(user_id: UUID, app_version: str) -> None:
    """Met à jour app_version sur user_profiles si la version a changé (fire-and-forget)."""
    async with safe_async_session() as db:
        await db.execute(
            text(
                """
                UPDATE user_profiles
                SET app_version = :v,
                    app_version_updated_at = :ts
                WHERE user_id = :uid
                  AND app_version IS DISTINCT FROM :v
                """
            ),
            {"v": app_version, "ts": datetime.now(timezone.utc), "uid": str(user_id)},
        )
        await db.commit()


@router.post("/events", status_code=201)
async def log_event(
    event: EventCreate,
    background_tasks: BackgroundTasks,
    user_id: UUID = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
    x_app_version: str | None = Header(None, alias="X-App-Version"),
):
    """Enregistre un événement analytique."""
    service = AnalyticsService(db)
    await service.log_event(
        user_id=user_id,
        event_type=event.event_type,
        event_data=event.event_data,
        device_id=event.device_id,
    )

    # Update per-user version tracking on session_start or when header is present.
    # Priority: explicit header > event_data field.
    app_version = x_app_version or (
        event.event_data.get("app_version")
        if event.event_type == "session_start"
        else None
    )
    if app_version:
        background_tasks.add_task(_update_app_version, user_id, app_version)

    return {"status": "ok"}


@router.get("/digest-metrics")
async def get_digest_metrics(
    days: int = 7,
    user_id: UUID = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
):
    """Métriques d'engagement digest: taux de complétion, temps moyen, breakdown des actions."""
    service = AnalyticsService(db)
    metrics = await service.get_digest_metrics(user_id, days)
    breakdown = await service.get_interaction_breakdown(user_id, "digest", days)
    return {
        "period_days": days,
        "digest_sessions": metrics,
        "interaction_breakdown": breakdown,
    }
