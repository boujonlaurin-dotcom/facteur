"""Enums for Facteur data models.

These enums are shared between SQLAlchemy models and Pydantic schemas.
They map to PostgreSQL ENUM types in the database.
"""

from enum import Enum


class SourceType(str, Enum):
    """Type de source de contenu."""

    ARTICLE = "article"
    PODCAST = "podcast"
    YOUTUBE = "youtube"


class ContentType(str, Enum):
    """Type de contenu individuel."""

    ARTICLE = "article"
    PODCAST = "podcast"
    YOUTUBE = "youtube"


class ContentStatus(str, Enum):
    """Statut d'un contenu pour un utilisateur."""

    UNSEEN = "unseen"
    SEEN = "seen"
    CONSUMED = "consumed"


class HiddenReason(str, Enum):
    """Raison pour laquelle un contenu est masqué."""

    SOURCE = "source"
    TOPIC = "topic"
