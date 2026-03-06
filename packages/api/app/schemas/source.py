"""Schemas source."""

from uuid import UUID

from pydantic import BaseModel, field_validator

from app.models.enums import SourceType


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
    score_independence: float | None = None
    score_rigor: float | None = None
    score_ux: float | None = None

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
        allowed = {0.5, 1.0, 2.0}
        if v not in allowed:
            raise ValueError(
                f"priority_multiplier doit être 0.5, 1.0 ou 2.0 (reçu: {v})"
            )
        return v


class UpdateSourceSubscriptionRequest(BaseModel):
    """Mise à jour de l'abonnement premium à une source."""

    has_subscription: bool
