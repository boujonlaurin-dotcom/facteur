"""Service abonnement."""

from datetime import datetime, timedelta
from uuid import UUID, uuid4

import structlog
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.subscription import UserSubscription
from app.schemas.subscription import SubscriptionResponse, SubscriptionStatus
from app.services.posthog_client import get_posthog_client

logger = structlog.get_logger()


class SubscriptionService:
    """Service pour la gestion des abonnements.

    RevenueCat est la source de vérité de l'entitlement `premium`.
    Cette table sert de miroir requêtable pour l'analytics et le back-office.
    Les transitions de status sont déclenchées par les webhooks RevenueCat.
    """

    TRIAL_DAYS = 7

    def __init__(self, db: AsyncSession):
        self.db = db
        self._posthog = get_posthog_client()

    async def get_subscription_status(self, user_id: str) -> SubscriptionResponse:
        """Récupère le statut de l'abonnement."""
        subscription = await self._get_subscription(user_id)

        if not subscription:
            subscription = await self._create_trial(user_id)

        return SubscriptionResponse(
            status=SubscriptionStatus(subscription.status),
            trial_end=subscription.trial_end
            if subscription.status == "trial"
            else None,
            current_period_end=subscription.current_period_end,
            days_remaining=subscription.days_remaining,
            is_premium=subscription.status in ("active", "trial"),
            can_access=subscription.is_active,
            product_id=subscription.product_id,
        )

    async def _get_subscription(self, user_id: str) -> UserSubscription | None:
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

    async def _get_or_create_subscription(self, app_user_id: str) -> UserSubscription:
        """Récupère ou crée une ligne pour un app_user_id (Supabase user_id).

        Nécessaire pour le flux web : un achat depuis la landing peut arriver
        avant qu'une ligne user_subscriptions existe (cas où le user vient
        d'être créé en passwordless juste avant le checkout).
        """
        subscription = await self._get_subscription(app_user_id)
        if subscription is None:
            subscription = await self._create_trial(app_user_id)
        return subscription

    @staticmethod
    def _parse_ms(value: int | str | None) -> datetime | None:
        """Convertit un timestamp ms RevenueCat en datetime UTC."""
        if value is None:
            return None
        try:
            return datetime.utcfromtimestamp(int(value) / 1000)
        except (TypeError, ValueError):
            return None

    def _is_duplicate_event(
        self, subscription: UserSubscription, event_id: str | None
    ) -> bool:
        """Détecte les rejeux du même event RevenueCat (idempotence)."""
        if event_id is None:
            return False
        if subscription.last_event_id == event_id:
            logger.info(
                "subscription.webhook.duplicate_event",
                event_id=event_id,
                user_id=str(subscription.user_id),
            )
            return True
        return False

    def _mark_event(self, subscription: UserSubscription, event_id: str | None) -> None:
        if event_id is not None:
            subscription.last_event_id = event_id

    def _emit(self, user_id: UUID, event: str, props: dict | None = None) -> None:
        """Émet un event PostHog côté serveur (fire-and-forget)."""
        self._posthog.capture(user_id, event, props or {})

    async def handle_initial_purchase(self, app_user_id: str, event_data: dict) -> None:
        """Gère un premier achat (essai 7j ou direct).

        RevenueCat envoie INITIAL_PURCHASE pour le premier paiement.
        Si `period_type == "TRIAL"`, l'abonnement est en essai gratuit.
        Sinon c'est un abonnement payant direct (cas peu probable en V1).
        """
        subscription = await self._get_or_create_subscription(app_user_id)
        event_id = event_data.get("id")
        if self._is_duplicate_event(subscription, event_id):
            return

        period_type = event_data.get("period_type", "NORMAL")
        product_id = event_data.get("product_id")
        original_app_user_id = event_data.get("original_app_user_id")

        subscription.product_id = product_id
        if original_app_user_id:
            subscription.revenuecat_user_id = original_app_user_id
        subscription.current_period_start = datetime.utcnow()
        subscription.current_period_end = self._parse_ms(
            event_data.get("expiration_at_ms")
        )

        if period_type == "TRIAL":
            subscription.status = "trial"
            subscription.trial_start = datetime.utcnow()
            subscription.trial_end = (
                subscription.current_period_end
                or datetime.utcnow() + timedelta(days=self.TRIAL_DAYS)
            )
            self._emit(
                subscription.user_id,
                "trial_started",
                {"product_id": product_id},
            )
        else:
            subscription.status = "active"
            self._emit(
                subscription.user_id,
                "subscription_activated",
                {"product_id": product_id, "from": "initial_purchase"},
            )

        self._mark_event(subscription, event_id)
        await self.db.flush()

    async def handle_renewal(self, app_user_id: str, event_data: dict) -> None:
        """Gère un renouvellement (sortie d'essai vers payant, ou cycle suivant)."""
        subscription = await self._get_or_create_subscription(app_user_id)
        event_id = event_data.get("id")
        if self._is_duplicate_event(subscription, event_id):
            return

        was_trial = subscription.status == "trial"
        subscription.status = "active"
        subscription.product_id = (
            event_data.get("product_id") or subscription.product_id
        )
        subscription.current_period_start = datetime.utcnow()
        subscription.current_period_end = self._parse_ms(
            event_data.get("expiration_at_ms")
        )

        self._emit(
            subscription.user_id,
            "subscription_activated" if was_trial else "subscription_renewed",
            {"product_id": subscription.product_id},
        )
        self._mark_event(subscription, event_id)
        await self.db.flush()

    async def handle_cancellation(self, app_user_id: str, event_data: dict) -> None:
        """Gère une annulation (l'accès reste actif jusqu'à expiration)."""
        subscription = await self._get_or_create_subscription(app_user_id)
        event_id = event_data.get("id")
        if self._is_duplicate_event(subscription, event_id):
            return

        subscription.status = "cancelled"
        self._emit(
            subscription.user_id,
            "subscription_cancelled",
            {"product_id": subscription.product_id},
        )
        self._mark_event(subscription, event_id)
        await self.db.flush()

    async def handle_expiration(self, app_user_id: str, event_data: dict) -> None:
        """Gère une expiration (fin réelle d'accès)."""
        subscription = await self._get_or_create_subscription(app_user_id)
        event_id = event_data.get("id")
        if self._is_duplicate_event(subscription, event_id):
            return

        subscription.status = "expired"
        self._emit(
            subscription.user_id,
            "subscription_expired",
            {"product_id": subscription.product_id},
        )
        self._mark_event(subscription, event_id)
        await self.db.flush()

    async def handle_uncancellation(self, app_user_id: str, event_data: dict) -> None:
        """Gère une réactivation après annulation (user revient avant expiration)."""
        subscription = await self._get_or_create_subscription(app_user_id)
        event_id = event_data.get("id")
        if self._is_duplicate_event(subscription, event_id):
            return

        subscription.status = "active"
        self._emit(
            subscription.user_id,
            "subscription_activated",
            {"product_id": subscription.product_id, "from": "uncancellation"},
        )
        self._mark_event(subscription, event_id)
        await self.db.flush()

    async def handle_product_change(self, app_user_id: str, event_data: dict) -> None:
        """Gère un changement de produit (ex: monthly → annual)."""
        subscription = await self._get_or_create_subscription(app_user_id)
        event_id = event_data.get("id")
        if self._is_duplicate_event(subscription, event_id):
            return

        new_product = event_data.get("new_product_id") or event_data.get("product_id")
        if new_product:
            subscription.product_id = new_product
        subscription.current_period_end = (
            self._parse_ms(event_data.get("expiration_at_ms"))
            or subscription.current_period_end
        )

        self._mark_event(subscription, event_id)
        await self.db.flush()
