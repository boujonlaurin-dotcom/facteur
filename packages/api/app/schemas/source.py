"""Schemas source."""

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field

from app.models.enums import SourceType
from app.schemas.content import ContentResponse

ContentTypeFilter = Literal["article", "youtube", "reddit", "podcast"]


class SourceResponse(BaseModel):
    """Réponse source."""

    id: UUID
    name: str
    url: str
    type: SourceType
    theme: str
    description: str | None
    logo_url: str | None
    is_curated: bool
    is_custom: bool = False
    is_trusted: bool = False
    is_muted: bool = False
    priority_multiplier: float = 1.0
    has_subscription: bool = False
    content_count: int = 0
    # Volume de publication sur 30 j (calculé côté catalogue, défaut 0).
    # Additif/rétro-compatible — aucune colonne DB, aucune migration.
    articles_30d: int = 0
    follower_count: int = 0
    bias_stance: str = "unknown"
    reliability_score: str = "unknown"
    bias_origin: str = "unknown"
    secondary_themes: list[str] | None = None
    granular_topics: list[str] | None = None
    source_tier: str = "mainstream"
    score_independence: float | None = None
    score_rigor: float | None = None
    score_ux: float | None = None
    recommended_by: str | None = None
    recommendation_reason: str | None = None
    has_paywall: bool = False
    premium_connection: "PremiumConnectionResponse | None" = None

    class Config:
        from_attributes = True


class PremiumConnectionResponse(BaseModel):
    """Configuration mobile pour connecter une source payante en WebView."""

    enabled: bool = True
    login_url: str
    test_url: str
    display_hint: str | None = None
    # True quand la config est dérivée d'un fallback générique (URL = home de la
    # source) plutôt que d'une config curée/explicite. Le mobile adapte le label
    # du CTA ("Associer" vs "Connecter").
    is_generic: bool = False

    @staticmethod
    def is_explicitly_disabled(config: object) -> bool:
        """True when a source opts out of the WebView subscription flow."""
        return isinstance(config, dict) and config.get("enabled") is False

    @classmethod
    def from_config(cls, config: object) -> "PremiumConnectionResponse | None":
        if not isinstance(config, dict) or config.get("enabled") is not True:
            return None

        login_url = config.get("login_url")
        test_url = config.get("test_url")
        if not isinstance(login_url, str) or not login_url.strip():
            return None
        if not isinstance(test_url, str) or not test_url.strip():
            return None

        display_hint = config.get("display_hint")
        return cls(
            enabled=True,
            login_url=login_url.strip(),
            test_url=test_url.strip(),
            display_hint=display_hint.strip()
            if isinstance(display_hint, str) and display_hint.strip()
            else None,
        )

    @classmethod
    def from_source(
        cls, source: object, *, curated_map: dict
    ) -> "PremiumConnectionResponse | None":
        """Résout la config de connexion premium d'une source, par priorité.

        1. config explicite (``premium_connection_config``) si présente ;
        2. sinon match domaine dans ``curated_map`` → config curée
           (``is_generic=False``) ;
        3. sinon, si la source est payante (paywall_config / map) et possède une
           URL http(s) valide → fallback générique (login=test=home de la source,
           ``is_generic=True``) ;
        4. sinon ``None``.

        ``premium_connection_config.enabled = false`` est un opt-out explicite :
        il sert de blocklist pour les sources dont la connexion WebView est
        connue comme incompatible, et bloque donc aussi la map curée/le fallback.
        """
        # Import local : évite un cycle schemas → services au chargement.
        from app.services.premium_curated_sources import (
            domain_key,
            is_paywalled_source,
        )

        config = getattr(source, "premium_connection_config", None)
        if cls.is_explicitly_disabled(config):
            return None

        explicit = cls.from_config(config)
        if explicit is not None:
            return explicit

        url = getattr(source, "url", None)
        domain = domain_key(url)

        curated = curated_map.get(domain) if domain else None
        if isinstance(curated, dict):
            login_url = str(curated.get("login_url", "")).strip()
            test_url = str(curated.get("test_url", "")).strip()
            if login_url and test_url:
                hint = curated.get("display_hint")
                return cls(
                    enabled=True,
                    login_url=login_url,
                    test_url=test_url,
                    display_hint=hint.strip()
                    if isinstance(hint, str) and hint.strip()
                    else None,
                    is_generic=False,
                )

        if is_paywalled_source(source, curated_map=curated_map):
            clean_url = url.strip() if isinstance(url, str) else ""
            if clean_url.startswith(("http://", "https://")):
                return cls(
                    enabled=True,
                    login_url=clean_url,
                    test_url=clean_url,
                    display_hint=(
                        "Connecte-toi à ton compte sur le site du média, "
                        "puis reviens lire tes articles."
                    ),
                    is_generic=True,
                )

        return None


class SourceCreate(BaseModel):
    """Création d'une source custom."""

    url: str
    name: str | None = None


class SourceDetectRequest(BaseModel):
    """Requête de détection de source."""

    url: str


class SourceDetectResponse(BaseModel):
    """Réponse de détection de source."""

    source_id: UUID | None = None
    detected_type: SourceType
    feed_url: str
    name: str
    description: str | None = None
    logo_url: str | None = None
    theme: str
    preview: dict | None = None  # item_count, latest_titles
    is_search_result: bool = False  # Flag to know if we should display a list
    bias_stance: str = "unknown"
    reliability_score: str = "unknown"
    bias_origin: str = "unknown"


class SourceSearchResponse(BaseModel):
    """Réponse quand on reçoit plusieurs résultats."""

    results: list[SourceResponse]


class SourceCatalogResponse(BaseModel):
    """Réponse catalogue des sources curées."""

    curated: list[SourceResponse]
    custom: list[SourceResponse]


class UpdateSourceSubscriptionRequest(BaseModel):
    """Mise à jour de l'abonnement premium à une source."""

    has_subscription: bool


# ─── Smart Search Schemas ─────────────────────────────────────────


class SmartSearchRequest(BaseModel):
    """Requête de recherche intelligente."""

    query: str = Field(..., min_length=1, max_length=500)
    content_type: ContentTypeFilter | None = None
    expand: bool = False


class SmartSearchRecentItem(BaseModel):
    """Item récent d'un feed pour preview."""

    title: str
    published_at: str = ""
    # Thème inféré (clé brute backend ; mapping label/couleur côté front).
    # Additif/rétro-compatible : reste None si non fourni par l'appelant.
    theme: str | None = None


class SmartSearchResultItem(BaseModel):
    """Résultat individuel du smart search."""

    name: str
    type: str
    url: str
    feed_url: str | None = None
    favicon_url: str | None = None
    description: str | None = None
    in_catalog: bool = False
    is_curated: bool = False
    source_id: UUID | None = None
    recent_items: list[SmartSearchRecentItem] = []
    score: float = 0.0
    source_layer: str = "unknown"


class SmartSearchResponse(BaseModel):
    """Réponse du smart search."""

    query_normalized: str
    results: list[SmartSearchResultItem]
    cache_hit: bool = False
    layers_called: list[str] = []
    latency_ms: int = 0


class SearchAbandonedRequest(BaseModel):
    """Signal d'abandon de recherche sans ajout de source."""

    query: str = Field(..., min_length=1, max_length=500)


class RecentItemsRequest(BaseModel):
    """Requête batch des derniers contenus par source (conclusion onboarding)."""

    source_ids: list[UUID] = Field(default_factory=list, max_length=30)
    per_source: int = Field(default=3, ge=1, le=5)


class SourceRecentItems(BaseModel):
    """Derniers contenus d'une source, avec son identité visuelle."""

    source_id: UUID
    name: str
    logo_url: str | None = None
    items: list[SmartSearchRecentItem] = []


class RecentItemsResponse(BaseModel):
    """Réponse batch des derniers contenus par source."""

    sources: list[SourceRecentItems] = []


class ThemeSourceGroup(BaseModel):
    """Groupe de sources par catégorie dans un thème."""

    label: str
    sources: list[SourceResponse]


class ThemeSourcesResponse(BaseModel):
    """Réponse sources par thème."""

    theme: str
    groups: list[ThemeSourceGroup]
    total_count: int = 0


class ThemeFollowed(BaseModel):
    """Thème suivi par un utilisateur."""

    slug: str
    label: str
    followed_sources_count: int = 0


class ThemesFollowedResponse(BaseModel):
    """Réponse thèmes suivis."""

    themes: list[ThemeFollowed]


class CoverageRow(BaseModel):
    """Couverture d'un thème par une source sur la période."""

    theme: str
    count: int
    pct: int


class CoverageResponse(BaseModel):
    """Agrégation de la couverture par thème d'une source.

    `theme` reste la clé brute backend ; le mapping label/couleur est fait
    côté front. `rows` est trié par `count` décroissant, top N + « autres ».
    """

    period_label: str
    total_count: int
    caption: str
    rows: list[CoverageRow] = []


class ThemeShare(BaseModel):
    """Part d'un thème dans la couverture d'une source (fiche source v3).

    `theme` reste la clé brute backend (mapping label/couleur côté front).
    `share` ∈ [0, 1] = `count / total` ; le mobile dérive le pourcentage.
    """

    theme: str
    count: int
    share: float


class SourceProfileResponse(BaseModel):
    """Profil unifié d'une source pour la fiche v3.

    Regroupe en une réponse l'identité de la source, sa couverture par thèmes
    sur 30 jours (`theme_distribution` + `articles_30d`), la date du plus
    ancien contenu connu (`oldest_content_at`, hors fenêtre, pour clamper le
    calcul de fréquence côté mobile) et ses articles les plus récents
    (`Content` complets → carte cliquable standard).
    """

    source: SourceResponse
    recent_articles: list[ContentResponse] = []
    theme_distribution: list[ThemeShare] = []
    articles_30d: int = 0
    oldest_content_at: datetime | None = None
