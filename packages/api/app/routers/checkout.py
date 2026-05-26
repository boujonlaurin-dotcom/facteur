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

from urllib.parse import urlencode

import certifi
import httpx
import sentry_sdk
import structlog
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.database import get_db
from app.schemas.checkout import CheckoutStartRequest, CheckoutStartResponse
from app.services.posthog_client import get_posthog_client
from app.services.subscription_service import SubscriptionService

router = APIRouter()
logger = structlog.get_logger()

# RevenueCat Web Billing URLs configurées dans le dashboard RC. La V1 utilise
# des URLs hostées par RevenueCat (mode "Paywall Link") — pas besoin de Stripe.js
# côté landing. Format attendu : `<base>?app_user_id=<user_id>`. Le base diffère
# selon l'offering pour aiguiller `default` vs `founder` (offerings RC distincts).
DEFAULT_WEB_BILLING_BASE_URL = "https://pay.rev.cat/facteur-premium"
FOUNDER_WEB_BILLING_BASE_URL = "https://pay.rev.cat/facteur-founder"


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
