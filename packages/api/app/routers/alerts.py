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
from app.schemas.alert import (
    AlertContent,
    AlertItem,
    AlertsResponse,
    AlertSuggestionsResponse,
    DismissAlertSuggestionRequest,
    DismissAlertSuggestionResponse,
)
from app.services.alert_cadence import (
    ALERT_CAP,
    ALERT_LOOKBACK,
    FREQUENCY_WINDOW_DAYS,
    cadence_per_week,
)
from app.services.alert_suggestions import (
    build_alert_suggestions,
    dismiss_alert_suggestion,
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

#: Contenus déclencheurs embarqués par cloche (story 30.4). Trois suffisent à
#: remplir la carte de la Tournée (`kAlertsSectionMaxRows`) quand une seule
#: cloche a sonné, et c'est ce plafond — combiné à `ALERT_CAP` — qui garantit
#: que la réponse ne peut pas enfler : au pire 5 cloches × 3 contenus.
ALERT_CONTENT_LIMIT = 3


def _content_type_value(raw: object) -> str | None:
    """`ContentType.ARTICLE` → `"article"`, en tolérant une valeur brute."""
    return getattr(raw, "value", raw) if raw is not None else None


def _unread_clause():
    """« Non lu » : seul `consumed` compte.

    `seen` signifie « passé dans le flux », pas « traité » — il n'éteint donc
    ni la pastille ni la ligne de la carte. Même prédicat que le compteur
    `new_content`, pour que les deux ne puissent pas diverger.
    """
    return (UserContentStatus.status.is_(None)) | (
        UserContentStatus.status != ContentStatus.CONSUMED
    )


def _status_join(uid: UUID):
    """Condition de jointure `user_content_statuses` bornée à l'utilisateur."""
    return (UserContentStatus.content_id == Content.id) & (
        UserContentStatus.user_id == uid
    )


async def _fresh_contents_by_source(
    db: AsyncSession,
    uid: UUID,
    sources: dict[UUID, Source],
    fresh_since: datetime,
) -> dict[UUID, list[AlertContent]]:
    """Jusqu'à `ALERT_CONTENT_LIMIT` contenus frais non lus **par source**.

    Une seule requête pour toutes les cloches source, via
    `row_number() OVER (PARTITION BY source_id)` : le bloc source garde un
    nombre de requêtes constant, quel que soit le nombre de cloches.
    """
    source_ids = list(sources)
    ranked = (
        select(
            Content.id.label("content_id"),
            Content.title.label("title"),
            Content.url.label("url"),
            Content.thumbnail_url.label("thumbnail_url"),
            Content.published_at.label("published_at"),
            Content.content_type.label("content_type"),
            Content.source_id.label("source_id"),
            func.row_number()
            .over(
                partition_by=Content.source_id,
                order_by=Content.published_at.desc(),
            )
            .label("rank"),
        )
        .outerjoin(UserContentStatus, _status_join(uid))
        .where(
            Content.source_id.in_(source_ids),
            Content.published_at >= fresh_since,
            _unread_clause(),
        )
        .subquery()
    )
    rows = (
        await db.execute(
            select(ranked)
            .where(ranked.c.rank <= ALERT_CONTENT_LIMIT)
            .order_by(ranked.c.source_id, ranked.c.rank)
        )
    ).all()

    by_source: dict[UUID, list[AlertContent]] = {}
    for row in rows:
        source = sources.get(row.source_id)
        by_source.setdefault(row.source_id, []).append(
            AlertContent(
                content_id=row.content_id,
                title=row.title,
                url=row.url,
                thumbnail_url=row.thumbnail_url,
                published_at=row.published_at,
                content_type=_content_type_value(row.content_type),
                source_id=row.source_id,
                source_name=source.name if source else "",
                source_logo_url=source.logo_url if source else None,
            )
        )
    return by_source


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
            .outerjoin(UserContentStatus, _status_join(uid))
            .where(
                Content.source_id.in_(source_ids),
                Content.published_at >= fresh_since,
                _unread_clause(),
            )
            .group_by(Content.source_id)
        )
    ).all()
    fresh = {row[0]: row[1] for row in fresh_rows}

    # Contenus déclencheurs (30.4) : une requête de plus, et une seule, pour
    # toutes les cloches. Rien à ramener si aucune n'a de neuf.
    contents_by_source: dict[UUID, list[AlertContent]] = {}
    if fresh:
        contents_by_source = await _fresh_contents_by_source(
            db, uid, {s.id: s for s, _ in rows if s.id in fresh}, fresh_since
        )

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
                contents=contents_by_source.get(source.id, []),
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
        contents: list[AlertContent] = []
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
                    .outerjoin(UserContentStatus, _status_join(uid))
                    .where(
                        predicate,
                        Content.published_at >= fresh_since,
                        _unread_clause(),
                    )
                )
            ).scalar_one()

            # Contenus déclencheurs (30.4). Une requête par sujet — le prédicat
            # n'a pas de `source_id` à partitionner —, mais bornée par le
            # plafond de 5 cloches : au pire 5 requêtes, jamais un fan-out
            # ouvert. On ne la paie que si la cloche a effectivement du neuf.
            if new_content:
                content_rows = (
                    await db.execute(
                        select(
                            Content.id,
                            Content.title,
                            Content.url,
                            Content.thumbnail_url,
                            Content.published_at,
                            Content.content_type,
                            Source.id.label("src_id"),
                            Source.name.label("src_name"),
                            Source.logo_url.label("src_logo_url"),
                        )
                        .join(Source, Source.id == Content.source_id)
                        .outerjoin(UserContentStatus, _status_join(uid))
                        .where(
                            predicate,
                            Content.published_at >= fresh_since,
                            _unread_clause(),
                        )
                        .order_by(Content.published_at.desc())
                        .limit(ALERT_CONTENT_LIMIT)
                    )
                ).all()
                contents = [
                    AlertContent(
                        content_id=row.id,
                        title=row.title,
                        url=row.url,
                        thumbnail_url=row.thumbnail_url,
                        published_at=row.published_at,
                        content_type=_content_type_value(row.content_type),
                        source_id=row.src_id,
                        source_name=row.src_name or "",
                        source_logo_url=row.src_logo_url,
                    )
                    for row in content_rows
                ]

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
                contents=contents,
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


@router.get("/suggestions", response_model=AlertSuggestionsResponse)
async def list_alert_suggestions(
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> AlertSuggestionsResponse:
    """Cibles à mettre sous cloche, déduites de l'usage réel (story 30.6).

    Appelé à chaque ouverture de « Mes alertes » : le coût est une passe
    agrégée bornée, pas une boucle par cible (cf. `alert_suggestions.py`).
    """
    return await build_alert_suggestions(db, UUID(user_id), datetime.now(UTC))


@router.post("/suggestions/dismiss", response_model=DismissAlertSuggestionResponse)
async def dismiss_suggestion(
    payload: DismissAlertSuggestionRequest,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> DismissAlertSuggestionResponse:
    """Une suggestion écartée ne revient pas le lendemain. Idempotent."""
    await dismiss_alert_suggestion(
        db, UUID(user_id), kind=payload.kind, target_id=payload.target_id
    )
    return DismissAlertSuggestionResponse(dismissed=True)
