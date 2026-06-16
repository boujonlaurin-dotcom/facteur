"""Server-side daily Essentiel push dispatcher."""

import asyncio
import base64
import json
from collections.abc import Callable
from datetime import UTC, date, datetime, time, timedelta
from functools import lru_cache
from typing import Any
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import structlog
from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.database import safe_async_session
from app.models.daily_digest import DailyDigest
from app.models.push_notification import PushDelivery, PushDevice
from app.models.user_notification_preferences import UserNotificationPreferences
from app.services.digest_service import DigestService
from app.services.essentiel_service import (
    build_essentiel_response,
    fetch_user_essentiel_context,
)

logger = structlog.get_logger()
settings = get_settings()

PUSH_KIND = "daily_digest"
MORNING_TIME = time(7, 30)
MORNING_CUTOFF = time(12, 0)
EVENING_TIME = time(19, 0)
RETRY_DELAY = timedelta(minutes=5)

PushSender = Callable[[str, str, str, dict[str, str]], Any]


def _firebase_configured() -> bool:
    return bool(
        settings.firebase_service_account_json
        or settings.firebase_service_account_base64
    )


@lru_cache(maxsize=1)
def _firebase_app():
    raw = settings.firebase_service_account_json
    if not raw and settings.firebase_service_account_base64:
        raw = base64.b64decode(settings.firebase_service_account_base64).decode()
    if not raw:
        return None

    import firebase_admin
    from firebase_admin import credentials

    try:
        return firebase_admin.get_app()
    except ValueError:
        return firebase_admin.initialize_app(credentials.Certificate(json.loads(raw)))


def _send_fcm(token: str, title: str, body: str, data: dict[str, str]) -> str:
    app = _firebase_app()
    if app is None:
        raise RuntimeError("firebase_not_configured")

    from firebase_admin import messaging

    return messaging.send(
        messaging.Message(
            token=token,
            notification=messaging.Notification(title=title, body=body),
            data=data,
            android=messaging.AndroidConfig(
                priority="high",
                notification=messaging.AndroidNotification(
                    channel_id="digest_channel",
                    icon="ic_stat_facteur",
                    color="#D35400",
                ),
            ),
            apns=messaging.APNSConfig(
                headers={"apns-priority": "10"},
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(sound="default", content_available=True)
                ),
            ),
        ),
        app=app,
    )


def _is_due(local_now: datetime, time_slot: str) -> bool:
    local_time = local_now.time().replace(tzinfo=None)
    if time_slot == "morning":
        return MORNING_TIME <= local_time <= MORNING_CUTOFF
    return local_time >= EVENING_TIME


def _is_invalid_token_error(exc: Exception) -> bool:
    return type(exc).__name__ in {
        "UnregisteredError",
        "SenderIdMismatchError",
        "InvalidArgumentError",
    }


async def _get_or_create_delivery(
    session: AsyncSession,
    *,
    device_id,
    target_date: date,
    now: datetime,
) -> PushDelivery:
    await session.execute(
        pg_insert(PushDelivery)
        .values(
            device_id=device_id,
            target_date=target_date,
            kind=PUSH_KIND,
            status="pending",
            attempt_count=0,
            next_attempt_at=now,
            created_at=now,
            updated_at=now,
        )
        .on_conflict_do_nothing(index_elements=["device_id", "target_date", "kind"])
    )
    await session.flush()
    delivery = await session.scalar(
        select(PushDelivery).where(
            PushDelivery.device_id == device_id,
            PushDelivery.target_date == target_date,
            PushDelivery.kind == PUSH_KIND,
        )
    )
    assert delivery is not None
    return delivery


async def _build_exact_essentiel(session: AsyncSession, user_id, target_date: date):
    digest = await session.scalar(
        select(DailyDigest).where(
            DailyDigest.user_id == user_id,
            DailyDigest.target_date == target_date,
            DailyDigest.is_serene.is_(False),
        )
    )
    if digest is None or not (
        (digest.format_version or "").startswith("editorial_")
        or digest.format_version == "topics_v1"
    ):
        return None

    response = await DigestService(session)._build_digest_response(digest, user_id)
    if response.target_date != target_date or response.is_stale_fallback:
        return None
    context = await fetch_user_essentiel_context(session, user_id)
    return build_essentiel_response(response, user_context=context)


async def dispatch_daily_essentiel_pushes(
    *,
    now: datetime | None = None,
    sender: PushSender = _send_fcm,
) -> dict[str, int]:
    """Send due pushes once per device/day, retrying morning gaps until noon."""
    if sender is _send_fcm and not _firebase_configured():
        logger.info("push_dispatch_disabled", reason="firebase_not_configured")
        return {"sent": 0, "retried": 0, "skipped": 0, "invalid_tokens": 0}

    utc_now = (now or datetime.now(UTC)).astimezone(UTC)
    metrics = {"sent": 0, "retried": 0, "skipped": 0, "invalid_tokens": 0}

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

        digest_cache: dict[tuple[Any, date], Any] = {}
        for device, prefs in rows:
            try:
                local_now = utc_now.astimezone(ZoneInfo(prefs.timezone))
            except ZoneInfoNotFoundError:
                logger.warning(
                    "push_invalid_timezone",
                    user_id=str(device.user_id),
                    timezone=prefs.timezone,
                )
                continue
            if not _is_due(local_now, prefs.time_slot):
                continue

            target_date = local_now.date()
            delivery = await _get_or_create_delivery(
                session,
                device_id=device.device_id,
                target_date=target_date,
                now=utc_now,
            )
            if delivery.status in {"sent", "skipped"}:
                continue
            if delivery.next_attempt_at and delivery.next_attempt_at > utc_now:
                continue

            cache_key = (device.user_id, target_date)
            if cache_key not in digest_cache:
                digest_cache[cache_key] = await _build_exact_essentiel(
                    session, device.user_id, target_date
                )
            essentiel = digest_cache[cache_key]

            if essentiel is None or not essentiel.articles:
                if prefs.time_slot == "morning" and local_now.time() >= MORNING_CUTOFF:
                    delivery.status = "skipped"
                    delivery.skipped_at = utc_now
                    delivery.error_code = "digest_missing_at_cutoff"
                    metrics["skipped"] += 1
                else:
                    delivery.status = "pending"
                    delivery.next_attempt_at = utc_now + RETRY_DELAY
                    delivery.error_code = "digest_not_ready"
                    metrics["retried"] += 1
                continue

            teasers = [article.title for article in essentiel.articles[:2]]
            body = teasers[0]
            delivery.attempt_count += 1
            delivery.last_attempt_at = utc_now
            try:
                await asyncio.to_thread(
                    sender,
                    device.fcm_token,
                    "Facteur",
                    body,
                    {
                        "route": "/digest",
                        "target_date": target_date.isoformat(),
                        "kind": PUSH_KIND,
                        "teasers": json.dumps(teasers, ensure_ascii=False),
                    },
                )
            except Exception as exc:
                delivery.status = "failed"
                delivery.next_attempt_at = utc_now + RETRY_DELAY
                delivery.error_code = type(exc).__name__
                delivery.error_message = str(exc)[:1000]
                if _is_invalid_token_error(exc):
                    device.revoked_at = utc_now
                    metrics["invalid_tokens"] += 1
                else:
                    metrics["retried"] += 1
                logger.warning(
                    "push_delivery_failed",
                    device_id=str(device.device_id),
                    error=type(exc).__name__,
                )
            else:
                delivery.status = "sent"
                delivery.sent_at = utc_now
                delivery.next_attempt_at = None
                delivery.error_code = None
                delivery.error_message = None
                metrics["sent"] += 1

        await session.commit()

    logger.info("push_dispatch_completed", **metrics)
    return metrics
