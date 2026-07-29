"""Écran « Mes alertes » — inventaire des cloches actives (Epic 30, 30.2 / 30.3).

Les toggles vivent à côté de leur cible (`sources.py`, `custom_topics.py`,
mêmes invalidations de cache) ; ce routeur ne sert que la lecture, partagée
entre l'écran de réglages et la section « Tes alertes » de la Tournée. Il fait
l'union des deux familles — l'utilisateur a *une* liste de cloches, pas deux.
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
from app.models.user_topic_profile import UserTopicProfile
from app.schemas.alert import AlertItem, AlertsResponse
from app.services.alert_cadence import (
    ALERT_CAP,
    ALERT_LOOKBACK,
    FREQUENCY_WINDOW_DAYS,
    cadence_per_week,
)
from app.services.source_alert_producer import (
    FOLLOWED_SOURCE_STATES,
    source_alert_kind,
)
from app.services.topic_alert_producer import (
    build_topic_predicate,
    topic_alert_kind,
)

router = APIRouter()


async def _last_sent_by_kind(
    db: AsyncSession, uid: UUID, kinds: dict[str, UUID]
) -> dict[UUID, datetime]:
    """Dernier envoi effectif, indexé par cible, pour un lot de `kind` composites."""
    if not kinds:
        return {}
    rows = (
        await db.execute(
            select(PushDelivery.kind, func.max(PushDelivery.sent_at))
            .join(PushDevice, PushDevice.device_id == PushDelivery.device_id)
            .where(
                PushDevice.user_id == uid,
                PushDelivery.status == "sent",
                PushDelivery.kind.in_(list(kinds)),
            )
            .group_by(PushDelivery.kind)
        )
    ).all()
    return {kinds[row[0]]: row[1] for row in rows}


async def _source_items(db: AsyncSession, uid: UUID, now: datetime) -> list[AlertItem]:
    window_start = now - timedelta(days=FREQUENCY_WINDOW_DAYS)
    fresh_since = now - ALERT_LOOKBACK

    rows = (
        await db.execute(
            select(Source, UserSource.notify_filtered)
            .join(UserSource, UserSource.source_id == Source.id)
            .where(
                UserSource.user_id == uid,
                UserSource.notify.is_(True),
                UserSource.state.in_(FOLLOWED_SOURCE_STATES),
            )
            .order_by(Source.name)
        )
    ).all()
    if not rows:
        return []

    source_ids = [s.id for s, _ in rows]

    # Volume 30 j + dernière parution, en une passe pour toutes les cloches.
    stats_rows = (
        await db.execute(
            select(
                Content.source_id,
                func.count()
                .filter(Content.published_at >= window_start)
                .label("articles_30d"),
                func.min(Content.published_at).label("oldest_at"),
                func.max(Content.published_at).label("last_published_at"),
            )
            .where(Content.source_id.in_(source_ids))
            .group_by(Content.source_id)
        )
    ).all()
    stats = {
        r.source_id: (r.articles_30d, r.oldest_at, r.last_published_at)
        for r in stats_rows
    }

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

    last_sent = await _last_sent_by_kind(
        db, uid, {source_alert_kind(sid): sid for sid in source_ids}
    )

    items = []
    for source, notify_filtered in rows:
        articles_30d, oldest_at, last_published_at = stats.get(
            source.id, (0, None, None)
        )
        items.append(
            AlertItem(
                kind="source",
                source_id=source.id,
                source_name=source.name,
                source_logo_url=source.logo_url,
                filtered=notify_filtered is True,
                articles_30d=articles_30d,
                cadence_per_week=cadence_per_week(articles_30d, oldest_at, now),
                last_published_at=last_published_at,
                last_alert_sent_at=last_sent.get(source.id),
                new_content=fresh.get(source.id, 0),
            )
        )
    return items


async def _topic_items(db: AsyncSession, uid: UUID, now: datetime) -> list[AlertItem]:
    window_start = now - timedelta(days=FREQUENCY_WINDOW_DAYS)
    fresh_since = now - ALERT_LOOKBACK

    profiles = (
        (
            await db.execute(
                select(UserTopicProfile)
                .where(
                    UserTopicProfile.user_id == uid,
                    UserTopicProfile.notify.is_(True),
                    UserTopicProfile.state.in_(FOLLOWED_SOURCE_STATES),
                )
                .order_by(UserTopicProfile.topic_name)
            )
        )
        .scalars()
        .all()
    )
    if not profiles:
        return []

    last_sent = await _last_sent_by_kind(
        db, uid, {topic_alert_kind(p.id): p.id for p in profiles}
    )

    items = []
    for profile in profiles:
        predicate = build_topic_predicate(profile)
        articles_30d = 0
        oldest_at = last_published_at = None
        new_content = 0
        if predicate is not None:
            # Un sujet n'a pas de `source_id` à grouper : une agrégation par
            # sujet, bornée par le plafond de 5 cloches.
            articles_30d, oldest_at, last_published_at = (
                await db.execute(
                    select(
                        func.count(),
                        func.min(Content.published_at),
                        func.max(Content.published_at),
                    ).where(
                        predicate,
                        Content.published_at >= window_start,
                        Content.published_at <= now,
                    )
                )
            ).one()
            new_content = (
                await db.execute(
                    select(func.count())
                    .select_from(Content)
                    .outerjoin(
                        UserContentStatus,
                        (UserContentStatus.content_id == Content.id)
                        & (UserContentStatus.user_id == uid),
                    )
                    .where(
                        predicate,
                        Content.published_at >= fresh_since,
                        (UserContentStatus.status.is_(None))
                        | (UserContentStatus.status != ContentStatus.CONSUMED),
                    )
                )
            ).scalar_one()

        items.append(
            AlertItem(
                kind="topic",
                source_id=profile.id,
                source_name=profile.topic_name,
                filtered=profile.notify_filtered is True,
                articles_30d=articles_30d,
                cadence_per_week=cadence_per_week(articles_30d, oldest_at, now),
                last_published_at=last_published_at,
                last_alert_sent_at=last_sent.get(profile.id),
                new_content=new_content,
            )
        )
    return items


@router.get("", response_model=AlertsResponse)
async def list_alerts(
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> AlertsResponse:
    """Cloches actives de l'utilisateur, avec de quoi écrire la copy d'attente."""
    uid = UUID(user_id)
    now = datetime.now(UTC)

    items = await _source_items(db, uid, now) + await _topic_items(db, uid, now)
    # Les cloches qui ont sonné récemment d'abord : c'est l'ordre dans lequel
    # l'utilisateur cherche « qu'est-ce qui m'a notifié ? ». `None` (jamais
    # sonné) en queue.
    items.sort(
        key=lambda i: (
            i.last_alert_sent_at is None,
            -(i.last_alert_sent_at.timestamp() if i.last_alert_sent_at else 0),
            i.source_name.lower(),
        )
    )

    return AlertsResponse(cap=ALERT_CAP, active_count=len(items), items=items)
