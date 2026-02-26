"""Schemas feed."""

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

    type: str | None = None  # article, podcast, youtube
    theme: str | None = None
    source_id: str | None = None
