"""Service abonnement."""

from datetime import datetime, timedelta
from typing import Optional
from uuid import UUID, uuid4

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.subscription import UserSubscription
from app.schemas.subscription import SubscriptionResponse, SubscriptionStatus


class SubscriptionService:
    """Service pour la gestion des abonnements."""

    TRIAL_DAYS = 7

    def __init__(self, db: AsyncSession):
        self.db = db

    async def get_subscription_status(self, user_id: str) -> SubscriptionResponse:
        """Récupère le statut de l'abonnement."""
        subscription = await self._get_subscription(user_id)

        if not subscription:
            # Créer un trial par défaut
            subscription = await self._create_trial(user_id)

        return SubscriptionResponse(
            status=SubscriptionStatus(subscription.status),
            trial_end=subscription.trial_end if subscription.status == "trial" else None,
            current_period_end=subscription.current_period_end,
            days_remaining=subscription.days_remaining,
            is_premium=subscription.status in ("active", "trial"),
            can_access=subscription.is_active,
            product_id=subscription.product_id,
        )

    async def _get_subscription(self, user_id: str) -> Optional[UserSubscription]:
        """Récupère l'abonnement d'un utilisateur."""
        query = select(UserSubscription).where(
            UserSubscription.user_id == UUID(user_id)
        )
        result = await self.db.execute(query)
        return result.scalar_one_or_none()

    async def _create_trial(self, user_id: str) -> UserSubscription:
        """Crée une période d'essai pour un utilisateur."""
        subscription = UserSubscription(
            id=uuid4(),
            user_id=UUID(user_id),
            status="trial",
            trial_start=datetime.utcnow(),
            trial_end=datetime.utcnow() + timedelta(days=self.TRIAL_DAYS),
        )
        self.db.add(subscription)
        await self.db.flush()

        return subscription

    async def sync_with_revenuecat(self, user_id: str) -> None:
        """Synchronise l'état avec RevenueCat."""
        # TODO: Appeler l'API RevenueCat pour vérifier l'état
        pass

    async def handle_initial_purchase(
        self, app_user_id: str, event_data: dict
    ) -> None:
        """Gère un premier achat."""
        subscription = await self._get_subscription(app_user_id)

        if subscription:
            subscription.status = "active"
            subscription.product_id = event_data.get("product_id")
            subscription.revenuecat_user_id = event_data.get("original_app_user_id")
            subscription.current_period_start = datetime.utcnow()

            # Parser la date d'expiration de RevenueCat
            expiration = event_data.get("expiration_at_ms")
            if expiration:
                subscription.current_period_end = datetime.fromtimestamp(
                    expiration / 1000
                )

            await self.db.flush()

    async def handle_renewal(self, app_user_id: str, event_data: dict) -> None:
        """Gère un renouvellement."""
        subscription = await self._get_subscription(app_user_id)

        if subscription:
            subscription.status = "active"
            subscription.current_period_start = datetime.utcnow()

            expiration = event_data.get("expiration_at_ms")
            if expiration:
                subscription.current_period_end = datetime.fromtimestamp(
                    expiration / 1000
                )

            await self.db.flush()

    async def handle_cancellation(self, app_user_id: str, event_data: dict) -> None:
        """Gère une annulation."""
        subscription = await self._get_subscription(app_user_id)

        if subscription:
            subscription.status = "cancelled"
            await self.db.flush()

    async def handle_expiration(self, app_user_id: str, event_data: dict) -> None:
        """Gère une expiration."""
        subscription = await self._get_subscription(app_user_id)

        if subscription:
            subscription.status = "expired"
            await self.db.flush()

