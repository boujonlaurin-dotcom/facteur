"""Schemas Pydantic pour les événements analytics unifiés.

Schema unifié suivant les patterns GAFAM (YouTube, Meta, Spotify):
- Un seul type d'événement `content_interaction` pour toutes les interactions contenu
- Le champ `surface` distingue le contexte (feed vs digest)
- Forward-compatible avec atomic_themes (Camembert)
- Session-level events restent surface-specific (digest_session, feed_session)
"""

from enum import Enum

from pydantic import BaseModel, Field
from uuid import UUID


class InteractionAction(str, Enum):
    """Actions possibles sur un contenu."""
    READ = "read"
    SAVE = "save"
    DISMISS = "dismiss"
    PASS = "pass"


class InteractionSurface(str, Enum):
    """Surface d'interaction."""
    FEED = "feed"
    DIGEST = "digest"


class ContentInteractionPayload(BaseModel):
    """Payload pour un événement content_interaction.

    Schema unifié suivant les patterns GAFAM:
    - Un seul type d'événement pour toutes les interactions contenu
    - Le champ 'surface' distingue le contexte
    - Forward-compatible avec atomic_themes (Camembert)
    """
    action: InteractionAction
    surface: InteractionSurface
    content_id: UUID
    source_id: UUID
    topics: list[str] = Field(default_factory=list)
    atomic_themes: list[str] | None = None  # Forward-compatible for Camembert
    position: int | None = None  # 1-5 for digest, rank for feed
    time_spent_seconds: int = 0
    session_id: str | None = None

    class Config:
        from_attributes = True


class DigestSessionPayload(BaseModel):
    """Payload pour un événement digest_session."""
    session_id: str
    digest_date: str
    articles_read: int = 0
    articles_saved: int = 0
    articles_dismissed: int = 0
    articles_passed: int = 0
    total_time_seconds: int = 0
    closure_achieved: bool = False
    streak: int = 0


class FeedSessionPayload(BaseModel):
    """Payload pour un événement feed_session."""
    session_id: str
    scroll_depth_percent: float = 0.0
    items_viewed: int = 0
    items_interacted: int = 0
    total_time_seconds: int = 0
