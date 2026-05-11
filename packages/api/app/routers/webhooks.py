"""Routes webhooks."""

import hmac

import structlog
from fastapi import APIRouter, Depends, Header, HTTPException, Request, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.database import get_db
from app.services.subscription_service import SubscriptionService

router = APIRouter()
logger = structlog.get_logger()


@router.post("/revenuecat")
async def revenuecat_webhook(
    request: Request,
    authorization: str | None = Header(None),
    db: AsyncSession = Depends(get_db),
) -> dict[str, str]:
    """
    Webhook RevenueCat pour les événements d'abonnement.

    Auth : RevenueCat envoie le secret configuré dans le dashboard tel quel
    via le header `Authorization` (cf. doc « Authorization Header
    Verification »). On compare avec `Bearer <secret>`.

    Événements gérés:
    - INITIAL_PURCHASE
    - RENEWAL
    - CANCELLATION
    - EXPIRATION
    """
    settings = get_settings()
    if settings.revenuecat_webhook_secret:
        expected = f"Bearer {settings.revenuecat_webhook_secret}"
        if not authorization or not hmac.compare_digest(authorization, expected):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid authorization",
            )

    # Parser l'événement
    try:
        body = await request.json()
        event_data = body.get("event", {})
        event_type = event_data.get("type")
        app_user_id = event_data.get("app_user_id")

        logger.info(
            "RevenueCat webhook received",
            event_type=event_type,
            app_user_id=app_user_id,
        )

        if not app_user_id:
            logger.warning("Webhook without app_user_id")
            return {"status": "ignored"}

        # Traiter l'événement
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
            case _:
                logger.info("Unhandled event type", event_type=event_type)

        return {"status": "processed"}

    except Exception as e:
        logger.error("Webhook processing error", error=str(e))
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Webhook processing failed",
        )
