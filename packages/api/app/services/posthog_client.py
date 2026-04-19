"""Client PostHog pour analytics produit (rétention, cohortes, funnels).

Story 14.1 — Dual-track avec analytics_events (qui reste pour digest-metrics).
Les appels PostHog sont fire-and-forget, jamais bloquants pour l'utilisateur.
"""

from __future__ import annotations

from functools import lru_cache
from typing import Any
from uuid import UUID

import structlog
from posthog import Posthog

from app.config import get_settings

logger = structlog.get_logger()


class PostHogClient:
    """Wrapper autour du SDK Posthog avec kill-switch et logging."""

    def __init__(
        self,
        api_key: str,
        host: str,
        enabled: bool,
    ) -> None:
        self.enabled = enabled and bool(api_key)
        self._client: Posthog | None = None
        if self.enabled:
            self._client = Posthog(
                project_api_key=api_key,
                host=host,
                # Disable GeoIP server-side — we rely on app-level properties.
                disable_geoip=True,
            )

    def capture(
        self,
        user_id: UUID | str,
        event: str,
        properties: dict[str, Any] | None = None,
    ) -> None:
        """Envoie un event à PostHog. Silencieux si désactivé ou en échec."""
        if not self.enabled or self._client is None:
            return
        try:
            self._client.capture(
                distinct_id=str(user_id),
                event=event,
                properties=properties or {},
            )
        except Exception as exc:
            logger.warning(
                "posthog.capture_failed",
                posthog_event=event,
                user_id=str(user_id),
                error=str(exc),
            )

    def identify(
        self,
        user_id: UUID | str,
        properties: dict[str, Any] | None = None,
    ) -> None:
        """Met à jour les user properties sur PostHog. Silencieux si KO."""
        if not self.enabled or self._client is None:
            return
        try:
            self._client.identify(
                distinct_id=str(user_id),
                properties=properties or {},
            )
        except Exception as exc:
            logger.warning(
                "posthog.identify_failed",
                user_id=str(user_id),
                error=str(exc),
            )

    def shutdown(self) -> None:
        """Flush les events avant arrêt du process (appelé au shutdown FastAPI)."""
        if self._client is not None:
            try:
                self._client.shutdown()
            except Exception as exc:
                logger.warning("posthog.shutdown_failed", error=str(exc))


@lru_cache
def get_posthog_client() -> PostHogClient:
    """Singleton PostHogClient initialisé depuis les settings."""
    settings = get_settings()
    return PostHogClient(
        api_key=settings.posthog_api_key,
        host=settings.posthog_host,
        enabled=settings.posthog_enabled,
    )


def _parse_email_list(raw: str) -> set[str]:
    """Parse une liste d'emails séparés par virgule, normalisée en minuscules."""
    return {email.strip().lower() for email in raw.split(",") if email.strip()}


def derive_cohort_properties(email: str | None) -> dict[str, Any]:
    """Calcule les user properties de cohorte à partir de l'email utilisateur.

    Les listes sont lues depuis la config (POSTHOG_CREATOR_EMAILS,
    POSTHOG_CLOSE_CIRCLE_EMAILS) pour éviter de committer des PII.
    """
    if not email:
        return {
            "is_creator_ytbeur": False,
            "is_close_to_laurin": False,
        }
    settings = get_settings()
    creators = _parse_email_list(settings.posthog_creator_emails)
    close_circle = _parse_email_list(settings.posthog_close_circle_emails)
    normalized = email.strip().lower()
    return {
        "is_creator_ytbeur": normalized in creators,
        "is_close_to_laurin": normalized in close_circle,
    }
