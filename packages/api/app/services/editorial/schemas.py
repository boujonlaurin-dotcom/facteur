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
    theme: str | None = None
    is_a_la_une: bool = False


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
    recul_intro: str | None = None


class EditorialSubject(BaseModel):
    """One of 5 subjects in the editorial digest."""

    rank: int
    topic_id: str
    label: str
    selection_reason: str
    deep_angle: str
    source_count: int = 0  # number of unique sources covering this topic
    theme: str | None = None
    is_a_la_une: bool = False  # headline subject (rank 1, most covered)
    # Editorial text fields — populated by WriterService (ÉTAPE 4)
    intro_text: str | None = None
    transition_text: str | None = None
    # Matched articles
    actu_article: MatchedActuArticle | None = None
    extra_actu_articles: list[MatchedActuArticle] = []
    deep_article: MatchedDeepArticle | None = None
    # Perspective analysis — populated by PerspectiveService (ÉTAPE 3C)
    perspective_count: int = 0
    bias_distribution: dict[str, int] | None = None
    bias_highlights: str | None = None
    divergence_analysis: str | None = None
    divergence_level: str | None = None  # "low" | "medium" | "high"
    perspective_sources: list[dict] | None = None  # PerspectiveSourceMini dicts


# --- Story 10.24: LLM writing output schemas ---


class SubjectWriting(BaseModel):
    """Per-subject writing from LLM (ÉTAPE 4)."""

    topic_id: str
    intro_text: str
    transition_text: str | None = None  # null for last subject
    recul_intro: str | None = None


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


class ActuDecaleeArticle(BaseModel):
    """LLM actu décalée selection for serein mode."""

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

    Contains the 5 selected topics with deep matches,
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
    actu_decalee: ActuDecaleeArticle | None = None

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
    actu_decalee: ActuDecaleeArticle | None = None


# --- Perspective helpers ---


class PerspectiveSourceMini(BaseModel):
    """Lightweight source info extracted from a Perspective.

    Distinct from SourceMini (which requires a UUID id) because Google News
    perspectives don't have a source_id in our DB.
    """

    name: str
    domain: str
    bias_stance: str = "unknown"
    logo_url: str | None = None


def compute_bias_distribution(perspectives: list) -> dict[str, int]:
    """Count perspectives by bias stance."""
    dist = {"left": 0, "center-left": 0, "center": 0, "center-right": 0, "right": 0}
    for p in perspectives:
        if p.bias_stance in dist:
            dist[p.bias_stance] += 1
    return dist


def compute_bias_highlights(dist: dict[str, int]) -> str:
    """Generate a human-readable bias highlight from distribution.

    Aggregates left+center-left and right+center-right before comparing.
    """
    total = sum(dist.values())
    if total == 0:
        return "Aucune source trouvée"

    left = dist.get("left", 0) + dist.get("center-left", 0)
    right = dist.get("right", 0) + dist.get("center-right", 0)

    # Total absence of one side (with other side having >= 2)
    if left == 0 and right >= 2:
        return "Aucun média de gauche"
    if right == 0 and left >= 2:
        return "Aucun média de droite"

    # Strong dominance (> 60%)
    if left / total > 0.6:
        return "Très couvert à gauche"
    if right / total > 0.6:
        return "Très couvert à droite"

    return "Couverture équilibrée"


def compute_divergence_level(dist: dict[str, int]) -> str:
    """Derive divergence level from bias distribution spread.

    Returns "low", "medium", or "high" based on how much the left/right
    sides are both represented.
    """
    total = sum(dist.values())
    if total < 2:
        return "low"

    left = dist.get("left", 0) + dist.get("center-left", 0)
    right = dist.get("right", 0) + dist.get("center-right", 0)

    # Only one side represented → low divergence
    if left == 0 or right == 0:
        return "low"

    # Both sides represented — check ratio of minority side
    minority = min(left, right)
    ratio = minority / total

    if ratio >= 0.3:
        return "high"
    elif ratio >= 0.15:
        return "medium"
    return "low"
