"""Token signé (HS256) pour le lien de checkout app -> web « soutien ».

Porté dans le magic link Supabase (`redirect_to=/soutenir?t=<token>`) puis relu
par `POST /api/checkout/create-stripe-session`. On NE réutilise PAS
`supabase_jwt_secret` : l'auth réelle de l'app est ES256/JWKS, ce token est un
canal séparé signé avec `checkout_link_secret`.

Le token ne contient rien de secret (user_id + email) et ne débloque pas Premium
par lui-même : il autorise seulement l'ouverture d'une session Stripe Checkout
que l'utilisateur doit finaliser avec sa carte. Le montant, lui, est borné
serveur.
"""

from datetime import UTC, datetime, timedelta

from jose import JWTError, jwt

from app.config import get_settings

_ALGORITHM = "HS256"
_AUDIENCE = "soutenir"
# Le token est embarqué dans un email : il doit survivre au délai d'ouverture de
# la boîte mail. On l'aligne (large) sur la durée de vie du magic link Supabase.
_DEFAULT_TTL_MINUTES = 24 * 60


class CheckoutTokenError(Exception):
    """Token de checkout absent, invalide ou expiré."""


def mint_checkout_token(
    user_id: str, email: str, ttl_minutes: int | None = None
) -> str:
    """Signe un token portant `user_id`/`email` pour le parcours soutien."""
    settings = get_settings()
    if not settings.checkout_link_secret:
        raise CheckoutTokenError("checkout_link_secret not configured")

    now = datetime.now(UTC)
    ttl = ttl_minutes if ttl_minutes is not None else _DEFAULT_TTL_MINUTES
    claims = {
        "sub": user_id,
        "email": email,
        "aud": _AUDIENCE,
        "iat": int(now.timestamp()),
        "exp": int((now + timedelta(minutes=ttl)).timestamp()),
    }
    return jwt.encode(claims, settings.checkout_link_secret, algorithm=_ALGORITHM)


def verify_checkout_token(token: str) -> dict[str, str]:
    """Vérifie signature/exp/aud et renvoie `{user_id, email}`.

    Lève `CheckoutTokenError` sur token expiré, mauvaise audience, signature
    invalide ou claims manquants.
    """
    settings = get_settings()
    if not settings.checkout_link_secret:
        raise CheckoutTokenError("checkout_link_secret not configured")

    try:
        payload = jwt.decode(
            token,
            settings.checkout_link_secret,
            algorithms=[_ALGORITHM],
            audience=_AUDIENCE,
        )
    except JWTError as exc:
        raise CheckoutTokenError(f"invalid token: {exc}") from exc

    user_id = payload.get("sub")
    email = payload.get("email")
    if not user_id or not email:
        raise CheckoutTokenError("missing claims")
    return {"user_id": user_id, "email": email}
