"""Schémas Pydantic pour « Ma veille »."""

from __future__ import annotations

from datetime import date, datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

# Slugs autorisés pour `theme_id` dans les requêtes de suggestion. Doit
# rester aligné avec la contrainte SQL `ck_source_theme_valid` (cf.
# alembic/versions/*_add_*_to_constraint.py) ET avec la liste des thèmes
# Facteur côté front (`kVeilleFacteurThemes`) + onboarding
# (`user_service.py:170`). Un slug hors liste → 422 immédiat.
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


# ─── Sub-objects ─────────────────────────────────────────────────────────────


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


# ─── Config (GET / POST / PATCH) ─────────────────────────────────────────────


class VeilleConfigResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    user_id: UUID
    theme_id: str
    theme_label: str
    frequency: Literal["weekly", "biweekly", "monthly"]
    day_of_week: int | None = None
    delivery_hour: int = 7
    timezone: str = "Europe/Paris"
    status: Literal["active", "paused", "archived"]
    last_delivered_at: datetime | None = None
    next_scheduled_at: datetime | None = None
    created_at: datetime
    updated_at: datetime
    topics: list[VeilleTopicResponse] = []
    sources: list[VeilleSourceResponse] = []
    purpose: str | None = None
    purpose_other: str | None = None
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


class VeilleConfigUpsert(BaseModel):
    theme_id: str = Field(min_length=1, max_length=50)
    theme_label: str = Field(min_length=1, max_length=120)
    topics: list[VeilleTopicSelection] = Field(default_factory=list)
    source_selections: list[VeilleSourceSelection] = Field(default_factory=list)
    frequency: Literal["weekly", "biweekly", "monthly"]
    day_of_week: int | None = Field(default=None, ge=0, le=6)
    delivery_hour: int = Field(default=7, ge=0, le=23)
    timezone: str = Field(default="Europe/Paris", max_length=64)
    # V1 personalization — acceptés par le schéma (PR A) mais persistance
    # cablée plus tard (PR B).
    purpose: str | None = Field(default=None, max_length=80)
    purpose_other: str | None = Field(default=None, max_length=80)
    editorial_brief: str | None = Field(default=None, max_length=280)
    preset_id: str | None = Field(default=None, max_length=80)


class VeilleConfigPatch(BaseModel):
    frequency: Literal["weekly", "biweekly", "monthly"] | None = None
    day_of_week: int | None = Field(default=None, ge=0, le=6)
    delivery_hour: int | None = Field(default=None, ge=0, le=23)
    timezone: str | None = Field(default=None, max_length=64)
    status: Literal["active", "paused", "archived"] | None = None
    purpose: str | None = Field(default=None, max_length=80)
    purpose_other: str | None = Field(default=None, max_length=80)
    editorial_brief: str | None = Field(default=None, max_length=280)
    preset_id: str | None = Field(default=None, max_length=80)


# ─── Suggestions ─────────────────────────────────────────────────────────────


class VeilleTopicSuggestion(BaseModel):
    topic_id: str
    label: str
    reason: str | None = None


class VeilleSuggestTopicsRequest(BaseModel):
    theme_id: VeilleThemeSlug
    theme_label: str = Field(min_length=1, max_length=120)
    selected_topic_ids: list[str] = Field(default_factory=list)
    exclude_topic_ids: list[str] = Field(default_factory=list)
    purpose: str | None = Field(default=None, max_length=80)
    purpose_other: str | None = Field(default=None, max_length=80)
    editorial_brief: str | None = Field(default=None, max_length=280)


class VeilleSourceSuggestion(BaseModel):
    source_id: UUID
    name: str
    url: str
    feed_url: str
    theme: str
    why: str | None = None


class VeilleSourceSuggestionsResponse(BaseModel):
    followed: list[VeilleSourceSuggestion]
    niche: list[VeilleSourceSuggestion]


class VeilleSuggestSourcesRequest(BaseModel):
    theme_id: VeilleThemeSlug
    topic_labels: list[str] = Field(default_factory=list)
    exclude_source_ids: list[UUID] = Field(default_factory=list)
    purpose: str | None = Field(default=None, max_length=80)
    purpose_other: str | None = Field(default=None, max_length=80)
    editorial_brief: str | None = Field(default=None, max_length=280)


# ─── Deliveries ──────────────────────────────────────────────────────────────


class VeilleDeliveryListItem(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    veille_config_id: UUID
    target_date: date
    generation_state: Literal["pending", "running", "succeeded", "failed"]
    item_count: int = 0
    generated_at: datetime | None = None
    created_at: datetime


class VeilleDeliveryArticle(BaseModel):
    """Article référencé dans un cluster d'une livraison veille."""

    content_id: UUID
    source_id: UUID
    title: str
    url: str
    excerpt: str = ""
    published_at: datetime


class VeilleDeliveryItem(BaseModel):
    """Cluster thématique exposé au front (Story 18.2)."""

    cluster_id: str
    title: str
    articles: list[VeilleDeliveryArticle] = Field(default_factory=list)
    why_it_matters: str = ""


class VeilleDeliveryResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    veille_config_id: UUID
    target_date: date
    items: list[VeilleDeliveryItem] = Field(default_factory=list)
    generation_state: Literal["pending", "running", "succeeded", "failed"]
    attempts: int
    started_at: datetime | None = None
    finished_at: datetime | None = None
    last_error: str | None = None
    version: int
    generated_at: datetime | None = None
    created_at: datetime
    updated_at: datetime


class VeilleGenerateRequest(BaseModel):
    """Force une génération pour la config courante au target_date=today."""

    target_date: date | None = None


class VeilleGenerateFirstResponse(BaseModel):
    """Réponse 202 du POST /deliveries/generate-first."""

    delivery_id: UUID
    estimated_seconds: int = 60


class VeilleSourceExample(BaseModel):
    """Aperçu d'article récent d'une source — Step 3 du flow veille."""

    title: str
    url: str
    published_at: datetime | None = None
    excerpt: str = ""


# ─── Presets (V1 onboarding) ─────────────────────────────────────────────────


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
