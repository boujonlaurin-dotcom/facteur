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
    source_count: int = 0  # number of unique sources covering this topic


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
    description: str | None = None


class EditorialSubject(BaseModel):
    """One of 3 subjects in the editorial digest."""

    rank: int
    topic_id: str
    label: str
    selection_reason: str
    deep_angle: str
    source_count: int = 0  # number of unique sources covering this topic
    is_a_la_une: bool = False  # headline subject (rank 1, most covered)
    # Editorial text fields — populated by WriterService (ÉTAPE 4)
    intro_text: str | None = None
    transition_text: str | None = None
    # Matched articles
    actu_article: MatchedActuArticle | None = None
    deep_article: MatchedDeepArticle | None = None


# --- Story 10.24: LLM writing output schemas ---


class SubjectWriting(BaseModel):
    """Per-subject writing from LLM (ÉTAPE 4)."""

    topic_id: str
    intro_text: str
    transition_text: str | None = None  # null for last subject


class WritingOutput(BaseModel):
    """Full LLM writing output (ÉTAPE 4)."""

    header_text: str
    subjects: list[SubjectWriting]
    closure_text: str
    cta_text: str | None = None


class PepiteArticle(BaseModel):
    """LLM pépite selection (ÉTAPE 5)."""

    content_id: UUID
    mini_editorial: str


class CoupDeCoeurArticle(BaseModel):
    """Most-saved article by community (ÉTAPE 6). No LLM."""

    content_id: UUID
    title: str
    source_name: str
    save_count: int


class EditorialGlobalContext(BaseModel):
    """Global context computed once per batch (shared across all users).

    Contains the 3 selected topics with deep matches,
    plus editorial texts, pépite, and coup de coeur (Story 10.24).
    """

    subjects: list[EditorialSubject]
    # TopicCluster raw data serialized for actu matching
    # Stored as list of dicts since TopicCluster is a dataclass, not Pydantic
    cluster_data: list[dict]
    generated_at: datetime
    # Story 10.24: editorial writing output
    header_text: str | None = None
    closure_text: str | None = None
    cta_text: str | None = None
    pepite: PepiteArticle | None = None
    coup_de_coeur: CoupDeCoeurArticle | None = None

    class Config:
        arbitrary_types_allowed = True


class EditorialPipelineResult(BaseModel):
    """Full pipeline output for one user."""

    subjects: list[EditorialSubject]
    metadata: dict  # timing, fallback_used, deep_hit_rate
    # Story 10.24: editorial writing output (propagated from global context)
    header_text: str | None = None
    closure_text: str | None = None
    cta_text: str | None = None
    pepite: PepiteArticle | None = None
    coup_de_coeur: CoupDeCoeurArticle | None = None
