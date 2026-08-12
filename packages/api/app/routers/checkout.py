"""Router checkout — entrée web pour le paiement Premium.

Flow MVP (V1 paywall) :
1. Le visiteur landing saisit son email + choisit une offering (`default` ou
   `founder`).
2. On crée (ou récupère) un user Supabase passwordless via l'Admin API.
3. On initialise une ligne `user_subscriptions` minimale pour ce user.
4. On renvoie l'URL RevenueCat Web Billing pré-remplie avec `app_user_id` =
   user_id Supabase. La landing redirige le visiteur dessus.

RevenueCat reste la source de vérité de l'entitlement `premium` après achat.
Le webhook `/api/webhooks/revenuecat` met ensuite à jour `user_subscriptions`.
"""

from datetime import UTC, datetime, timedelta
from urllib.parse import urlencode
from uuid import UUID

import certifi
import httpx
import sentry_sdk
import structlog
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.database import get_db
from app.dependencies import CurrentUserIdentity, get_current_user_identity
from app.models.subscription import (
    SUPPORT_LINK_TERMINAL_STATUSES,
    SupporterMessage,
    SupportLinkDelivery,
)
from app.schemas.checkout import (
    CheckoutLinkDeliveryResponse,
    CheckoutSendLinkRequest,
    CheckoutSendLinkResponse,
    CheckoutStartRequest,
    CheckoutStartResponse,
    CreateStripeSessionRequest,
    CreateStripeSessionResponse,
    SupporterMessagePublic,
)
from app.services.checkout_token import (
    CheckoutTokenError,
    verify_checkout_token,
)
from app.services.posthog_client import get_posthog_client
from app.services.stripe_service import create_support_subscription_session
from app.services.subscription_service import SubscriptionService
from app.services.support_link_email import attempt_support_link_delivery

router = APIRouter()
logger = structlog.get_logger()

# RevenueCat Web Billing URLs configurées dans le dashboard RC. La V1 utilise
# des URLs hostées par RevenueCat (mode "Paywall Link") — pas besoin de Stripe.js
# côté landing. Format attendu : `<base>?app_user_id=<user_id>`. Le base diffère
# selon l'offering pour aiguiller `default` vs `founder` (offerings RC distincts).
DEFAULT_WEB_BILLING_BASE_URL = "https://pay.rev.cat/facteur-premium"
FOUNDER_WEB_BILLING_BASE_URL = "https://pay.rev.cat/facteur-founder"

# Page-pont statique servie par la landing (domaine qu'on contrôle) vers laquelle
# le magic link Supabase redirige. Supabase n'honore un `redirect_to` que s'il
# matche l'allow-list « Redirect URLs » : une entrée unique et stable (notre
# domaine) plutôt que le domaine tiers `pay.rev.cat`. La page-pont forwarde
# ensuite vers l'URL RevenueCat passée en `next`.
CHECKOUT_REDIRECT_BASE_URL = "https://facteur.app/checkout-redirect.html"


async def _supabase_admin_lookup_user_by_email(email: str) -> str | None:
    """Retourne le user_id Supabase pour cet email, ou None s'il n'existe pas."""
    settings = get_settings()
    if not (settings.supabase_url and settings.supabase_service_role_key):
        return None

    url = f"{settings.supabase_url}/auth/v1/admin/users?email={email}"
    headers = {
        "Authorization": f"Bearer {settings.supabase_service_role_key}",
        "apikey": settings.supabase_service_role_key,
    }
    async with httpx.AsyncClient(verify=certifi.where(), timeout=10.0) as client:
        resp = await client.get(url, headers=headers)
    if resp.status_code != 200:
        return None
    payload = resp.json()
    users = payload.get("users") if isinstance(payload, dict) else None
    if not users:
        return None
    return users[0].get("id")


async def _supabase_admin_create_user(email: str) -> str:
    """Crée un user Supabase passwordless (email_confirm=true).

    L'utilisateur pourra ensuite se connecter dans l'app via magic link OTP.
    L'appelant doit avoir déjà vérifié l'absence du user via
    `_supabase_admin_lookup_user_by_email`. En cas de collision (race
    condition), le 422 Supabase est rattrapé par un second lookup.
    """
    settings = get_settings()
    if not (settings.supabase_url and settings.supabase_service_role_key):
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Supabase admin config missing",
        )

    url = f"{settings.supabase_url}/auth/v1/admin/users"
    headers = {
        "Authorization": f"Bearer {settings.supabase_service_role_key}",
        "apikey": settings.supabase_service_role_key,
        "Content-Type": "application/json",
    }
    body = {
        "email": email,
        "email_confirm": True,
    }
    async with httpx.AsyncClient(verify=certifi.where(), timeout=10.0) as client:
        resp = await client.post(url, headers=headers, json=body)

    if resp.status_code in (200, 201):
        user_id = resp.json().get("id")
        if user_id:
            return user_id

    if resp.status_code == 422:
        # Email déjà existant (collision sur unique constraint Supabase).
        retry = await _supabase_admin_lookup_user_by_email(email)
        if retry:
            return retry

    logger.warning(
        "checkout.supabase_admin_create_user_failed",
        status=resp.status_code,
        body=resp.text[:500],
    )
    sentry_sdk.capture_message(
        "checkout.supabase_admin_create_user_failed", level="warning"
    )
    raise HTTPException(
        status_code=status.HTTP_502_BAD_GATEWAY,
        detail="Could not create or fetch user",
    )


def _build_checkout_url(offering: str, user_id: str) -> str:
    """Construit l'URL RevenueCat Web Billing pré-remplie."""
    base = (
        FOUNDER_WEB_BILLING_BASE_URL
        if offering == "founder"
        else DEFAULT_WEB_BILLING_BASE_URL
    )
    params = urlencode({"app_user_id": user_id})
    return f"{base}?{params}"


def _build_bridge_url(checkout_url: str) -> str:
    """Enveloppe l'URL RevenueCat dans la page-pont `facteur.app`.

    Le magic link Supabase pointe vers `checkout-redirect.html?next=<url RC>` ;
    la page-pont forwarde vers `next`. `_build_checkout_url` reste la seule
    source de vérité de l'URL RevenueCat.
    """
    return f"{CHECKOUT_REDIRECT_BASE_URL}?{urlencode({'next': checkout_url})}"


@router.post("/start-passwordless", response_model=CheckoutStartResponse)
async def start_passwordless(
    request: CheckoutStartRequest,
    db: AsyncSession = Depends(get_db),
) -> CheckoutStartResponse:
    """Démarre le flow de checkout depuis la landing.

    Crée (ou récupère) le user Supabase, initialise sa ligne user_subscriptions,
    renvoie l'URL RevenueCat Web Billing à laquelle la landing doit rediriger.
    """
    existing_id = await _supabase_admin_lookup_user_by_email(request.email)
    is_new_user = existing_id is None

    user_id = existing_id or await _supabase_admin_create_user(request.email)

    service = SubscriptionService(db)
    await service._get_or_create_subscription(user_id)
    await db.commit()

    checkout_url = _build_checkout_url(request.offering, user_id)

    get_posthog_client().capture(
        user_id=user_id,
        event="checkout_started",
        properties={
            "offering": request.offering,
            "is_new_user": is_new_user,
            "utm_source": request.utm_source,
            "utm_medium": request.utm_medium,
            "utm_campaign": request.utm_campaign,
        },
    )

    logger.info(
        "checkout.start_passwordless",
        user_id=user_id,
        offering=request.offering,
        is_new_user=is_new_user,
    )

    return CheckoutStartResponse(
        user_id=user_id,
        checkout_url=checkout_url,
        is_new_user=is_new_user,
    )


_SUPPORT_LINK_RESEND_COOLDOWN = timedelta(minutes=1)


def _delivery_response(delivery: SupportLinkDelivery) -> CheckoutLinkDeliveryResponse:
    now = datetime.now(UTC)
    can_resend = (
        delivery.status not in SUPPORT_LINK_TERMINAL_STATUSES
        and delivery.created_at is not None
        and now - delivery.created_at >= _SUPPORT_LINK_RESEND_COOLDOWN
    )
    return CheckoutLinkDeliveryResponse(
        delivery_id=delivery.id,
        status=delivery.status,
        can_resend=can_resend,
    )


@router.post("/send-link", response_model=CheckoutSendLinkResponse, status_code=202)
async def send_link(
    request: CheckoutSendLinkRequest,
    current_user: CurrentUserIdentity = Depends(get_current_user_identity),
    db: AsyncSession = Depends(get_db),
) -> CheckoutSendLinkResponse:
    """Demande la livraison Resend d'un lien Stripe au compte courant.

    La réponse 202 signifie uniquement que la demande est durablement suivie;
    l'écran mobile consulte ensuite son statut ``delivered`` ou ``failed``.
    """
    settings = get_settings()
    if not settings.support_link_delivery_enabled:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Support link delivery is not configured",
        )

    user_id = UUID(current_user.user_id)
    latest = (
        await db.execute(
            select(SupportLinkDelivery)
            .where(SupportLinkDelivery.user_id == user_id)
            .order_by(desc(SupportLinkDelivery.created_at))
            .limit(1)
        )
    ).scalar_one_or_none()
    if latest and datetime.now(UTC) - latest.created_at < _SUPPORT_LINK_RESEND_COOLDOWN:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Support link resend is rate-limited, retry in a minute",
        )

    service = SubscriptionService(db)
    await service._get_or_create_subscription(current_user.user_id)
    delivery = SupportLinkDelivery(user_id=user_id, recipient_email=current_user.email)
    db.add(delivery)
    await db.commit()
    await db.refresh(delivery)
    # Première tentative synchrone : on persiste le résultat (le service commit)
    # et on ne remonte un 502 que sur un échec définitif, pour ne pas mentir au
    # client. Une erreur temporaire laisse la relance différée prendre le relais.
    error = await attempt_support_link_delivery(db, delivery, is_auto_retry=False)
    if error is not None and not error.temporary:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Could not request support link delivery",
        ) from error

    get_posthog_client().capture(
        user_id=str(user_id),
        event="checkout_link_sent",
        properties={
            "offering": request.offering,
            "resend": request.resend,
            "flow": "stripe_resend",
            "delivery_status": delivery.status,
        },
    )

    logger.info(
        "checkout.send_link",
        user_id=str(user_id),
        offering=request.offering,
        resend=request.resend,
    )

    return CheckoutSendLinkResponse(
        delivery_id=delivery.id,
        status="accepted" if delivery.status == "accepted" else "queued",
    )


@router.get("/send-link/{delivery_id}", response_model=CheckoutLinkDeliveryResponse)
async def support_link_delivery_status(
    delivery_id: UUID,
    current_user: CurrentUserIdentity = Depends(get_current_user_identity),
    db: AsyncSession = Depends(get_db),
) -> CheckoutLinkDeliveryResponse:
    """Expose uniquement au propriétaire l'état fournisseur de son enveloppe."""
    delivery = await db.get(SupportLinkDelivery, delivery_id)
    if delivery is None or delivery.user_id != UUID(current_user.user_id):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Delivery not found"
        )
    return _delivery_response(delivery)


@router.post("/create-stripe-session", response_model=CreateStripeSessionResponse)
async def create_stripe_session(
    request: CreateStripeSessionRequest,
    db: AsyncSession = Depends(get_db),
) -> CreateStripeSessionResponse:
    """Ouvre une session Stripe Checkout à prix libre depuis la page `/soutenir`.

    Non authentifié (appelé du web). L'identité vient soit du `token` signé
    (parcours app -> email -> web), soit de l'`email` (visiteur anonyme
    passwordless). Le montant est borné côté serveur par `stripe_service`.
    """
    if request.token:
        try:
            claims = verify_checkout_token(request.token)
        except CheckoutTokenError as exc:
            logger.warning("checkout.stripe_session_invalid_token", error=str(exc))
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid or expired link",
            ) from exc
        user_id = claims["user_id"]
        email = claims["email"]
        via = "token"
    elif request.email:
        existing_id = await _supabase_admin_lookup_user_by_email(request.email)
        user_id = existing_id or await _supabase_admin_create_user(request.email)
        email = request.email
        via = "email"
    else:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="token or email is required",
        )

    service = SubscriptionService(db)
    await service._get_or_create_subscription(user_id)
    await db.commit()

    url = await create_support_subscription_session(
        user_id, email, request.amount_cents, message=request.message
    )

    get_posthog_client().capture(
        user_id=user_id,
        event="support_session_created",
        properties={
            "amount_cents": request.amount_cents,
            "via": via,
            "has_message": bool(request.message and request.message.strip()),
        },
    )
    logger.info(
        "checkout.create_stripe_session",
        user_id=user_id,
        amount_cents=request.amount_cents,
        via=via,
    )
    return CreateStripeSessionResponse(url=url)


@router.get("/support-messages", response_model=list[SupporterMessagePublic])
async def support_messages(
    db: AsyncSession = Depends(get_db),
) -> list[SupporterMessagePublic]:
    """Mur public des mots de soutien : uniquement les messages **modérés**.

    Non authentifié (lecture publique). Ne renvoie que `published = true` : un
    mot reste invisible tant qu'un humain ne l'a pas validé.
    """
    result = await db.execute(
        select(SupporterMessage)
        .where(SupporterMessage.published.is_(True))
        .order_by(SupporterMessage.created_at.desc())
        .limit(100)
    )
    return [
        SupporterMessagePublic(
            message=row.message,
            display_name=row.display_name,
            created_at=row.created_at,
        )
        for row in result.scalars().all()
    ]
