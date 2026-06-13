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
    REDDIT = "reddit"


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

    RECENT = "recent"  # Deprecated: chrono pur sans diversification
    CHRONOLOGICAL = "chronological"  # Epic 12: chrono diversifié (nouveau défaut)
    INSPIRATION = "inspiration"
    PERSPECTIVES = "perspectives"
    DEEP_DIVE = "deep_dive"


class InterestState(StrEnum):
    """État sémantique d'un intérêt (Thème, Sujet ou Source) — Story 22.1.

    Axe unique partagé par `user_interests`, `user_topic_profiles`, `user_sources`.
    `weight` / `priority_multiplier` restent des signaux appris/quantitatifs ;
    `state` est le signal déclaré par l'utilisateur.
    """

    HIDDEN = "hidden"
    UNFOLLOWED = "unfollowed"
    FOLLOWED = "followed"
    FAVORITE = "favorite"
