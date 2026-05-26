"""Routes webhooks."""

import hashlib
import hmac

import structlog
from fastapi import APIRouter, Depends, Header, HTTPException, Request, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.database import get_db
from app.services.subscription_service import SubscriptionService

router = APIRouter()
logger = structlog.get_logger()
settings = get_settings()


def verify_revenuecat_signature(
    payload: bytes,
    signature: str,
    secret: str,
) -> bool:
    """Vérifie la signature HMAC SHA-256 du webhook RevenueCat.

    RevenueCat envoie soit un header `Authorization: Bearer <secret>` (mode
    secret partagé), soit un HMAC. On supporte les deux : si la signature
    fournie est `Bearer <secret>`, on compare en clair ; sinon on calcule
    le HMAC.
    """
    if signature.startswith("Bearer "):
        token = signature.removeprefix("Bearer ").strip()
        return hmac.compare_digest(token, secret)

    expected = hmac.new(
        secret.encode(),
        payload,
        hashlib.sha256,
    ).hexdigest()

    return hmac.compare_digest(expected, signature)


@router.post("/revenuecat")
async def revenuecat_webhook(
    request: Request,
    x_revenuecat_signature: str = Header(None, alias="X-RevenueCat-Signature"),
    authorization: str = Header(None),
    db: AsyncSession = Depends(get_db),
) -> dict[str, str]:
    """Webhook RevenueCat pour les événements d'abonnement.

    Événements gérés : INITIAL_PURCHASE, RENEWAL, CANCELLATION, EXPIRATION,
    UNCANCELLATION, PRODUCT_CHANGE. Idempotent via `event.id` (rejeu sans effet).
    Retourne 200 systématiquement (sauf signature invalide) pour éviter les
    retries RevenueCat sur des events ignorés/inconnus.
    """
    if settings.is_production and settings.revenuecat_webhook_secret:
        payload = await request.body()
        signature = x_revenuecat_signature or authorization

        if not signature:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Missing signature",
            )

        if not verify_revenuecat_signature(
            payload,
            signature,
            settings.revenuecat_webhook_secret,
        ):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid signature",
            )

    try:
        body = await request.json()
        event_data = body.get("event", {})
        event_type = event_data.get("type")
        event_id = event_data.get("id")
        app_user_id = event_data.get("app_user_id")

        logger.info(
            "revenuecat.webhook_received",
            event_type=event_type,
            event_id=event_id,
            app_user_id=app_user_id,
        )

        if not app_user_id:
            logger.warning("revenuecat.webhook_missing_app_user_id")
            return {"status": "ignored"}

        service = SubscriptionService(db)

        match event_type:
            case "INITIAL_PURCHASE":
                await service.handle_initial_purchase(app_user_id, event_data)
            case "RENEWAL":
                await service.handle_renewal(app_user_id, event_data)
            case "CANCELLATION":
                await service.handle_cancellation(app_user_id, event_data)
            case "EXPIRATION":
                await service.handle_expiration(app_user_id, event_data)
            case "UNCANCELLATION":
                await service.handle_uncancellation(app_user_id, event_data)
            case "PRODUCT_CHANGE":
                await service.handle_product_change(app_user_id, event_data)
            case (
                "NON_RENEWING_PURCHASE"
                | "BILLING_ISSUE"
                | "SUBSCRIBER_ALIAS"
                | "TRANSFER"
                | "TEST"
            ):
                logger.info("revenuecat.webhook_noop", event_type=event_type)
            case _:
                logger.info("revenuecat.webhook_unhandled", event_type=event_type)

        return {"status": "processed"}

    except HTTPException:
        raise
    except Exception as e:
        logger.error("revenuecat.webhook_error", error=str(e))
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Webhook processing failed",
        )
