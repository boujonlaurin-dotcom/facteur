"""Service abonnement."""

import contextlib
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import sentry_sdk
import structlog
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.subscription import SupporterMessage, UserSubscription
from app.schemas.subscription import SubscriptionResponse, SubscriptionStatus
from app.services.posthog_client import get_posthog_client
from app.services.revenuecat_grant_service import RevenueCatGrantService

logger = structlog.get_logger()


class SubscriptionService:
    """Service pour la gestion des abonnements.

    RevenueCat est la source de vérité de l'entitlement `premium`.
    Cette table sert de miroir requêtable pour l'analytics et le back-office.
    Les transitions de status sont déclenchées par les webhooks RevenueCat.
    """

    TRIAL_DAYS = 7
    # Marge de grâce ajoutée à l'entitlement promotionnel RevenueCat au-delà de
    # la fin de période Stripe : absorbe le délai des webhooks de renouvellement.
    GRANT_GRACE_DAYS = 3

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

    # ─────────────────────────────────────────────────────────────────────
    # Stripe (parcours « Soutien à prix libre »)
    #
    # L'idempotence globale des webhooks Stripe est portée par la table
    # `stripe_events` (INSERT ON CONFLICT côté routeur) : ces handlers n'ont
    # donc pas à re-dédupliquer. Le grant/revoke RevenueCat est lui-même
    # idempotent (re-grant = extension, revoke_promotionals = no-op si absent).
    # ─────────────────────────────────────────────────────────────────────

    @staticmethod
    def _parse_seconds(value: int | str | None) -> datetime | None:
        """Convertit un timestamp Stripe (secondes epoch) en datetime UTC.

        Exprimé via `_parse_ms` (source unique de la conversion epoch -> datetime
        naïf UTC) : le montant est en secondes, on repasse en ms.
        """
        if value is None:
            return None
        try:
            return SubscriptionService._parse_ms(int(value) * 1000)
        except (TypeError, ValueError, OSError):
            return None

    @staticmethod
    def _invoice_period_end(invoice: dict) -> datetime | None:
        """Fin de période facturée : ligne d'abonnement d'abord, puis fallback."""
        lines = (invoice.get("lines") or {}).get("data") or []
        if lines:
            period = lines[0].get("period") or {}
            end = SubscriptionService._parse_seconds(period.get("end"))
            if end:
                return end
        return SubscriptionService._parse_seconds(invoice.get("period_end"))

    async def _resolve_subscription_by_stripe(
        self,
        *,
        stripe_subscription_id: str | None = None,
        stripe_customer_id: str | None = None,
    ) -> UserSubscription | None:
        """Retrouve la ligne miroir via l'id d'abonnement puis de client Stripe."""
        if stripe_subscription_id:
            result = await self.db.execute(
                select(UserSubscription).where(
                    UserSubscription.stripe_subscription_id == stripe_subscription_id
                )
            )
            row = result.scalar_one_or_none()
            if row:
                return row
        if stripe_customer_id:
            result = await self.db.execute(
                select(UserSubscription).where(
                    UserSubscription.stripe_customer_id == stripe_customer_id
                )
            )
            return result.scalar_one_or_none()
        return None

    async def handle_stripe_checkout_completed(self, session: dict) -> None:
        """`checkout.session.completed` : persiste le mapping user <-> Stripe.

        Le grant Premium est posé par `handle_stripe_invoice_paid` (qui connaît la
        période) ; ici on ne fait que relier `user_id` aux ids Stripe.
        """
        metadata = session.get("metadata") or {}
        user_id = session.get("client_reference_id") or metadata.get("user_id")
        if not user_id:
            logger.warning("stripe.checkout_completed_missing_user")
            sentry_sdk.capture_message(
                "stripe.checkout_completed_missing_user", level="warning"
            )
            return

        subscription = await self._get_or_create_subscription(user_id)
        subscription.provider = "stripe"
        if session.get("customer"):
            subscription.stripe_customer_id = session["customer"]
        if session.get("subscription"):
            subscription.stripe_subscription_id = session["subscription"]

        raw_amount = metadata.get("support_amount_cents") or session.get("amount_total")
        if raw_amount is not None:
            with contextlib.suppress(TypeError, ValueError):
                subscription.support_amount_cents = int(raw_amount)

        # Mot de soutien optionnel : persisté non publié (modération avant le
        # mur public). Seuls les paiements engagés (ce webhook) laissent un mot.
        raw_message = (metadata.get("support_message") or "").strip()
        if raw_message:
            self.db.add(
                SupporterMessage(
                    id=uuid4(),
                    user_id=subscription.user_id,
                    message=raw_message,
                    stripe_session_id=session.get("id"),
                    published=False,
                )
            )

        self._emit(
            subscription.user_id,
            "support_checkout_completed",
            {
                "amount_cents": subscription.support_amount_cents,
                "has_message": bool(raw_message),
            },
        )
        await self.db.flush()

    async def handle_stripe_invoice_paid(
        self, invoice: dict, grant_service: RevenueCatGrantService | None = None
    ) -> None:
        """`invoice.paid` : passe l'abonnement `active` puis (re-)grant Premium."""
        grant_service = grant_service or RevenueCatGrantService()

        subscription_id = invoice.get("subscription")
        customer_id = invoice.get("customer")
        user_id = (
            (invoice.get("subscription_details") or {}).get("metadata") or {}
        ).get("user_id")

        subscription: UserSubscription | None = None
        if not user_id:
            subscription = await self._resolve_subscription_by_stripe(
                stripe_subscription_id=subscription_id,
                stripe_customer_id=customer_id,
            )
            if subscription:
                user_id = str(subscription.user_id)

        if not user_id:
            logger.warning(
                "stripe.invoice_paid_unresolved_user",
                subscription=subscription_id,
                customer=customer_id,
            )
            sentry_sdk.capture_message(
                "stripe.invoice_paid_unresolved_user", level="warning"
            )
            return

        if subscription is None:
            subscription = await self._get_or_create_subscription(user_id)

        subscription.provider = "stripe"
        if subscription_id:
            subscription.stripe_subscription_id = subscription_id
        if customer_id:
            subscription.stripe_customer_id = customer_id
        subscription.status = "active"
        subscription.current_period_start = (
            self._parse_seconds(invoice.get("period_start"))
            or subscription.current_period_start
        )
        period_end = self._invoice_period_end(invoice)
        if period_end:
            subscription.current_period_end = period_end
        await self.db.flush()

        if period_end:
            # `period_end` est un datetime naïf en UTC (cf. `_parse_seconds`) :
            # on le rend timezone-aware avant `.timestamp()`, sinon Python
            # l'interprète en heure locale et décale `end_time_ms` de l'offset
            # UTC du serveur.
            end_utc = period_end.replace(tzinfo=UTC)
            end_time_ms = int(
                (end_utc + timedelta(days=self.GRANT_GRACE_DAYS)).timestamp() * 1000
            )
            await grant_service.grant_premium(user_id, end_time_ms)

        self._emit(
            subscription.user_id,
            "support_invoice_paid",
            {"amount_cents": subscription.support_amount_cents},
        )

    async def handle_stripe_subscription_deleted(
        self, sub_obj: dict, grant_service: RevenueCatGrantService | None = None
    ) -> None:
        """`customer.subscription.deleted` : status `cancelled` + revoke Premium."""
        grant_service = grant_service or RevenueCatGrantService()

        subscription_id = sub_obj.get("id")
        customer_id = sub_obj.get("customer")
        user_id = (sub_obj.get("metadata") or {}).get("user_id")

        subscription: UserSubscription | None = None
        if not user_id:
            subscription = await self._resolve_subscription_by_stripe(
                stripe_subscription_id=subscription_id,
                stripe_customer_id=customer_id,
            )
            if subscription:
                user_id = str(subscription.user_id)
        else:
            subscription = await self._get_subscription(user_id)

        if not user_id:
            logger.warning(
                "stripe.subscription_deleted_unresolved_user",
                subscription=subscription_id,
            )
            sentry_sdk.capture_message(
                "stripe.subscription_deleted_unresolved_user", level="warning"
            )
            return

        if subscription is not None:
            subscription.status = "cancelled"
            await self.db.flush()

        await grant_service.revoke_premium(user_id)
        self._emit(UUID(user_id), "support_subscription_cancelled", {})

    async def handle_stripe_payment_failed(self, invoice: dict) -> None:
        """`invoice.payment_failed` : status `past_due` (pas de revoke immédiat).

        L'entitlement promotionnel expire de lui-même à `end_time_ms` si les
        paiements ne reprennent pas ; on ne coupe pas l'accès tout de suite.
        """
        subscription = await self._resolve_subscription_by_stripe(
            stripe_subscription_id=invoice.get("subscription"),
            stripe_customer_id=invoice.get("customer"),
        )
        if subscription is None:
            logger.warning(
                "stripe.payment_failed_unresolved_user",
                subscription=invoice.get("subscription"),
            )
            return

        subscription.status = "past_due"
        await self.db.flush()
        self._emit(subscription.user_id, "support_payment_failed", {})
