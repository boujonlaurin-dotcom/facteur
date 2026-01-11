"""Schemas feed."""

from typing import Optional

from pydantic import BaseModel

from app.schemas.content import ContentResponse


class PaginationMeta(BaseModel):
    """Métadonnées de pagination."""

    page: int
    per_page: int
    total: int
    has_next: bool


class FeedItemResponse(ContentResponse):
    """Item du feed (hérite de ContentResponse)."""

    pass


class FeedResponse(BaseModel):
    """Réponse feed paginé."""

    items: list[FeedItemResponse]
    pagination: PaginationMeta


class FeedFilters(BaseModel):
    """Filtres du feed."""

    type: Optional[str] = None  # article, podcast, youtube
    theme: Optional[str] = None
    source_id: Optional[str] = None

