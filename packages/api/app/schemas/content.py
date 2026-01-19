"""Schemas contenu."""

from datetime import datetime
from typing import Optional
from uuid import UUID

from pydantic import BaseModel

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


class RecommendationReason(BaseModel):
    """Raison de la recommandation."""
    label: str  # ex: "Pour toi", "Incontournable", "Analyse de fond"
    confidence: float # 0.0 à 1.0

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
    is_hidden: bool = False
    hidden_reason: Optional[str] = None
    description: Optional[str] = None
    recommendation_reason: Optional[RecommendationReason] = None

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
    is_hidden: bool = False
    hidden_reason: Optional[str] = None
    time_spent_seconds: int = 0

    class Config:
        from_attributes = True


class ContentStatusUpdate(BaseModel):
    """Mise à jour du statut d'un contenu."""

    status: Optional[ContentStatus] = None
    time_spent_seconds: Optional[int] = None

