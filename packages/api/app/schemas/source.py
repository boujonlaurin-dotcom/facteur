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
    content_count: int = 0

    class Config:
        from_attributes = True


class SourceCreate(BaseModel):
    """Création d'une source custom."""

    url: HttpUrl
    name: Optional[str] = None


class SourceDetectRequest(BaseModel):
    """Requête de détection de source."""

    url: HttpUrl


class SourceDetectResponse(BaseModel):
    """Réponse de détection de source."""

    detected_type: SourceType
    feed_url: str
    name: str
    description: Optional[str] = None
    logo_url: Optional[str] = None
    preview: Optional[dict] = None  # item_count, latest_title


class SourceCatalogResponse(BaseModel):
    """Réponse catalogue des sources curées."""

    curated: list[SourceResponse]
    custom: list[SourceResponse]


