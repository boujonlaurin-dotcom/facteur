"""Transport Resend des liens de soutien, sans dépendre d'un OTP Supabase."""

from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from urllib.parse import urlencode

import certifi
import httpx
import sentry_sdk
import structlog
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.models.subscription import (
    SUPPORT_LINK_RETRY_DELAY,
    SupportLinkDelivery,
    SupportLinkDeliveryAttempt,
)
from app.services.checkout_token import mint_checkout_token

logger = structlog.get_logger()
# Le gabarit est statique (seul `{{CHECKOUT_URL}}` varie) : on le lit une fois au
# chargement du module plutôt qu'à chaque envoi, pour ne pas bloquer la boucle
# asyncio sur un accès disque à chaque tentative.
_TEMPLATE_HTML = (
    Path(__file__).parent.parent / "templates" / "soutien-checkout-link.html"
).read_text(encoding="utf-8")


@dataclass(frozen=True)
class ResendSendResult:
    message_id: str


class ResendSendError(Exception):
    def __init__(self, code: str, *, temporary: bool) -> None:
        self.code = code
        self.temporary = temporary
        super().__init__(code)


def _render_email(checkout_url: str) -> tuple[str, str]:
    html = _TEMPLATE_HTML.replace("{{CHECKOUT_URL}}", checkout_url)
    text = (
        "Merci pour ta demande de soutien.\n\n"
        "Choisis ton soutien mensuel, librement et sans engagement :\n"
        f"{checkout_url}\n\n"
        "Ce lien est valable 24 heures.\n\nDjango & Laurin, tes facteurs"
    )
    return html, text


async def send_support_link_email(
    delivery: SupportLinkDelivery, *, attempt_number: int
) -> ResendSendResult:
    """Demande l'envoi à Resend et retourne son identifiant traçable.

    La clé d'idempotence est stable pour une tentative donnée : un timeout
    réseau peut donc être rejoué sans créer de double enveloppe pendant les
    24 heures de fenêtre Resend.
    """
    settings = get_settings()
    if not settings.support_link_delivery_enabled:
        raise ResendSendError("resend_not_configured", temporary=False)

    token = mint_checkout_token(str(delivery.user_id), delivery.recipient_email)
    checkout_url = f"{settings.public_web_base_url}/soutenir?{urlencode({'t': token})}"
    html, text = _render_email(checkout_url)
    body = {
        "from": settings.resend_from_email,
        "to": [delivery.recipient_email],
        "subject": "Merci pour ta demande de soutien",
        "html": html,
        "text": text,
        "tags": [
            {"name": "flow", "value": "support-link"},
            {"name": "delivery_id", "value": str(delivery.id)},
        ],
    }
    try:
        async with httpx.AsyncClient(verify=certifi.where(), timeout=10.0) as client:
            response = await client.post(
                "https://api.resend.com/emails",
                headers={
                    "Authorization": f"Bearer {settings.resend_api_key}",
                    "Content-Type": "application/json",
                    "Idempotency-Key": f"support-link/{delivery.id}/{attempt_number}",
                },
                json=body,
            )
    except httpx.TimeoutException as exc:
        raise ResendSendError("resend_timeout", temporary=True) from exc
    except httpx.HTTPError as exc:
        raise ResendSendError("resend_network_error", temporary=True) from exc

    if response.status_code not in (200, 201):
        temporary = response.status_code == 429 or response.status_code >= 500
        logger.warning(
            "support_link.resend_send_failed",
            delivery_id=str(delivery.id),
            status=response.status_code,
        )
        raise ResendSendError(
            f"resend_http_{response.status_code}", temporary=temporary
        )

    message_id = response.json().get("id")
    if not isinstance(message_id, str) or not message_id:
        raise ResendSendError("resend_missing_message_id", temporary=True)
    return ResendSendResult(message_id=message_id)


async def attempt_support_link_delivery(
    db: AsyncSession, delivery: SupportLinkDelivery, *, is_auto_retry: bool
) -> ResendSendError | None:
    """Persiste une tentative Resend et retourne l'erreur éventuelle.

    Cette fonction est partagée par la route et le scheduler, ce qui évite que
    la relance importe un routeur FastAPI (et garde une seule sémantique de
    statut/idempotence).
    """
    attempt_number = delivery.attempts + 1
    try:
        result = await send_support_link_email(delivery, attempt_number=attempt_number)
    except ResendSendError as exc:
        delivery.error_code = exc.code
        if exc.temporary and not delivery.auto_retry_used:
            delivery.status = "queued"
            delivery.next_retry_at = datetime.now(UTC) + SUPPORT_LINK_RETRY_DELAY
            if is_auto_retry:
                delivery.auto_retry_used = True
        else:
            delivery.status = "failed"
            delivery.next_retry_at = None
            sentry_sdk.capture_message("support_link_delivery_failed", level="error")
        await db.commit()
        return exc

    delivery.attempts = attempt_number
    if is_auto_retry:
        delivery.auto_retry_used = True
    delivery.status = "accepted"
    delivery.error_code = None
    delivery.next_retry_at = None
    db.add(
        SupportLinkDeliveryAttempt(
            delivery_id=delivery.id,
            attempt_number=attempt_number,
            provider_message_id=result.message_id,
        )
    )
    await db.commit()
    return None
