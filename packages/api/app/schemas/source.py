"""Schemas source."""

from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field, field_validator

from app.models.enums import SourceType

ContentTypeFilter = Literal["article", "youtube", "reddit", "podcast"]


class SourceResponse(BaseModel):
    """Réponse source."""

    id: UUID
    name: str
    url: str
    type: SourceType
    theme: str
    description: str | None
    logo_url: str | None
    is_curated: bool
    is_custom: bool = False
    is_trusted: bool = False
    is_muted: bool = False
    priority_multiplier: float = 1.0
    has_subscription: bool = False
    content_count: int = 0
    follower_count: int = 0
    bias_stance: str = "unknown"
    reliability_score: str = "unknown"
    bias_origin: str = "unknown"
    secondary_themes: list[str] | None = None
    granular_topics: list[str] | None = None
    source_tier: str = "mainstream"
    score_independence: float | None = None
    score_rigor: float | None = None
    score_ux: float | None = None
    editorial_note: str | None = None

    class Config:
        from_attributes = True


class SourceCreate(BaseModel):
    """Création d'une source custom."""

    url: str
    name: str | None = None


class SourceDetectRequest(BaseModel):
    """Requête de détection de source."""

    url: str


class SourceDetectResponse(BaseModel):
    """Réponse de détection de source."""

    source_id: UUID | None = None
    detected_type: SourceType
    feed_url: str
    name: str
    description: str | None = None
    logo_url: str | None = None
    theme: str
    preview: dict | None = None  # item_count, latest_titles
    is_search_result: bool = False  # Flag to know if we should display a list
    bias_stance: str = "unknown"
    reliability_score: str = "unknown"
    bias_origin: str = "unknown"


class SourceSearchResponse(BaseModel):
    """Réponse quand on reçoit plusieurs résultats."""

    results: list[SourceResponse]


class SourceCatalogResponse(BaseModel):
    """Réponse catalogue des sources curées."""

    curated: list[SourceResponse]
    custom: list[SourceResponse]


class UpdateSourceWeightRequest(BaseModel):
    """Mise à jour du poids d'une source."""

    priority_multiplier: float

    @field_validator("priority_multiplier")
    @classmethod
    def validate_multiplier(cls, v: float) -> float:
        allowed = {0.2, 1.0, 2.0}
        if v not in allowed:
            raise ValueError(
                f"priority_multiplier doit être 0.2, 1.0 ou 2.0 (reçu: {v})"
            )
        return v


class UpdateSourceSubscriptionRequest(BaseModel):
    """Mise à jour de l'abonnement premium à une source."""

    has_subscription: bool


# ─── Smart Search Schemas ─────────────────────────────────────────


class SmartSearchRequest(BaseModel):
    """Requête de recherche intelligente."""

    query: str = Field(..., min_length=1, max_length=500)
    content_type: ContentTypeFilter | None = None
    expand: bool = False


class SmartSearchRecentItem(BaseModel):
    """Item récent d'un feed pour preview."""

    title: str
    published_at: str = ""


class SmartSearchResultItem(BaseModel):
    """Résultat individuel du smart search."""

    name: str
    type: str
    url: str
    feed_url: str | None = None
    favicon_url: str | None = None
    description: str | None = None
    in_catalog: bool = False
    is_curated: bool = False
    source_id: UUID | None = None
    recent_items: list[SmartSearchRecentItem] = []
    score: float = 0.0
    source_layer: str = "unknown"


class SmartSearchResponse(BaseModel):
    """Réponse du smart search."""

    query_normalized: str
    results: list[SmartSearchResultItem]
    cache_hit: bool = False
    layers_called: list[str] = []
    latency_ms: int = 0


class SearchAbandonedRequest(BaseModel):
    """Signal d'abandon de recherche sans ajout de source."""

    query: str = Field(..., min_length=1, max_length=500)


class ThemeSourceGroup(BaseModel):
    """Groupe de sources par catégorie dans un thème."""

    label: str
    sources: list[SourceResponse]


class ThemeSourcesResponse(BaseModel):
    """Réponse sources par thème."""

    theme: str
    groups: list[ThemeSourceGroup]
    total_count: int = 0


class ThemeFollowed(BaseModel):
    """Thème suivi par un utilisateur."""

    slug: str
    label: str
    followed_sources_count: int = 0


class ThemesFollowedResponse(BaseModel):
    """Réponse thèmes suivis."""

    themes: list[ThemeFollowed]
