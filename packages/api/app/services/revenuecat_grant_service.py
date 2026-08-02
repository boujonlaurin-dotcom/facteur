"""Grant / revoke de l'entitlement Premium « promotionnel » RevenueCat (REST v1).

Le miroir Stripe pose (`grant_premium`) ou retire (`revoke_premium`) l'entitlement
`premium` côté RevenueCat ; le SDK mobile le lit ensuite -> zéro changement du
gating (`isPremiumProvider`).

Exige une clé API **secrète v1** (`revenuecat_rest_api_key`), distincte de la clé
SDK publique (`revenuecat_api_key`) : une clé publique renvoie 401 sur
`/promotional`.
"""

import certifi
import httpx
import structlog

from app.config import get_settings

logger = structlog.get_logger()

_BASE_URL = "https://api.revenuecat.com/v1"
# Le bundle CA ne change pas d'un appel à l'autre : le résoudre une fois à
# l'import évite de reconstruire le contexte TLS à chaque grant/revoke.
_CA_BUNDLE = certifi.where()


class RevenueCatGrantError(Exception):
    """Échec d'un appel grant/revoke RevenueCat (config absente ou HTTP non-2xx)."""


class RevenueCatGrantService:
    """Client mince pour les entitlements promotionnels RevenueCat."""

    def __init__(self) -> None:
        settings = get_settings()
        self._api_key = settings.revenuecat_rest_api_key
        self._entitlement = settings.revenuecat_entitlement_id

    @property
    def is_configured(self) -> bool:
        return bool(self._api_key)

    def _headers(self) -> dict[str, str]:
        return {
            "Authorization": f"Bearer {self._api_key}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        }

    async def _post(
        self, action: str, url: str, app_user_id: str, json: dict | None = None
    ) -> None:
        """POST commun grant/revoke : garde config + client + gestion du statut.

        `action` sert de clé de log (`grant`/`revoke`) ; `json=None` = pas de body
        (cas revoke).
        """
        if not self.is_configured:
            logger.warning("revenuecat_grant.not_configured", action=action)
            raise RevenueCatGrantError("revenuecat_rest_api_key not configured")

        async with httpx.AsyncClient(verify=_CA_BUNDLE, timeout=10.0) as client:
            resp = await client.post(url, headers=self._headers(), json=json)
        if resp.status_code not in (200, 201):
            logger.warning(
                f"revenuecat_grant.{action}_failed",
                status=resp.status_code,
                body=resp.text[:500],
                app_user_id=app_user_id,
            )
            raise RevenueCatGrantError(f"{action} failed: HTTP {resp.status_code}")

    async def grant_premium(self, app_user_id: str, end_time_ms: int) -> None:
        """Accorde/étend l'entitlement promotionnel jusqu'à `end_time_ms`.

        Re-appeler avec un `end_time_ms` plus tardif étend la validité : c'est ce
        qui gère le renouvellement (re-grant à chaque `invoice.paid`).
        """
        url = (
            f"{_BASE_URL}/subscribers/{app_user_id}"
            f"/entitlements/{self._entitlement}/promotional"
        )
        await self._post("grant", url, app_user_id, json={"end_time_ms": end_time_ms})
        logger.info(
            "revenuecat_grant.granted",
            app_user_id=app_user_id,
            end_time_ms=end_time_ms,
        )

    async def revoke_premium(self, app_user_id: str) -> None:
        """Retire l'entitlement promotionnel (idempotent côté RevenueCat)."""
        url = (
            f"{_BASE_URL}/subscribers/{app_user_id}"
            f"/entitlements/{self._entitlement}/revoke_promotionals"
        )
        await self._post("revoke", url, app_user_id)
        logger.info("revenuecat_grant.revoked", app_user_id=app_user_id)
