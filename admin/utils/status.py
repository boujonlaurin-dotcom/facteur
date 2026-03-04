"""Logique de calcul de statut pour sources et utilisateurs."""

from datetime import datetime, timezone

from admin.utils.config import (
    SOURCE_DEFAULT_INTERVAL_HOURS,
    SOURCE_STALE_MULTIPLIER_CRITICAL,
    SOURCE_STALE_MULTIPLIER_WARNING,
    USER_ACTIVE_HOURS,
    USER_SLOWING_DAYS,
)


def compute_source_status(
    last_article_at: datetime | None,
    avg_interval_hours: float | None,
) -> str:
    """Calcule le statut d'une source.

    Returns: "OK" / "Retard" / "KO"
    """
    if last_article_at is None:
        return "KO"

    now = datetime.now(timezone.utc)
    if last_article_at.tzinfo is None:
        delta_hours = (now.replace(tzinfo=None) - last_article_at).total_seconds() / 3600
    else:
        delta_hours = (now - last_article_at).total_seconds() / 3600

    interval = avg_interval_hours if avg_interval_hours and avg_interval_hours > 0 else SOURCE_DEFAULT_INTERVAL_HOURS

    if delta_hours <= interval * SOURCE_STALE_MULTIPLIER_WARNING:
        return "OK"
    elif delta_hours <= interval * SOURCE_STALE_MULTIPLIER_CRITICAL:
        return "Retard"
    else:
        return "KO"


def source_status_emoji(status: str) -> str:
    """Convertit un statut en emoji."""
    return {"OK": "\u2705", "Retard": "\u26a0\ufe0f", "KO": "\u274c"}.get(status, "\u2753")


def compute_user_badge(last_activity_at: datetime | None) -> str:
    """Calcule le badge d'activité utilisateur.

    Returns: "Actif" / "Ralenti" / "Inactif"
    """
    if last_activity_at is None:
        return "Inactif"

    now = datetime.now(timezone.utc)
    if last_activity_at.tzinfo is None:
        delta_hours = (now.replace(tzinfo=None) - last_activity_at).total_seconds() / 3600
    else:
        delta_hours = (now - last_activity_at).total_seconds() / 3600

    if delta_hours < USER_ACTIVE_HOURS:
        return "Actif"
    elif delta_hours < USER_SLOWING_DAYS * 24:
        return "Ralenti"
    else:
        return "Inactif"


def user_badge_emoji(badge: str) -> str:
    """Convertit un badge en emoji."""
    return {"Actif": "\U0001f7e2", "Ralenti": "\U0001f7e1", "Inactif": "\U0001f534"}.get(badge, "\u2753")
