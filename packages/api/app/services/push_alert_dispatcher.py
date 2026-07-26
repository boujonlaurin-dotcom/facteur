"""Dispatch des alertes « source rare » (Epic 30, story 30.2).

Même passe que le dispatcher de la tournée, mêmes garanties : garde Firebase,
créneau utilisateur, insertion idempotente `(device, target_date, kind)`,
gouverneur, métriques. Deux différences assumées :

- le `kind` porte la source (`source_alert:<hex>`) pour que deux cloches du même
  jour ne se télescopent pas sur la contrainte d'unicité de `push_deliveries` ;
- le gouverneur est appelé avec `ritual_companion=True` : l'alerte est
  silencieuse et accompagne la tournée au lieu de lui disputer son territoire.

Conséquence du budget journalier partagé (2/24h) : une fois la tournée envoyée,
au plus 1 alerte passe dans la journée. Les suivantes sont `skipped` avec
`daily_budget_exceeded` — c'est le garde-fou qui fait son travail.
"""

import asyncio
from collections.abc import Sequence
from datetime import UTC, datetime
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import structlog
from sqlalchemy import select

from app.database import safe_async_session
from app.models.analytics import AnalyticsEvent
from app.models.push_notification import PushDevice
from app.models.user_notification_preferences import UserNotificationPreferences
from app.services.posthog_client import get_posthog_client
from app.services.push_composer import compose_source_alert
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
    ANALYTICS_KIND,
    SourceAlertCandidate,
    find_source_alert_candidates,
    rarity_phrase,
    source_alert_kind,
)

logger = structlog.get_logger()


async def dispatch_source_alerts(
    *,
    now: datetime | None = None,
    sender: PushSender = send_fcm,
) -> dict[str, int]:
    """Envoie une alerte par source rare ayant publié dans les dernières 24 h."""
    metrics = {"sent": 0, "skipped": 0, "governed": 0, "invalid_tokens": 0}
    if sender is send_fcm and not firebase_configured():
        logger.info("source_alert_dispatch_disabled", reason="firebase_not_configured")
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
        candidates_cache: dict[object, Sequence[SourceAlertCandidate]] = {}

        for device, prefs in rows:
            try:
                local_now = utc_now.astimezone(ZoneInfo(prefs.timezone))
            except ZoneInfoNotFoundError:
                logger.warning(
                    "source_alert_invalid_timezone",
                    user_id=str(device.user_id),
                    timezone=prefs.timezone,
                )
                continue
            if not is_due(local_now, prefs.time_slot):
                continue

            if device.user_id not in candidates_cache:
                candidates_cache[device.user_id] = await find_source_alert_candidates(
                    session, user_id=device.user_id, now=utc_now
                )
            candidates = candidates_cache[device.user_id]
            if not candidates:
                continue

            target_date = local_now.date()
            for candidate in candidates:
                await _deliver_one(
                    session,
                    device=device,
                    candidate=candidate,
                    target_date=target_date,
                    utc_now=utc_now,
                    sender=sender,
                    metrics=metrics,
                )

        await session.commit()

    logger.info("source_alert_dispatch_completed", **metrics)
    return metrics


async def _deliver_one(
    session,
    *,
    device,
    candidate: SourceAlertCandidate,
    target_date,
    utc_now: datetime,
    sender: PushSender,
    metrics: dict[str, int],
) -> None:
    kind = source_alert_kind(candidate.source_id)
    delivery = await get_or_create_delivery(
        session,
        device_id=device.device_id,
        target_date=target_date,
        now=utc_now,
        kind=kind,
    )
    # Une alerte ne se rejoue pas : contrairement à la tournée, il n'y a pas de
    # « pas encore prêt » à retenter — l'article existe déjà. `failed` inclus :
    # une seconde tentative sonnerait un jour trop tard.
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
            "source_alert_governed",
            device_id=str(device.device_id),
            reason=decision.reason,
        )
        get_posthog_client().capture(
            device.user_id,
            "push_suppressed",
            {
                "kind": ANALYTICS_KIND,
                "reason": decision.reason,
                "source_id": str(candidate.source_id),
            },
        )
        return

    composed = compose_source_alert(
        candidate,
        rarity_phrase(candidate.articles_30d, candidate.oldest_content_at, utc_now),
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
            "source_alert_delivery_failed",
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
                "kind": ANALYTICS_KIND,
                "source_id": str(candidate.source_id),
                "content_id": str(candidate.content_id),
                "target_date": target_date.isoformat(),
            },
        )
    )
    get_posthog_client().capture(
        device.user_id,
        "push_sent",
        {
            "kind": ANALYTICS_KIND,
            "source_id": str(candidate.source_id),
            "target_date": target_date.isoformat(),
        },
    )
