"""Schémas des alertes « source rare » (Epic 30, story 30.2)."""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel


class UpdateSourceAlertRequest(BaseModel):
    enabled: bool


class SourceAlertToggleResponse(BaseModel):
    """Réponse du toggle : l'état posé + le compteur pour l'en-tête « x / 5 »."""

    enabled: bool
    active_count: int
    cap: int


class AlertItem(BaseModel):
    """Une cloche active, telle que rendue par l'écran « Mes alertes ».

    `last_published_at` porte le « silence comme preuve » : c'est lui qui
    permet d'écrire « Rien de neuf depuis N semaines, et c'est vérifié ».
    """

    source_id: UUID
    source_name: str
    source_logo_url: str | None = None
    articles_30d: int = 0
    last_published_at: datetime | None = None
    last_alert_sent_at: datetime | None = None
    new_content: int = 0


class AlertsResponse(BaseModel):
    cap: int
    active_count: int
    items: list[AlertItem] = []
