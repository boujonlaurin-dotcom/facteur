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
    CONTENT_TYPE = "content_type"


class BiasStance(str, Enum):
    """Positionnement éditorial (biais) d'une source."""

    LEFT = "left"
    CENTER_LEFT = "center-left"
    CENTER = "center"
    CENTER_RIGHT = "center-right"
    RIGHT = "right"
    ALTERNATIVE = "alternative"
    SPECIALIZED = "specialized"
    UNKNOWN = "unknown"


class ReliabilityScore(str, Enum):
    """Score de fiabilité d'une source."""

    LOW = "low"
    MEDIUM = "medium"
    MIXED = "mixed"
    HIGH = "high"
    UNKNOWN = "unknown"



class BiasOrigin(str, Enum):
    """Origine de l'information de biais."""

    EXTERNAL_DB = "external-db"
    CURATED = "curated"
    LLM = "llm"
    UNKNOWN = "unknown"


class FeedFilterMode(str, Enum):
    """Mode de filtrage du feed (Intent-based)."""

    INSPIRATION = "inspiration"
    PERSPECTIVES = "perspectives"
    DEEP_DIVE = "deep_dive"


class DigestMode(str, Enum):
    """Mode de personnalisation du digest quotidien (Epic 11)."""

    POUR_VOUS = "pour_vous"
    SEREIN = "serein"
    PERSPECTIVE = "perspective"
    THEME_FOCUS = "theme_focus"

