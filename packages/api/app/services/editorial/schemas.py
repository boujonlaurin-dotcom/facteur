"""Pydantic schemas for the editorial digest pipeline."""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel


class ClusterSummary(BaseModel):
    """Serialized TopicCluster for LLM input.

    `article_titles` retiré (LR-1 PR 2) : jusqu'à 10 titres / cluster gonflaient
    le prompt de curation sans peser sur la sélection (le LLM choisit sur
    label / couverture / trending / thème). Économie de tokens prompt, comportement
    de sélection inchangé.
    """

    topic_id: str
    label: str
    source_count: int
    is_trending: bool
    theme: str | None = None


class SelectedTopic(BaseModel):
    """LLM curation output (ÉTAPE 2)."""

    topic_id: str
    label: str  # 5-8 words
    selection_reason: str
    # `None` when the topic has no meaningful systemic/structural angle
    # (people, faits divers, actualité purement événementielle). When null,
    # DeepMatcher skips the topic — no "Pas de recul" is forced.
    deep_angle: str | None = None
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


class EditorialSubject(BaseModel):
    """One of 5 subjects in the editorial digest."""

    rank: int
    topic_id: str
    label: str
    selection_reason: str
    # `None` for topics with no meaningful systemic angle (people, faits
    # divers, sport, buzz). DeepMatcher skips these; see SelectedTopic.
    deep_angle: str | None = None
    source_count: int = 0  # number of unique sources covering this topic
    theme: str | None = None
    is_a_la_une: bool = False  # headline subject (rank 1, most covered)
    # Matched articles
    actu_article: MatchedActuArticle | None = None
    extra_actu_articles: list[MatchedActuArticle] = []
    # `deep_article` (Pas de recul) is disabled in the post-unification cleanup;
    # the field is kept None-only so persisted EditorialSubject snapshots remain
    # readable. TODO: réactiver pour la prochaine itération Pas de recul.
    deep_article: MatchedDeepArticle | None = None
    # Perspective analysis — populated by PerspectiveService (ÉTAPE 3C)
    perspective_count: int = 0
    bias_distribution: dict[str, int] | None = None
    bias_highlights: str | None = None
    divergence_analysis: str | None = None
    divergence_level: str | None = None  # "low" | "medium" | "high"
    perspective_sources: list[dict] | None = None  # PerspectiveSourceMini dicts
    # Full merged perspectives (cluster + GNews, known-bias filtered) used
    # to compute perspective_count / bias_distribution. Persisted so the
    # /contents/{id}/perspectives endpoint can return the SAME set the
    # digest header was built from — preview logos and bottom-sheet list
    # reference one snapshot. Each dict mirrors the Perspective dataclass:
    # {title, url, source_name, source_domain, bias_stance,
    #  published_at, description}.
    perspective_articles: list[dict] | None = None
    # Pivot content used to compute perspectives (cluster's most-recent article).
    # Mobile re-uses this id when calling /perspectives so the bottom sheet count
    # matches the header / bias spectrum bar. None on legacy cached digests.
    representative_content_id: UUID | None = None


class EditorialGlobalContext(BaseModel):
    """Global context computed once per batch (shared across all users).

    Contains the selected topics with their perspective analysis, plus the
    serialized cluster data for per-user actu matching.
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
