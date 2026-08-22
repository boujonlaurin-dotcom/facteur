"""Service Stripe — parcours « Soutien à prix libre » (env-gated).

Env-gated : lève 503 tant que `stripe_secret_key` (ou `stripe_webhook_secret`
pour la vérif webhook) est vide. Le SDK Stripe est synchrone/bloquant : les
appels réseau sont déportés en threadpool pour ne pas figer l'event loop.

Client instancié (`stripe.StripeClient`) plutôt que le pattern global déprécié
`stripe.api_key = ...` : une mutation globale serait partagée entre requêtes
concurrentes (event loop unique, threadpool partagé) et pourrait faire fuiter
la clé d'une requête vers une autre en cas de reconfiguration à chaud.

Sécurité : seul `amount_cents` vient de l'utilisateur (borné min/max serveur) ;
la devise et le produit sont fixés côté serveur (pas de SSRF). Le
`custom_unit_amount` de Stripe ne marche PAS en mode subscription -> le montant
validé est passé en `unit_amount` FIXE dans un `price_data` récurrent inline.
"""

import hashlib
from datetime import UTC, datetime

import stripe
import structlog
from fastapi import HTTPException, status
from starlette.concurrency import run_in_threadpool

from app.config import get_settings
from app.schemas.checkout import SUPPORT_MESSAGE_MAX_LEN

logger = structlog.get_logger()

# Fenêtre de dédup de la clé d'idempotence Stripe : un double-clic ou un retry
# réseau à quelques secondes d'intervalle réutilise la même clé (Stripe renvoie
# alors la session déjà créée au lieu d'en créer une deuxième) ; passé ce délai,
# une nouvelle tentative repart sur une nouvelle clé (l'utilisateur peut
# légitimement vouloir soutenir une deuxième fois).
_IDEMPOTENCY_WINDOW_SECONDS = 300


def _get_stripe_client() -> stripe.StripeClient:
    """Instancie un client Stripe scopé à cet appel. Lève 503 si non configuré."""
    settings = get_settings()
    if not settings.stripe_secret_key:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Stripe not configured",
        )
    return stripe.StripeClient(settings.stripe_secret_key)


def _support_session_idempotency_key(
    user_id: str, amount_cents: int, message: str
) -> str:
    """Dérive une clé stable par fenêtre de 5 min (anti double-clic/retry).

    Volontairement PAS un uuid4 aléatoire : une clé générée à chaque appel ne
    protège jamais rien, puisque deux appels identiques obtiendraient toujours
    des clés différentes (Stripe ne peut alors jamais détecter le doublon).
    """
    bucket = int(datetime.now(UTC).timestamp() // _IDEMPOTENCY_WINDOW_SECONDS)
    raw = f"support-session:{user_id}:{amount_cents}:{message}:{bucket}"
    return hashlib.sha256(raw.encode()).hexdigest()


async def create_support_subscription_session(
    user_id: str, email: str, amount_cents: int, message: str | None = None
) -> str:
    """Crée une session Stripe Checkout d'abonnement à prix libre.

    Renvoie l'URL hébergée Stripe. Lève 400 si le montant est hors bornes,
    503 si Stripe n'est pas configuré. Le `message` optionnel est transporté en
    metadata de session pour être persisté au webhook (mur des soutiens).
    """
    settings = get_settings()
    client = _get_stripe_client()

    if (
        amount_cents < settings.stripe_support_min_cents
        or amount_cents > settings.stripe_support_max_cents
    ):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                f"amount_cents must be between {settings.stripe_support_min_cents} "
                f"and {settings.stripe_support_max_cents}"
            ),
        )

    session_metadata = {"user_id": user_id}
    clean_message = (message or "").strip()[:SUPPORT_MESSAGE_MAX_LEN]
    if clean_message:
        session_metadata["support_message"] = clean_message

    idempotency_key = _support_session_idempotency_key(
        user_id, amount_cents, clean_message
    )

    session = await run_in_threadpool(
        client.checkout.sessions.create,
        params={
            "mode": "subscription",
            "client_reference_id": user_id,
            "customer_email": email,
            "line_items": [
                {
                    "price_data": {
                        "currency": settings.stripe_currency,
                        "product": settings.stripe_support_product_id,
                        "unit_amount": amount_cents,
                        "recurring": {"interval": "month"},
                    },
                    "quantity": 1,
                }
            ],
            "subscription_data": {
                "metadata": {
                    "user_id": user_id,
                    "support_amount_cents": str(amount_cents),
                }
            },
            "metadata": session_metadata,
            "success_url": (
                f"{settings.public_web_base_url}/soutenir-merci"
                "?session_id={CHECKOUT_SESSION_ID}"
            ),
            "cancel_url": f"{settings.public_web_base_url}/soutenir",
        },
        options={"idempotency_key": idempotency_key},
    )

    logger.info(
        "stripe.support_session_created",
        user_id=user_id,
        amount_cents=amount_cents,
    )
    return session.url


def construct_event(payload: bytes, sig_header: str | None) -> stripe.Event:
    """Vérifie la signature du webhook (HMAC + tolérance timestamp = anti-replay).

    Lève 503 si non configuré, 401 si la signature/le payload est invalide.
    """
    settings = get_settings()
    if not settings.stripe_webhook_secret:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Stripe webhook not configured",
        )
    # La vérif de signature est locale (HMAC) : pas besoin d'une clé secrète
    # valide ici, seul `stripe_webhook_secret` (gate ci-dessus) compte.
    client = stripe.StripeClient(settings.stripe_secret_key or "unused")
    try:
        return client.construct_event(
            payload, sig_header or "", settings.stripe_webhook_secret
        )
    except (ValueError, stripe.error.SignatureVerificationError) as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid Stripe signature",
        ) from exc
