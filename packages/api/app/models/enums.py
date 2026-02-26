"""Enums for Facteur data models.

These enums are shared between SQLAlchemy models and Pydantic schemas.
They map to PostgreSQL ENUM types in the database.
"""

from enum import StrEnum


class SourceType(StrEnum):
    """Type de source de contenu."""

    ARTICLE = "article"
    PODCAST = "podcast"
    YOUTUBE = "youtube"


class ContentType(StrEnum):
    """Type de contenu individuel."""

    ARTICLE = "article"
    PODCAST = "podcast"
    YOUTUBE = "youtube"


class ContentStatus(StrEnum):
    """Statut d'un contenu pour un utilisateur."""

    UNSEEN = "unseen"
    SEEN = "seen"
    CONSUMED = "consumed"


class HiddenReason(StrEnum):
    """Raison pour laquelle un contenu est masqué."""

    SOURCE = "source"
    TOPIC = "topic"
    CONTENT_TYPE = "content_type"


class BiasStance(StrEnum):
    """Positionnement éditorial (biais) d'une source."""

    LEFT = "left"
    CENTER_LEFT = "center-left"
    CENTER = "center"
    CENTER_RIGHT = "center-right"
    RIGHT = "right"
    ALTERNATIVE = "alternative"
    SPECIALIZED = "specialized"
    UNKNOWN = "unknown"


class ReliabilityScore(StrEnum):
    """Score de fiabilité d'une source."""

    LOW = "low"
    MEDIUM = "medium"
    MIXED = "mixed"
    HIGH = "high"
    UNKNOWN = "unknown"


class BiasOrigin(StrEnum):
    """Origine de l'information de biais."""

    EXTERNAL_DB = "external-db"
    CURATED = "curated"
    LLM = "llm"
    UNKNOWN = "unknown"


class FeedFilterMode(StrEnum):
    """Mode de filtrage du feed (Intent-based)."""

    RECENT = "recent"
    INSPIRATION = "inspiration"
    PERSPECTIVES = "perspectives"
    DEEP_DIVE = "deep_dive"


class DigestMode(StrEnum):
    """Mode de personnalisation du digest quotidien (Epic 11)."""

    POUR_VOUS = "pour_vous"
    SEREIN = "serein"
    PERSPECTIVE = "perspective"
    THEME_FOCUS = "theme_focus"
