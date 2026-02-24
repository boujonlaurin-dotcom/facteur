"""Schemas contenu."""

from datetime import datetime
from typing import Optional
from uuid import UUID

from pydantic import BaseModel, field_serializer

from app.models.enums import BiasOrigin, BiasStance, ContentStatus, ContentType, HiddenReason, ReliabilityScore


class HideContentRequest(BaseModel):
    """Requête pour masquer un contenu."""

    reason: HiddenReason


class SourceMini(BaseModel):
    """Source minifiée pour les cards."""

    id: UUID
    name: str
    logo_url: Optional[str]
    type: str  # Ajout pour éviter le crash mobile
    theme: Optional[str] # Ajout pour l'UI mobile
    bias_stance: BiasStance = BiasStance.UNKNOWN
    reliability_score: ReliabilityScore = ReliabilityScore.UNKNOWN
    bias_origin: BiasOrigin = BiasOrigin.UNKNOWN

    class Config:
        from_attributes = True


class ScoreContribution(BaseModel):
    """Contribution d'un facteur au score de recommandation."""
    label: str       # ex: "Thème : Tech"
    points: float    # ex: 70
    is_positive: bool = True


class RecommendationReason(BaseModel):
    """Raison de la recommandation avec breakdown détaillé."""
    label: str                              # ex: "Pour toi" (top reason)
    score_total: float = 0.0                # Total des points
    breakdown: list[ScoreContribution] = [] # Détail par facteur

class ContentResponse(BaseModel):
    """Réponse contenu (card dans le feed)."""

    id: UUID
    title: str
    url: str
    thumbnail_url: Optional[str]
    content_type: ContentType
    duration_seconds: Optional[int]
    published_at: datetime
    source: SourceMini
    status: ContentStatus = ContentStatus.UNSEEN
    is_saved: bool = False
    is_liked: bool = False
    is_hidden: bool = False
    hidden_reason: Optional[str] = None
    description: Optional[str] = None
    topics: list[str] | None = None  # Topics ML granulaires (slugs), NULL si non classifié
    is_paid: bool = False  # Paywall detection
    recommendation_reason: Optional[RecommendationReason] = None

    @field_serializer('topics', when_used='always')
    def serialize_topics(self, value: list[str] | None) -> list[str]:
        """ORM topics peut être NULL en base → toujours retourner une liste lors de la sérialisation."""
        return value if value is not None else []

    class Config:
        from_attributes = True


class ContentDetailResponse(BaseModel):
    """Réponse détail contenu."""

    id: UUID
    title: str
    url: str
    thumbnail_url: Optional[str]
    description: Optional[str]
    html_content: Optional[str] = None  # Story 5.2: In-App Reading Mode
    audio_url: Optional[str] = None     # Story 5.2: In-App Reading Mode
    content_type: ContentType
    duration_seconds: Optional[int]
    published_at: datetime
    source: SourceMini
    status: ContentStatus
    is_saved: bool = False
    is_liked: bool = False
    is_hidden: bool = False
    hidden_reason: Optional[str] = None
    time_spent_seconds: int = 0

    class Config:
        from_attributes = True


class ContentStatusUpdate(BaseModel):
    """Mise à jour du statut d'un contenu."""

    status: Optional[ContentStatus] = None
    time_spent_seconds: Optional[int] = None

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

    content_ids: list[UUID]


class FeedResponse(BaseModel):
    """Réponse globale du feed."""

    briefing: list[DailyTop3Response] = []  # Le Top 3 du jour (vide si on n'est pas "today" ou déjà vu?)
    items: list[ContentResponse]            # Le flux infini
