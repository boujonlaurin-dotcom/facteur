"""Router pour les analytics."""

from datetime import UTC, date, datetime
from uuid import UUID

from fastapi import APIRouter, BackgroundTasks, Depends, Header, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db, safe_async_session
from app.dependencies import get_current_user_id
from app.services.analytics_service import AnalyticsService
from app.services.recommendation.scoring_config import scoring_algo_version
from app.services.streak_service import StreakService

router = APIRouter(tags=["Analytics"])

#: Taille maximale d'un lot accepté par `POST /events/batch`. Le client flush
#: tous les 25 events : la marge absorbe un flush de fin de session sans jamais
#: laisser un lot pathologique ouvrir un commit de plusieurs milliers de lignes.
MAX_BATCH_EVENTS = 100

#: Impression d'un article dans la Tournée ou l'Essentiel — le **dénominateur**
#: du CTR. Le seul type d'event que le backend estampille (cf.
#: [_stamp_algo_version]).
IMPRESSION_EVENT_TYPE = "article_impression"


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
            {"v": app_version, "ts": datetime.now(UTC), "uid": str(user_id)},
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

    if event.event_type == "session_start":
        local_date: date | None = None
        raw_local_date = event.event_data.get("local_date")
        if isinstance(raw_local_date, str):
            try:
                local_date = date.fromisoformat(raw_local_date)
            except ValueError:
                local_date = None

        await StreakService(db).record_session_start(
            str(user_id),
            local_date=local_date,
        )
        await db.commit()

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


def _stamp_algo_version(event: EventCreate) -> dict:
    """Estampille la version de scoring active sur une impression.

    Côté **serveur** et pas client : le mobile ne connaît pas la configuration
    de scoring, et la faire redescendre dans `/api/feed` + `/api/essentiel`
    puis remonter dans l'event serait trois surfaces de plumbing pour la même
    valeur. Limite assumée : un redeploy entre le scoring d'un flux et
    l'impression de ses cartes estampille la nouvelle version sur des cartes
    scorées par l'ancienne — quelques minutes de données par déploiement.

    Un `algo_version` déjà posé par le client n'est jamais écrasé.
    """
    if event.event_type != IMPRESSION_EVENT_TYPE:
        return event.event_data
    if event.event_data.get("algo_version"):
        return event.event_data
    return {**event.event_data, "algo_version": scoring_algo_version()}


@router.post("/events/batch", status_code=201)
async def log_events_batch(
    events: list[EventCreate],
    user_id: UUID = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
):
    """Enregistre un **lot** d'événements analytiques en un seul commit.

    Additif : `POST /events` reste le chemin unitaire et n'est pas touché — les
    binaires en circulation continuent de l'utiliser. Ce lot est réservé à la
    télémétrie fire-and-forget (impressions) : il n'exécute **aucun** des effets
    de bord de `/events` (streak sur `session_start`, mise à jour d'app_version).
    Un `session_start` doit donc rester sur le chemin unitaire.
    """
    if len(events) > MAX_BATCH_EVENTS:
        raise HTTPException(
            status_code=422,
            detail=f"Lot trop grand ({len(events)} > {MAX_BATCH_EVENTS} events)",
        )

    accepted = await AnalyticsService(db).log_events(
        user_id=user_id,
        events=[
            (event.event_type, _stamp_algo_version(event), event.device_id)
            for event in events
        ],
    )
    return {"status": "ok", "accepted": accepted}


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
