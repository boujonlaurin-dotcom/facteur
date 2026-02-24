"""Routes abonnement."""

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user_id
from app.schemas.subscription import SubscriptionResponse
from app.services.subscription_service import SubscriptionService

router = APIRouter()


@router.get("", response_model=SubscriptionResponse)
async def get_subscription(
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> SubscriptionResponse:
    """Récupérer le statut de l'abonnement."""
    service = SubscriptionService(db)
    subscription = await service.get_subscription_status(user_id)

    return subscription


@router.post("/restore")
async def restore_purchases(
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> dict[str, str]:
    """
    Restaurer les achats.

    Note: La restauration est gérée par RevenueCat côté client.
    Ce endpoint synchronise l'état avec le backend.
    """
    service = SubscriptionService(db)
    await service.sync_with_revenuecat(user_id)

    return {"status": "synced"}
