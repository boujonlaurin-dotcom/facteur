"""Webhook Stripe — parcours « Soutien à prix libre ».

Monté sur `/api/webhooks/stripe`. Vérifie la signature (`construct_event`),
garantit l'idempotence via la table `stripe_events` (INSERT ON CONFLICT DO
NOTHING dans la MÊME transaction que le traitement : un échec de traitement
rollback aussi l'insertion, donc le retry Stripe re-traite ; un doublon déjà
committé est ignoré). Répond 200 sauf signature invalide (401) ou échec de
traitement (500 -> retry Stripe).
"""

import sentry_sdk
import structlog
from fastapi import APIRouter, Depends, Header, HTTPException, Request, status
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.subscription import StripeEvent
from app.services.revenuecat_grant_service import RevenueCatGrantService
from app.services.stripe_service import construct_event
from app.services.subscription_service import SubscriptionService

router = APIRouter()
logger = structlog.get_logger()


@router.post("/stripe")
async def stripe_webhook(
    request: Request,
    stripe_signature: str = Header(None, alias="Stripe-Signature"),
    db: AsyncSession = Depends(get_db),
) -> dict[str, str]:
    """Reçoit et traite les events Stripe du parcours soutien."""
    payload = await request.body()
    event = construct_event(payload, stripe_signature)  # 401/503 si invalide

    event_id = event["id"]
    event_type = event["type"]
    obj = event["data"]["object"]

    logger.info("stripe.webhook_received", event_type=event_type, event_id=event_id)

    # Idempotence : on tente d'insérer l'event ; s'il existe déjà (committé par
    # une livraison précédente), on ne traite pas. L'insert n'est PAS committé
    # tant que le traitement n'a pas réussi -> un échec rollback l'insert et le
    # retry Stripe re-traite proprement.
    insert_stmt = (
        pg_insert(StripeEvent)
        .values(event_id=event_id, event_type=event_type)
        .on_conflict_do_nothing(index_elements=["event_id"])
        .returning(StripeEvent.event_id)
    )
    inserted = (await db.execute(insert_stmt)).scalar_one_or_none()
    if inserted is None:
        await db.rollback()
        logger.info("stripe.webhook_duplicate", event_id=event_id)
        return {"status": "duplicate"}

    try:
        service = SubscriptionService(db)
        grant = RevenueCatGrantService()

        match event_type:
            case "checkout.session.completed":
                await service.handle_stripe_checkout_completed(obj)
            case "invoice.paid":
                await service.handle_stripe_invoice_paid(obj, grant)
            case "customer.subscription.deleted":
                await service.handle_stripe_subscription_deleted(obj, grant)
            case "invoice.payment_failed":
                await service.handle_stripe_payment_failed(obj)
            case _:
                logger.info("stripe.webhook_unhandled", event_type=event_type)

        await db.commit()
    except Exception as exc:  # noqa: BLE001 - on rollback + remonte en 500
        await db.rollback()
        logger.error("stripe.webhook_error", event_type=event_type, error=str(exc))
        sentry_sdk.capture_exception(exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Webhook processing failed",
        ) from exc

    return {"status": "processed"}
