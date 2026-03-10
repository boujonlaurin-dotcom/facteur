"""Pydantic schemas for the editorial digest pipeline."""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel


class ClusterSummary(BaseModel):
    """Serialized TopicCluster for LLM input."""

    topic_id: str
    label: str
    article_titles: list[str]
    source_count: int
    is_trending: bool
    theme: str | None = None


class SelectedTopic(BaseModel):
    """LLM curation output (ÉTAPE 2)."""

    topic_id: str
    label: str  # 5-8 words
    selection_reason: str
    deep_angle: str  # systemic angle to search for in deep sources


class MatchedActuArticle(BaseModel):
    """ÉTAPE 3A output — news article from user's sources."""

    content_id: UUID
    title: str
    source_name: str
    source_id: UUID
    is_user_source: bool
    published_at: datetime


class MatchedDeepArticle(BaseModel):
    """ÉTAPE 3B output — deep analysis article."""

    content_id: UUID
    title: str
    source_name: str
    source_id: UUID
    published_at: datetime
    match_reason: str


class EditorialSubject(BaseModel):
    """One of 3 subjects in the editorial digest."""

    rank: int
    topic_id: str
    label: str
    selection_reason: str
    deep_angle: str
    # Editorial text fields — populated in Story 10.24
    intro_text: str | None = None
    transition_text: str | None = None
    # Matched articles
    actu_article: MatchedActuArticle | None = None
    deep_article: MatchedDeepArticle | None = None


class EditorialGlobalContext(BaseModel):
    """Global context computed once per batch (shared across all users).

    Contains the 3 selected topics with deep matches.
    Actu matching is per-user and happens in run_for_user().
    """

    subjects: list[EditorialSubject]
    # TopicCluster raw data serialized for actu matching
    # Stored as list of dicts since TopicCluster is a dataclass, not Pydantic
    cluster_data: list[dict]
    generated_at: datetime

    class Config:
        arbitrary_types_allowed = True


class EditorialPipelineResult(BaseModel):
    """Full pipeline output for one user."""

    subjects: list[EditorialSubject]
    metadata: dict  # timing, fallback_used, deep_hit_rate
