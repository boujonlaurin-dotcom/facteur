"""Dispatch des alertes source et sujet (Epic 30, stories 30.2 / 30.3).

Même passe que le dispatcher de la tournée, mêmes garanties : garde Firebase,
créneau utilisateur, insertion idempotente `(device, target_date, kind)`,
gouverneur, métriques. Deux différences assumées :

- le `kind` porte la cible (`source_alert:<hex>` / `topic_alert:<hex>`) pour que
  deux cloches du même jour ne se télescopent pas sur la contrainte d'unicité
  de `push_deliveries` ;
- le gouverneur est appelé avec `ritual_companion=True` : l'alerte est
  silencieuse et accompagne la tournée au lieu de lui disputer son territoire.

Les deux familles partagent toute la mécanique de livraison (`_deliver_one`),
paramétrée par un `_AlertKind` : seuls le `kind` composite, le composer et la
clé d'analytics changent. Le budget journalier du gouverneur (5/24 h) reste le
plafond réel du nombre d'alertes reçues dans une journée.
"""

import asyncio
from collections.abc import Awaitable, Callable, Sequence
from dataclasses import dataclass
from datetime import UTC, date, datetime
from typing import Any
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import structlog
from sqlalchemy import select

from app.database import safe_async_session
from app.models.analytics import AnalyticsEvent
from app.models.push_notification import PushDevice
from app.models.user_notification_preferences import UserNotificationPreferences
from app.services.alert_cadence import cadence_phrase
from app.services.posthog_client import get_posthog_client
from app.services.push_composer import (
    ComposedPush,
    compose_source_alert,
    compose_topic_alert,
)
from app.services.push_dispatcher import (
    PushSender,
    firebase_configured,
    get_or_create_delivery,
    is_due,
    is_invalid_token_error,
    send_fcm,
)
from app.services.push_governor import check_push_budget
from app.services.source_alert_producer import (
    ANALYTICS_KIND as SOURCE_ANALYTICS_KIND,
)
from app.services.source_alert_producer import (
    find_source_alert_candidates,
    source_alert_kind,
)
from app.services.topic_alert_producer import (
    ANALYTICS_KIND as TOPIC_ANALYTICS_KIND,
)
from app.services.topic_alert_producer import (
    find_topic_alert_candidates,
    topic_alert_kind,
)

logger = structlog.get_logger()


@dataclass(frozen=True)
class _AlertKind:
    """Ce qui distingue une famille d'alertes de l'autre — tout le reste est partagé."""

    name: str
    analytics_kind: str
    #: `(session, user_id, now) -> candidats`
    find_candidates: Callable[..., Awaitable[Sequence[Any]]]
    #: `candidate -> kind` composite stocké dans `push_deliveries.kind`
    delivery_kind: Callable[[Any], str]
    #: `(candidate, cadence_phrase) -> ComposedPush`
    compose: Callable[[Any, str], ComposedPush]
    #: Champ d'identité de la cible, exposé aux analytics.
    target_field: str
    #: `candidate -> id de la cible`
    target_id: Callable[[Any], str]


SOURCE_ALERTS = _AlertKind(
    name="source_alert",
    analytics_kind=SOURCE_ANALYTICS_KIND,
    find_candidates=find_source_alert_candidates,
    delivery_kind=lambda c: source_alert_kind(c.source_id),
    compose=compose_source_alert,
    target_field="source_id",
    target_id=lambda c: str(c.source_id),
)

TOPIC_ALERTS = _AlertKind(
    name="topic_alert",
    analytics_kind=TOPIC_ANALYTICS_KIND,
    find_candidates=find_topic_alert_candidates,
    delivery_kind=lambda c: topic_alert_kind(c.topic_id),
    compose=compose_topic_alert,
    target_field="topic_id",
    target_id=lambda c: str(c.topic_id),
)


async def dispatch_source_alerts(
    *,
    now: datetime | None = None,
    sender: PushSender = send_fcm,
) -> dict[str, int]:
    """Envoie une alerte par source sous cloche ayant publié dans les 24 h."""
    return await _dispatch(SOURCE_ALERTS, now=now, sender=sender)


async def dispatch_topic_alerts(
    *,
    now: datetime | None = None,
    sender: PushSender = send_fcm,
) -> dict[str, int]:
    """Envoie une alerte par sujet sous cloche ayant du neuf dans les 24 h."""
    return await _dispatch(TOPIC_ALERTS, now=now, sender=sender)


async def _dispatch(
    alert_kind: _AlertKind,
    *,
    now: datetime | None,
    sender: PushSender,
) -> dict[str, int]:
    metrics = {"sent": 0, "skipped": 0, "governed": 0, "invalid_tokens": 0}
    if sender is send_fcm and not firebase_configured():
        logger.info(
            f"{alert_kind.name}_dispatch_disabled", reason="firebase_not_configured"
        )
        return metrics

    utc_now = (now or datetime.now(UTC)).astimezone(UTC)

    async with safe_async_session() as session:
        rows = (
            await session.execute(
                select(PushDevice, UserNotificationPreferences)
                .join(
                    UserNotificationPreferences,
                    UserNotificationPreferences.user_id == PushDevice.user_id,
                )
                .where(
                    PushDevice.revoked_at.is_(None),
                    UserNotificationPreferences.push_enabled.is_(True),
                )
                .order_by(PushDevice.user_id, PushDevice.device_id)
            )
        ).all()

        # Candidats stables par utilisateur dans une passe : ils ne dépendent
        # pas du device, et la requête est la partie coûteuse.
        candidates_cache: dict[object, Sequence[Any]] = {}

        for device, prefs in rows:
            try:
                local_now = utc_now.astimezone(ZoneInfo(prefs.timezone))
            except ZoneInfoNotFoundError:
                logger.warning(
                    f"{alert_kind.name}_invalid_timezone",
                    user_id=str(device.user_id),
                    timezone=prefs.timezone,
                )
                continue
            if not is_due(local_now, prefs.time_slot):
                continue

            if device.user_id not in candidates_cache:
                candidates_cache[device.user_id] = await alert_kind.find_candidates(
                    session, user_id=device.user_id, now=utc_now
                )
            candidates = candidates_cache[device.user_id]
            if not candidates:
                continue

            target_date = local_now.date()
            for candidate in candidates:
                await _deliver_one(
                    session,
                    alert_kind=alert_kind,
                    device=device,
                    candidate=candidate,
                    target_date=target_date,
                    utc_now=utc_now,
                    sender=sender,
                    metrics=metrics,
                )

        await session.commit()

    logger.info(f"{alert_kind.name}_dispatch_completed", **metrics)
    return metrics


async def _deliver_one(
    session,
    *,
    alert_kind: _AlertKind,
    device,
    candidate: Any,
    target_date: date,
    utc_now: datetime,
    sender: PushSender,
    metrics: dict[str, int],
) -> None:
    kind = alert_kind.delivery_kind(candidate)
    delivery = await get_or_create_delivery(
        session,
        device_id=device.device_id,
        target_date=target_date,
        now=utc_now,
        kind=kind,
    )
    # Une alerte ne se rejoue pas : contrairement à la tournée, il n'y a pas de
    # « pas encore prêt » à retenter — l'article existe déjà. `failed` inclus :
    # une seconde tentative sonnerait un jour trop tard. C'est aussi ce qui
    # donne gratuitement la garde « 1 par jour » du mode filtré : la livraison
    # du jour existe déjà et n'est plus `pending`.
    if delivery.status != "pending":
        return

    decision = await check_push_budget(
        session,
        user_id=device.user_id,
        kind=kind,
        now=utc_now,
        target_date=target_date,
        ritual_companion=True,
    )
    if not decision.allowed:
        delivery.status = "skipped"
        delivery.skipped_at = utc_now
        delivery.error_code = decision.reason
        metrics["governed"] += 1
        metrics["skipped"] += 1
        logger.info(
            f"{alert_kind.name}_governed",
            device_id=str(device.device_id),
            reason=decision.reason,
        )
        get_posthog_client().capture(
            device.user_id,
            "push_suppressed",
            {
                "kind": alert_kind.analytics_kind,
                "reason": decision.reason,
                alert_kind.target_field: alert_kind.target_id(candidate),
            },
        )
        return

    composed = alert_kind.compose(
        candidate,
        cadence_phrase(candidate.articles_30d, candidate.oldest_content_at, utc_now),
    )
    delivery.attempt_count += 1
    delivery.last_attempt_at = utc_now
    try:
        await asyncio.to_thread(
            sender,
            device.fcm_token,
            composed.title,
            composed.body,
            {**composed.data, "sent_at": utc_now.isoformat()},
        )
    except Exception as exc:
        delivery.status = "failed"
        delivery.next_attempt_at = None
        delivery.error_code = type(exc).__name__
        delivery.error_message = str(exc)[:1000]
        if is_invalid_token_error(exc):
            device.revoked_at = utc_now
            metrics["invalid_tokens"] += 1
        logger.warning(
            f"{alert_kind.name}_delivery_failed",
            device_id=str(device.device_id),
            error=type(exc).__name__,
        )
        return

    delivery.status = "sent"
    delivery.sent_at = utc_now
    delivery.next_attempt_at = None
    delivery.error_code = None
    delivery.error_message = None
    metrics["sent"] += 1
    # Ajout direct (sans AnalyticsService.log_event, qui commit immédiatement) :
    # un commit mid-loop expirerait les objets ORM de la boucle.
    session.add(
        AnalyticsEvent(
            user_id=device.user_id,
            event_type="push_sent",
            event_data={
                "kind": alert_kind.analytics_kind,
                alert_kind.target_field: alert_kind.target_id(candidate),
                "content_id": str(candidate.content_id),
                "target_date": target_date.isoformat(),
            },
        )
    )
    get_posthog_client().capture(
        device.user_id,
        "push_sent",
        {
            "kind": alert_kind.analytics_kind,
            alert_kind.target_field: alert_kind.target_id(candidate),
            "target_date": target_date.isoformat(),
        },
    )
