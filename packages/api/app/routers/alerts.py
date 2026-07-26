"""Écran « Mes alertes » — inventaire des cloches actives (Epic 30, story 30.2).

Le toggle lui-même vit dans `sources.py` (à côté de `/trust`, mêmes
invalidations de cache) ; ce routeur ne sert que la lecture, partagée entre
l'écran de réglages et la section « Tes alertes » de la Tournée.
"""

from datetime import UTC, datetime, timedelta
from uuid import UUID

from fastapi import APIRouter, Depends
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user_id
from app.models.content import Content, UserContentStatus
from app.models.enums import ContentStatus
from app.models.push_notification import PushDelivery, PushDevice
from app.models.source import Source, UserSource
from app.schemas.alert import AlertItem, AlertsResponse
from app.services.source_alert_producer import (
    ALERT_CAP,
    ALERT_LOOKBACK,
    FOLLOWED_SOURCE_STATES,
    FREQUENCY_WINDOW_DAYS,
    source_alert_kind,
)

router = APIRouter()


@router.get("", response_model=AlertsResponse)
async def list_alerts(
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> AlertsResponse:
    """Cloches actives de l'utilisateur, avec de quoi écrire la copy d'attente."""
    uid = UUID(user_id)
    now = datetime.now(UTC)
    window_start = now - timedelta(days=FREQUENCY_WINDOW_DAYS)
    fresh_since = now - ALERT_LOOKBACK

    sources = (
        (
            await db.execute(
                select(Source)
                .join(UserSource, UserSource.source_id == Source.id)
                .where(
                    UserSource.user_id == uid,
                    UserSource.notify.is_(True),
                    UserSource.state.in_(FOLLOWED_SOURCE_STATES),
                )
                .order_by(Source.name)
            )
        )
        .scalars()
        .all()
    )

    if not sources:
        return AlertsResponse(cap=ALERT_CAP, active_count=0, items=[])

    source_ids = [s.id for s in sources]

    # Volume 30 j + dernière parution, en une passe pour toutes les cloches.
    stats_rows = (
        await db.execute(
            select(
                Content.source_id,
                func.count()
                .filter(Content.published_at >= window_start)
                .label("articles_30d"),
                func.max(Content.published_at).label("last_published_at"),
            )
            .where(Content.source_id.in_(source_ids))
            .group_by(Content.source_id)
        )
    ).all()
    stats = {r.source_id: (r.articles_30d, r.last_published_at) for r in stats_rows}

    # Contenus frais non lus : `consumed` seul compte comme lu — `seen` signifie
    # « passé dans le flux », pas « traité », et n'éteint donc pas la pastille.
    fresh_rows = (
        await db.execute(
            select(Content.source_id, func.count())
            .outerjoin(
                UserContentStatus,
                (UserContentStatus.content_id == Content.id)
                & (UserContentStatus.user_id == uid),
            )
            .where(
                Content.source_id.in_(source_ids),
                Content.published_at >= fresh_since,
                (UserContentStatus.status.is_(None))
                | (UserContentStatus.status != ContentStatus.CONSUMED),
            )
            .group_by(Content.source_id)
        )
    ).all()
    fresh = {row[0]: row[1] for row in fresh_rows}

    # Dernier envoi effectif, par kind composite (`source_alert:<hex>`).
    kind_to_source = {source_alert_kind(sid): sid for sid in source_ids}
    sent_rows = (
        await db.execute(
            select(PushDelivery.kind, func.max(PushDelivery.sent_at))
            .join(PushDevice, PushDevice.device_id == PushDelivery.device_id)
            .where(
                PushDevice.user_id == uid,
                PushDelivery.status == "sent",
                PushDelivery.kind.in_(list(kind_to_source)),
            )
            .group_by(PushDelivery.kind)
        )
    ).all()
    last_sent = {kind_to_source[row[0]]: row[1] for row in sent_rows}

    items = []
    for source in sources:
        articles_30d, last_published_at = stats.get(source.id, (0, None))
        items.append(
            AlertItem(
                source_id=source.id,
                source_name=source.name,
                source_logo_url=source.logo_url,
                articles_30d=articles_30d,
                last_published_at=last_published_at,
                last_alert_sent_at=last_sent.get(source.id),
                new_content=fresh.get(source.id, 0),
            )
        )

    return AlertsResponse(cap=ALERT_CAP, active_count=len(items), items=items)
