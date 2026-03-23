"""Schemas feed."""

from uuid import UUID

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


class ClusterInfo(BaseModel):
    """Metadata d'un cluster d'articles regroupés par custom topic (Epic 11)."""

    topic_slug: str
    topic_name: str
    representative_id: UUID
    hidden_count: int
    hidden_ids: list[UUID]


class SourceOverflowInfo(BaseModel):
    """Metadata d'overflow: articles filtrés par diversification pour une source."""

    source_id: UUID
    hidden_count: int


class TopicOverflowInfo(BaseModel):
    """Metadata d'overflow: articles neutres regroupés par topic ou thème."""

    group_type: str  # "topic" ou "theme"
    group_key: str  # slug du topic ou theme
    group_label: str  # label traduit pour affichage
    hidden_count: int
    hidden_ids: list[UUID]


class FeedResponse(BaseModel):
    """Réponse feed paginé."""

    items: list[FeedItemResponse]
    pagination: PaginationMeta
    clusters: list[ClusterInfo] = []
    source_overflow: list[SourceOverflowInfo] = []
    topic_overflow: list[TopicOverflowInfo] = []


class FeedFilters(BaseModel):
    """Filtres du feed."""

    type: str | None = None  # article, podcast, youtube
    theme: str | None = None
    source_id: str | None = None
