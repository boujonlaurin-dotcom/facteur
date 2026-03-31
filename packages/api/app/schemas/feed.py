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


class OverflowSourceInfo(BaseModel):
    """Source info within an overflow group (shared by keyword, topic, and cluster)."""

    source_id: UUID
    source_name: str
    source_logo_url: str | None
    article_count: int


class ClusterInfo(BaseModel):
    """Metadata d'un cluster d'articles regroupés par custom topic (Epic 11)."""

    topic_slug: str
    topic_name: str
    representative_id: UUID
    hidden_count: int
    hidden_ids: list[UUID]
    sources: list[OverflowSourceInfo] = []


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
    sources: list[OverflowSourceInfo] = []


# Alias for backward compatibility in router imports
KeywordOverflowSourceInfo = OverflowSourceInfo


class KeywordOverflowInfo(BaseModel):
    """Metadata d'overflow: articles regroupés par keyword mining sur les titres."""

    keyword: str
    display_label: str
    hidden_count: int
    hidden_ids: list[UUID]
    sources: list[KeywordOverflowSourceInfo]
    is_custom_topic: bool = False


class EntityOverflowInfo(BaseModel):
    """Metadata d'overflow: articles regroupés par entité nommée (NER)."""

    entity_name: str
    display_label: str
    hidden_count: int
    hidden_ids: list[UUID]
    sources: list[OverflowSourceInfo] = []


class FeedResponse(BaseModel):
    """Réponse feed paginé."""

    items: list[FeedItemResponse]
    pagination: PaginationMeta
    clusters: list[ClusterInfo] = []
    source_overflow: list[SourceOverflowInfo] = []
    topic_overflow: list[TopicOverflowInfo] = []
    keyword_overflow: list[KeywordOverflowInfo] = []
    entity_overflow: list[EntityOverflowInfo] = []


class FeedFilters(BaseModel):
    """Filtres du feed."""

    type: str | None = None  # article, podcast, youtube
    theme: str | None = None
    source_id: str | None = None
