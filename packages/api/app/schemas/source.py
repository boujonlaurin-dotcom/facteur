"""Schemas source."""

from datetime import datetime
from typing import Optional
from uuid import UUID

from pydantic import BaseModel, HttpUrl

from app.models.enums import SourceType


class SourceResponse(BaseModel):
    """Réponse source."""

    id: UUID
    name: str
    url: str
    type: SourceType
    theme: str
    description: Optional[str]
    logo_url: Optional[str]
    is_curated: bool
    is_custom: bool = False
    is_trusted: bool = False
    is_muted: bool = False
    content_count: int = 0
    follower_count: int = 0
    bias_stance: str = "unknown"
    reliability_score: str = "unknown"
    bias_origin: str = "unknown"
    secondary_themes: Optional[list[str]] = None
    score_independence: Optional[float] = None
    score_rigor: Optional[float] = None
    score_ux: Optional[float] = None

    class Config:
        from_attributes = True


class SourceCreate(BaseModel):
    """Création d'une source custom."""

    url: str
    name: Optional[str] = None


class SourceDetectRequest(BaseModel):
    """Requête de détection de source."""

    url: str


class SourceDetectResponse(BaseModel):
    """Réponse de détection de source."""

    source_id: Optional[UUID] = None
    detected_type: SourceType
    feed_url: str
    name: str
    description: Optional[str] = None
    logo_url: Optional[str] = None
    theme: str
    preview: Optional[dict] = None  # item_count, latest_titles
    is_search_result: bool = False # Flag to know if we should display a list
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


