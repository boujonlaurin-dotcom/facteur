"""Webhook Resend : vérifié, idempotent et résistant à l'ordre des events."""

import base64
import hashlib
import hmac
from datetime import UTC, datetime

import sentry_sdk
import structlog
from fastapi import APIRouter, Depends, Header, HTTPException, Request
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.database import get_db
from app.models.subscription import (
    SUPPORT_LINK_RETRY_DELAY,
    ResendWebhookEvent,
    SupportLinkDelivery,
    SupportLinkDeliveryAttempt,
)

router = APIRouter()
logger = structlog.get_logger()


def _verify_resend_signature(
    payload: bytes,
    *,
    svix_id: str | None,
    svix_timestamp: str | None,
    svix_signature: str | None,
) -> None:
    """Vérifie le format Svix utilisé par Resend sur le corps brut."""
    secret = get_settings().resend_webhook_secret
    if not secret:
        raise HTTPException(status_code=503, detail="Resend webhook not configured")
    if not (svix_id and svix_timestamp and svix_signature):
        raise HTTPException(status_code=401, detail="Missing Resend signature")
    try:
        raw_secret = base64.b64decode(secret.removeprefix("whsec_") + "===")
        signed = b".".join((svix_id.encode(), svix_timestamp.encode(), payload))
        expected = base64.b64encode(
            hmac.new(raw_secret, signed, hashlib.sha256).digest()
        ).decode()
    except Exception as exc:
        raise HTTPException(status_code=401, detail="Invalid Resend signature") from exc
    signatures = [part.strip().removeprefix("v1,") for part in svix_signature.split()]
    if not any(hmac.compare_digest(expected, candidate) for candidate in signatures):
        raise HTTPException(status_code=401, detail="Invalid Resend signature")


def _event_time(value: object) -> datetime:
    if not isinstance(value, str):
        return datetime.now(UTC)
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return datetime.now(UTC)


@router.post("/resend")
async def resend_webhook(
    request: Request,
    svix_id: str | None = Header(None, alias="svix-id"),
    svix_timestamp: str | None = Header(None, alias="svix-timestamp"),
    svix_signature: str | None = Header(None, alias="svix-signature"),
    db: AsyncSession = Depends(get_db),
) -> dict[str, str]:
    payload = await request.body()
    _verify_resend_signature(
        payload,
        svix_id=svix_id,
        svix_timestamp=svix_timestamp,
        svix_signature=svix_signature,
    )
    body = await request.json()
    event_type = body.get("type")
    data = body.get("data") or {}
    if not isinstance(event_type, str) or not svix_id:
        raise HTTPException(status_code=400, detail="Malformed Resend webhook")

    db.add(ResendWebhookEvent(svix_id=svix_id, event_type=event_type))
    try:
        await db.flush()
    except IntegrityError:
        await db.rollback()
        return {"status": "duplicate"}

    message_id = data.get("email_id")
    if not isinstance(message_id, str):
        await db.commit()
        return {"status": "ignored"}
    attempt = (
        await db.execute(
            select(SupportLinkDeliveryAttempt).where(
                SupportLinkDeliveryAttempt.provider_message_id == message_id
            )
        )
    ).scalar_one_or_none()
    if attempt is None:
        await db.commit()
        return {"status": "ignored"}
    delivery = await db.get(SupportLinkDelivery, attempt.delivery_id)
    if delivery is None:
        await db.commit()
        return {"status": "ignored"}

    occurred_at = _event_time(body.get("created_at"))
    if (
        delivery.last_provider_event_at
        and occurred_at < delivery.last_provider_event_at
    ):
        await db.commit()
        return {"status": "out_of_order"}
    delivery.last_provider_event_at = occurred_at

    match event_type:
        case "email.delivered":
            delivery.status = "delivered"
            delivery.next_retry_at = None
            delivery.error_code = None
        case "email.delivery_delayed":
            if delivery.status != "delivered":
                delivery.status = "delayed"
                if not delivery.auto_retry_used:
                    delivery.next_retry_at = (
                        datetime.now(UTC) + SUPPORT_LINK_RETRY_DELAY
                    )
        case "email.bounced" | "email.suppressed":
            delivery.status = (
                "bounced" if event_type == "email.bounced" else "suppressed"
            )
            delivery.next_retry_at = None
            delivery.error_code = event_type
            sentry_sdk.capture_message(
                "support_link_delivery_terminal_failure", level="error"
            )
        case "email.failed":
            delivery.status = "failed"
            delivery.next_retry_at = None
            delivery.error_code = event_type
            sentry_sdk.capture_message(
                "support_link_delivery_terminal_failure", level="error"
            )
        case "email.sent":
            if delivery.status not in ("delivered", "delayed"):
                delivery.status = "accepted"
        case _:
            logger.info("support_link.resend_event_ignored", event_type=event_type)
    await db.commit()
    return {"status": "processed"}
