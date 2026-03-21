"""Schemas contenu."""

import json
from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field, field_serializer

from app.models.enums import (
    BiasOrigin,
    BiasStance,
    ContentStatus,
    ContentType,
    HiddenReason,
    ReliabilityScore,
)


def parse_entity_strings(raw_entities: list[str] | None) -> list[dict]:
    """Parse JSON-encoded entity strings to {text, label} dicts for mobile."""
    if not raw_entities:
        return []
    result = []
    for raw in raw_entities:
        try:
            parsed = json.loads(raw)
            result.append({"text": parsed.get("name", raw), "label": parsed.get("type", "")})
        except (json.JSONDecodeError, AttributeError):
            result.append({"text": raw, "label": ""})
    return result


class HideContentRequest(BaseModel):
    """Requête pour masquer un contenu. Reason optionnel (swipe-left sans précision)."""

    reason: HiddenReason | None = None


class NoteUpsertRequest(BaseModel):
    """Requête pour créer/mettre à jour une note sur un article."""

    note_text: str = Field(..., min_length=1, max_length=1000)


class NoteResponse(BaseModel):
    """Réponse après upsert/delete d'une note."""

    note_text: str | None = None
    note_updated_at: datetime | None = None
    is_saved: bool = False


class SourceMini(BaseModel):
    """Source minifiée pour les cards."""

    id: UUID
    name: str
    logo_url: str | None
    type: str  # Ajout pour éviter le crash mobile
    theme: str | None  # Ajout pour l'UI mobile
    bias_stance: BiasStance = BiasStance.UNKNOWN
    reliability_score: ReliabilityScore = ReliabilityScore.UNKNOWN
    bias_origin: BiasOrigin = BiasOrigin.UNKNOWN

    class Config:
        from_attributes = True


class ScoreContribution(BaseModel):
    """Contribution d'un facteur au score de recommandation."""

    label: str  # ex: "Thème : Tech"
    points: float  # ex: 70
    is_positive: bool = True
    pillar: str | None = (
        None  # "pertinence" | "source" | "fraicheur" | "qualite" | "penalite"
    )


class RecommendationReason(BaseModel):
    """Raison de la recommandation avec breakdown détaillé."""

    label: str  # ex: "Pour toi" (top reason)
    score_total: float = 0.0  # Total des points
    breakdown: list[ScoreContribution] = []  # Détail par facteur


class ContentResponse(BaseModel):
    """Réponse contenu (card dans le feed)."""

    id: UUID
    title: str
    url: str
    thumbnail_url: str | None
    content_type: ContentType
    duration_seconds: int | None
    published_at: datetime
    source: SourceMini
    status: ContentStatus = ContentStatus.UNSEEN
    is_saved: bool = False
    is_liked: bool = False
    is_hidden: bool = False
    hidden_reason: str | None = None
    description: str | None = None
    topics: list[str] | None = (
        None  # Topics ML granulaires (slugs), NULL si non classifié
    )
    entities: list[str] | None = None  # Named entities (NER)
    is_paid: bool = False  # Paywall detection
    content_quality: str | None = None  # In-App Reading: 'full', 'partial', 'none'
    recommendation_reason: RecommendationReason | None = None
    reading_progress: int = 0
    note_text: str | None = None
    note_updated_at: datetime | None = None

    @field_serializer("topics", when_used="always")
    def serialize_topics(self, value: list[str] | None) -> list[str]:
        """ORM topics peut être NULL en base → toujours retourner une liste lors de la sérialisation."""
        return value if value is not None else []

    @field_serializer("entities", when_used="always")
    def serialize_entities(self, value: list[str] | None) -> list[dict]:
        return parse_entity_strings(value)

    class Config:
        from_attributes = True


class ContentDetailResponse(BaseModel):
    """Réponse détail contenu."""

    id: UUID
    title: str
    url: str
    thumbnail_url: str | None
    description: str | None
    html_content: str | None = None  # Story 5.2: In-App Reading Mode
    audio_url: str | None = None  # Story 5.2: In-App Reading Mode
    content_quality: str | None = None  # In-App Reading: 'full', 'partial', 'none'
    extraction_attempted_at: datetime | None = None
    content_type: ContentType
    duration_seconds: int | None
    published_at: datetime
    source: SourceMini
    status: ContentStatus
    is_saved: bool = False
    is_liked: bool = False
    is_hidden: bool = False
    hidden_reason: str | None = None
    topics: list[str] | None = None
    entities: list[str] | None = None
    theme: str | None = None
    time_spent_seconds: int = 0
    reading_progress: int = 0
    note_text: str | None = None
    note_updated_at: datetime | None = None

    @field_serializer("topics", when_used="always")
    def serialize_topics(self, value: list[str] | None) -> list[str]:
        return value if value is not None else []

    @field_serializer("entities", when_used="always")
    def serialize_entities(self, value: list[str] | None) -> list[dict]:
        return parse_entity_strings(value)

    class Config:
        from_attributes = True


class ContentStatusUpdate(BaseModel):
    """Mise à jour du statut d'un contenu."""

    status: ContentStatus | None = None
    time_spent_seconds: int | None = None
    reading_progress: int | None = Field(None, ge=0, le=100)


class DailyTop3Response(BaseModel):
    """Item du Daily Briefing (Top 3)."""

    rank: int
    reason: str  # "À la Une", "Sujet tendance", "Source suivie"
    consumed: bool
    content: ContentResponse

    class Config:
        from_attributes = True


class FeedRefreshRequest(BaseModel):
    """Requête pour rafraîchir le feed (marquer les articles visibles comme 'déjà affiché')."""

    content_ids: list[UUID] = Field(..., max_length=200)


class FeedResponse(BaseModel):
    """Réponse globale du feed."""

    briefing: list[
        DailyTop3Response
    ] = []  # Le Top 3 du jour (vide si on n'est pas "today" ou déjà vu?)
    items: list[ContentResponse]  # Le flux infini
