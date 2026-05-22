"""Schémas Pydantic pour « Ma veille »."""

from __future__ import annotations

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator

VeilleThemeSlug = Literal[
    "tech",
    "society",
    "environment",
    "economy",
    "politics",
    "culture",
    "science",
    "international",
    "sport",
]

MAX_KEYWORDS_PER_CONFIG = 20


def _normalize_keyword(raw: str) -> str:
    return " ".join(raw.split()).lower()


class VeilleTopicResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    topic_id: str
    label: str
    kind: Literal["preset", "suggested", "custom"]
    reason: str | None = None
    position: int = 0


class VeilleSourceLite(BaseModel):
    """Source hydratée embarquée dans une veille."""

    model_config = ConfigDict(from_attributes=True)

    id: UUID
    name: str
    url: str
    feed_url: str
    theme: str
    type: str
    is_curated: bool
    logo_url: str | None = None


class VeilleSourceResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    source: VeilleSourceLite
    kind: Literal["followed", "niche"]
    why: str | None = None
    position: int = 0


class VeilleKeywordResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    keyword: str
    position: int = 0


class VeilleConfigResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    user_id: UUID
    theme_id: str
    theme_label: str
    status: Literal["active", "paused", "archived"]
    created_at: datetime
    updated_at: datetime
    topics: list[VeilleTopicResponse] = []
    sources: list[VeilleSourceResponse] = []
    keywords: list[VeilleKeywordResponse] = []
    purpose: str | None = None
    editorial_brief: str | None = None
    preset_id: str | None = None


class VeilleTopicSelection(BaseModel):
    topic_id: str = Field(min_length=1, max_length=80)
    label: str = Field(min_length=1, max_length=200)
    kind: Literal["preset", "suggested", "custom"]
    reason: str | None = Field(default=None, max_length=500)
    position: int = Field(default=0, ge=0)


class VeilleNicheCandidate(BaseModel):
    """Niche absente du catalogue → ingestion à la volée."""

    name: str = Field(min_length=1, max_length=200)
    url: str = Field(min_length=4, max_length=2048)
    why: str | None = Field(default=None, max_length=500)


class VeilleSourceSelection(BaseModel):
    """Soit un source_id existant, soit un candidat niche à ingérer."""

    kind: Literal["followed", "niche"]
    source_id: UUID | None = None
    niche_candidate: VeilleNicheCandidate | None = None
    why: str | None = Field(default=None, max_length=500)
    position: int = Field(default=0, ge=0)


class VeilleKeywordSelection(BaseModel):
    """Mot-clé / angle libre saisi par l'utilisateur — normalisé lowercase."""

    keyword: str = Field(min_length=2, max_length=60)
    position: int = Field(default=0, ge=0)

    @field_validator("keyword")
    @classmethod
    def _normalize(cls, v: str) -> str:
        return _normalize_keyword(v)


class VeilleConfigUpsert(BaseModel):
    """Upsert config veille. Au moins UN parmi topics/sources/keywords requis."""

    theme_id: str = Field(min_length=1, max_length=50)
    theme_label: str = Field(min_length=1, max_length=120)
    topics: list[VeilleTopicSelection] = Field(default_factory=list)
    source_selections: list[VeilleSourceSelection] = Field(default_factory=list)
    keywords: list[VeilleKeywordSelection] = Field(
        default_factory=list, max_length=MAX_KEYWORDS_PER_CONFIG
    )
    purpose: str | None = Field(default=None, max_length=80)
    editorial_brief: str | None = Field(default=None, max_length=280)
    preset_id: str | None = Field(default=None, max_length=80)

    @field_validator("keywords")
    @classmethod
    def _dedupe_keywords(
        cls, v: list[VeilleKeywordSelection]
    ) -> list[VeilleKeywordSelection]:
        seen: set[str] = set()
        out: list[VeilleKeywordSelection] = []
        for kw in v:
            if kw.keyword in seen:
                continue
            seen.add(kw.keyword)
            out.append(kw)
        return out

    def model_post_init(self, __context: object) -> None:
        if not (self.topics or self.source_selections or self.keywords):
            raise ValueError("Au moins un topic, une source ou un mot-clé est requis.")


class VeilleSourceExample(BaseModel):
    """Aperçu d'article récent d'une source — Step 3 du flow veille."""

    title: str
    url: str
    published_at: datetime | None = None
    excerpt: str = ""


class VeillePresetResponse(BaseModel):
    """Pré-set d'inspiration affiché en bas du Step 1 du flow veille.

    Les `sources` sont hydratées au runtime depuis la table `sources` (filtre
    `theme + is_curated`) plutôt que d'être hardcodées en UUIDs : ainsi un
    re-seed du catalogue ne casse pas la liste.
    """

    slug: str
    label: str
    accroche: str
    theme_id: str
    theme_label: str
    topics: list[str] = Field(default_factory=list)
    purposes: list[str] = Field(default_factory=list)
    editorial_brief: str = ""
    sources: list[VeilleSourceLite] = Field(default_factory=list)


class VeilleFeedArticle(BaseModel):
    """Article exposé par GET /api/veille/feed."""

    model_config = ConfigDict(from_attributes=True)

    id: UUID
    title: str
    url: str
    description: str | None = None
    published_at: datetime | None = None
    source: VeilleSourceLite
    theme: str | None = None
    topics: list[str] = Field(default_factory=list)
    thumbnail_url: str | None = None
    matched_on: list[Literal["theme", "topic", "source", "keyword"]] = Field(
        default_factory=list
    )


class VeilleFeedResponse(BaseModel):
    """Réponse de GET /api/veille/feed."""

    items: list[VeilleFeedArticle] = Field(default_factory=list)
    total: int = 0
    limit: int = 20
    offset: int = 0
    has_more: bool = False


# ─── Suggesters LLM (Story 23.3) ─────────────────────────────────────────────


class VeilleSuggestAnglesRequest(BaseModel):
    """Input du POST /api/veille/suggest/angles."""

    theme_id: str = Field(min_length=1, max_length=50)
    theme_label: str = Field(min_length=1, max_length=120)
    brief: str = Field(default="", max_length=500)


class VeilleAngleSuggestion(BaseModel):
    """Un angle proposé par le LLM avec ses mots-clés explicites."""

    title: str = Field(min_length=1, max_length=120)
    keywords: list[str] = Field(default_factory=list, max_length=10)
    reason: str | None = Field(default=None, max_length=300)


class VeilleSuggestAnglesResponse(BaseModel):
    angles: list[VeilleAngleSuggestion] = Field(default_factory=list)


class VeilleSuggestSourcesRequest(BaseModel):
    """Input du POST /api/veille/suggest/sources."""

    theme_id: str = Field(min_length=1, max_length=50)
    theme_label: str = Field(min_length=1, max_length=120)
    brief: str = Field(default="", max_length=500)
    angles: list[str] = Field(default_factory=list, max_length=20)
    keywords: list[str] = Field(default_factory=list, max_length=40)


class VeilleSourceSuggestion(BaseModel):
    """Une source proposée par le LLM — pas encore ingérée en DB."""

    name: str = Field(min_length=1, max_length=200)
    url: str = Field(min_length=4, max_length=2048)
    why: str | None = Field(default=None, max_length=300)
    relevance_score: float = Field(ge=0.0, le=1.0)


class VeilleSuggestSourcesResponse(BaseModel):
    sources: list[VeilleSourceSuggestion] = Field(default_factory=list)
