"""Relance des abandons d'onboarding par push (J+0 ~1h puis J+1 ~24h).

Cible : les devices enregistrés tôt (écran d'amorce à l'étape 3/4) dont
l'utilisateur n'a PAS terminé l'onboarding (`user_profiles.onboarding_completed
= False`). L'ancre temporelle est `push_devices.created_at` (stable à travers
les ré-enregistrements) = moment de l'opt-in précoce / abandon.

Réutilise le transport et l'insertion idempotente de `push_dispatcher`
(`firebase_configured`, `send_fcm`, `get_or_create_delivery`,
`is_invalid_token_error`). Deux `kind` distincts (`onboarding_reengagement_d0` /
`_d1`) → deux lignes `push_deliveries` one-shot par device sur la contrainte
d'unicité `(device_id, target_date, kind)`. Aucune migration : `kind` est déjà
une colonne `String(32)`.

Le gouverneur de budget (`check_push_budget`) est volontairement bypassé : ce
budget arbitre la piste digest quotidien. Ici le tunnel est naturellement
plafonné à 2 envois à vie par device (deux kinds, chacun one-shot).
"""

import asyncio
from datetime import UTC, datetime, time, timedelta
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import structlog
from sqlalchemy import select

from app.database import safe_async_session
from app.models.analytics import AnalyticsEvent
from app.models.push_notification import PushDevice
from app.models.user import UserProfile
from app.services.posthog_client import get_posthog_client
from app.services.push_dispatcher import (
    PushSender,
    firebase_configured,
    get_or_create_delivery,
    is_invalid_token_error,
    send_fcm,
)

logger = structlog.get_logger()

KIND_D0 = "onboarding_reengagement_d0"
KIND_D1 = "onboarding_reengagement_d1"

# Fenêtre de sélection : on ignore les devices trop vieux (l'abandon n'est plus
# « chaud » et le purge anonyme finira le ménage à J+30). Couvre largement J+1.
STALE_AFTER = timedelta(days=3)
D0_AFTER = timedelta(hours=1)
D1_AFTER = timedelta(hours=24)
RETRY_DELAY = timedelta(minutes=5)

# Heures calmes locales : pas d'envoi avant 08:00 ni à partir de 21:00.
QUIET_START = time(21, 0)
QUIET_END = time(8, 0)

FALLBACK_TIMEZONE = "Europe/Paris"

# TODO(PO): valider copy — FR sobre, pas d'em-dash, pas de métaphore facteur/lettre.
_COPY: dict[str, tuple[str, str]] = {
    KIND_D0: (
        "Tu y étais presque",
        "Ta configuration n'est pas terminée. Reprends en une minute.",
    ),
    KIND_D1: (
        "On termine ta configuration ?",
        "Quelques réponses suffisent pour recevoir ton premier récap.",
    ),
}


def _resolve_zone(timezone: str) -> ZoneInfo:
    try:
        return ZoneInfo(timezone)
    except ZoneInfoNotFoundError:
        return ZoneInfo(FALLBACK_TIMEZONE)


def _next_active_utc(local_now: datetime) -> datetime:
    """Prochain 08:00 local (en UTC) après une fenêtre calme."""
    if local_now.time() >= QUIET_START:
        base = (local_now + timedelta(days=1)).replace(
            hour=QUIET_END.hour, minute=QUIET_END.minute, second=0, microsecond=0
        )
    else:  # avant QUIET_END
        base = local_now.replace(
            hour=QUIET_END.hour, minute=QUIET_END.minute, second=0, microsecond=0
        )
    return base.astimezone(UTC)


def _is_quiet(local_now: datetime) -> bool:
    local_time = local_now.time()
    return local_time < QUIET_END or local_time >= QUIET_START


async def dispatch_onboarding_reengagement_pushes(
    *,
    now: datetime | None = None,
    sender: PushSender = send_fcm,
) -> dict[str, int]:
    """Envoie les relances J+0 puis J+1 aux abandons d'onboarding."""
    metrics = {
        "sent": 0,
        "deferred": 0,
        "retried": 0,
        "invalid_tokens": 0,
    }
    if sender is send_fcm and not firebase_configured():
        logger.info(
            "onboarding_reengagement_disabled", reason="firebase_not_configured"
        )
        return metrics

    utc_now = (now or datetime.now(UTC)).astimezone(UTC)

    async with safe_async_session() as session:
        rows = (
            (
                await session.execute(
                    select(PushDevice)
                    .join(UserProfile, UserProfile.user_id == PushDevice.user_id)
                    .where(
                        PushDevice.revoked_at.is_(None),
                        UserProfile.onboarding_completed.is_(False),
                        PushDevice.created_at > utc_now - STALE_AFTER,
                    )
                )
            )
            .scalars()
            .all()
        )

        for device in rows:
            created_at = device.created_at
            if created_at.tzinfo is None:
                created_at = created_at.replace(tzinfo=UTC)
            elapsed = utc_now - created_at

            zone = _resolve_zone(device.timezone)
            local_now = utc_now.astimezone(zone)

            for kind, threshold in ((KIND_D0, D0_AFTER), (KIND_D1, D1_AFTER)):
                if elapsed < threshold:
                    continue

                delivery = await get_or_create_delivery(
                    session,
                    device_id=device.device_id,
                    target_date=created_at.date(),
                    now=utc_now,
                    kind=kind,
                )
                if delivery.status in {"sent", "skipped"}:
                    continue
                if delivery.next_attempt_at and delivery.next_attempt_at > utc_now:
                    continue

                if _is_quiet(local_now):
                    delivery.status = "pending"
                    delivery.next_attempt_at = _next_active_utc(local_now)
                    delivery.error_code = "quiet_hours"
                    metrics["deferred"] += 1
                    continue

                title, body = _COPY[kind]
                delivery.attempt_count += 1
                delivery.last_attempt_at = utc_now
                try:
                    await asyncio.to_thread(
                        sender,
                        device.fcm_token,
                        title,
                        body,
                        {
                            "kind": kind,
                            "route": "/onboarding",
                            "sent_at": utc_now.isoformat(),
                        },
                    )
                except Exception as exc:
                    delivery.status = "failed"
                    delivery.next_attempt_at = utc_now + RETRY_DELAY
                    delivery.error_code = type(exc).__name__
                    delivery.error_message = str(exc)[:1000]
                    if is_invalid_token_error(exc):
                        device.revoked_at = utc_now
                        metrics["invalid_tokens"] += 1
                    else:
                        metrics["retried"] += 1
                    logger.warning(
                        "onboarding_reengagement_failed",
                        device_id=str(device.device_id),
                        kind=kind,
                        error=type(exc).__name__,
                    )
                else:
                    delivery.status = "sent"
                    delivery.sent_at = utc_now
                    delivery.next_attempt_at = None
                    delivery.error_code = None
                    delivery.error_message = None
                    metrics["sent"] += 1
                    # Ajout direct (pas de commit mid-loop qui expirerait les
                    # objets ORM) : persisté par le commit final.
                    session.add(
                        AnalyticsEvent(
                            user_id=device.user_id,
                            event_type="push_sent",
                            event_data={"kind": kind},
                        )
                    )
                    get_posthog_client().capture(
                        device.user_id,
                        "push_sent",
                        {"kind": kind},
                    )

        await session.commit()

    logger.info("onboarding_reengagement_completed", **metrics)
    return metrics
