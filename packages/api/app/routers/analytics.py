"""Router pour les analytics."""

from uuid import UUID

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from pydantic import BaseModel, Field

from app.database import get_db
from app.dependencies import get_current_user_id
from app.services.analytics_service import AnalyticsService

router = APIRouter(prefix="/analytics", tags=["Analytics"])


class EventCreate(BaseModel):
    """Schéma de création d'événement."""
    event_type: str = Field(..., description="Type d'événement (ex: session_start)")
    event_data: dict = Field(default_factory=dict, description="Données de l'événement")
    device_id: str | None = Field(None, description="Identifiant unique du device")


@router.post("/events", status_code=201)
async def log_event(
    event: EventCreate,
    user_id: UUID = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
):
    """Enregistre un événement analytique."""
    service = AnalyticsService(db)
    await service.log_event(
        user_id=user_id,
        event_type=event.event_type,
        event_data=event.event_data,
        device_id=event.device_id
    )
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
