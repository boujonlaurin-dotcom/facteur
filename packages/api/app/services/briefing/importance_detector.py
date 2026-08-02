"""Module de détection d'importance et clustering pour le briefing quotidien.

Story 4.4: Top 3 Briefing Quotidien
Epic 10+: Digest "Sujets du jour" — clustering universel

Ce module détecte les contenus objectivement importants via:
1. Parsing des feeds "À la Une" des sources de référence
2. Regroupement des titres par cosinus pondéré IDF pour détecter les sujets tendance
3. Clustering universel pour regrouper les articles par sujet (build_topic_clusters)

Architecture: Ce module est DÉCOUPLÉ du ScoringEngine. Il consomme les contenus
bruts et produit des clusters/flags d'importance utilisés par TopicSelector et Top3Selector.
"""

import os
from collections import Counter
from dataclasses import dataclass, field
from urllib.parse import urlparse
from uuid import UUID, uuid4

import structlog

from app.models.content import Content
from app.models.enums import SourceType
from app.services.text_similarity import (
    FRENCH_STOP_WORDS,
)
from app.services.text_similarity import (
    jaccard_similarity as _jaccard_similarity,
)
from app.services.text_similarity import (
    normalize_title as _normalize_title,
)

# Sources qui agrègent / partagent du contenu d'autres médias plutôt que
# d'en produire (Reddit, …). Quand un cluster contient à la fois une source
# primaire ET un share Reddit du même sujet, on ne compte pas Reddit comme
# une "couverture média" distincte. Cf. bug-digest-pipeline-fallbacks.md C4.
_AGGREGATOR_SOURCE_TYPES: frozenset[SourceType] = frozenset({SourceType.REDDIT})

# Fold fiabilité (B-2) : valeurs par défaut et vocabulaire « faux » des flags env.
_DEFAULT_COVERAGE_FOLD_SCORES: frozenset[str] = frozenset({"low", "mixed"})
_FALSEY_ENV_VALUES: frozenset[str] = frozenset({"false", "0", "no", ""})


def _extract_domain(url: str) -> str:
    """Extrait le domaine canonique depuis une URL d'article.

    Deux feeds du même site (ex: francetvinfo.fr/titres.rss et
    francetvinfo.fr/vrai-ou-fake.rss) retournent le même domaine, évitant
    qu'ils soient comptés comme deux sources distinctes dans le clustering.
    """
    try:
        host = urlparse(str(url)).netloc
        return (host or str(url)).removeprefix("www.")
    except Exception:
        return str(url)


def _coverage_fold_enabled() -> bool:
    """Kill switch du fold fiabilité (B-2).

    `EDITORIAL_COVERAGE_FOLD_ENABLED=false` restaure le comportement
    historique : seuls les agrégateurs (Reddit) sont foldés. Lu à l'usage
    (pas de cache) pour rester testable sans `cache_clear`.
    """
    raw = os.environ.get("EDITORIAL_COVERAGE_FOLD_ENABLED", "true").strip().lower()
    return raw not in _FALSEY_ENV_VALUES


def _coverage_fold_reliability_scores() -> frozenset[str]:
    """Scores de fiabilité qui déclenchent le fold (défaut : low, mixed).

    ⚠️ `unknown` volontairement absent du défaut : « jamais évaluée » ≠ « peu
    fiable » — l'inclure folderait ~39,5 % du corpus `politics` (cf.
    bug-curation-essentiel-personnalisation §1.2). Surchargeable via
    `EDITORIAL_COVERAGE_FOLD_RELIABILITY` (CSV).
    """
    raw = os.environ.get("EDITORIAL_COVERAGE_FOLD_RELIABILITY", "").strip()
    if not raw:
        return _DEFAULT_COVERAGE_FOLD_SCORES
    return frozenset(s.strip().lower() for s in raw.split(",") if s.strip())


def _counts_toward_coverage(content: Content) -> bool:
    """True si la source du contenu compte comme une couverture média distincte.

    Renvoie False (le contenu ne gonfle pas `source_count`) pour :
    - les **agrégateurs** (Reddit) — reprise, pas production éditoriale ;
    - les **sources non curées à faible fiabilité** (`reliability_score`
      ∈ {low, mixed}) — du volume sans jugement (BFMTV « Home Fil actu »,
      CNEWS). `unknown` n'est PAS foldée (cf. `_coverage_fold_reliability_scores`).

    Sémantique de **repli conservée** : `build_topic_clusters` ne folde ces
    sources que si le cluster contient au moins une source qui compte ; un
    cluster composé uniquement de sources foldées garde son décompte.
    """
    src = getattr(content, "source", None)
    if src is None:
        # Source inconnue → on ne folde pas (conservateur).
        return True

    # Agrégateur (Reddit) : jamais une couverture distincte. Foldé même quand
    # le kill switch est off (comportement historique).
    src_type = getattr(src, "type", None)
    if src_type is not None:
        try:
            if SourceType(src_type) in _AGGREGATOR_SOURCE_TYPES:
                return False
        except ValueError:
            pass

    # Fold fiabilité (B-2) : non curée ET reliability ∈ {low, mixed}.
    if _coverage_fold_enabled() and not bool(getattr(src, "is_curated", False)):
        score = getattr(src, "reliability_score", None)
        score_str = str(getattr(score, "value", score) or "").strip().lower()
        if score_str in _coverage_fold_reliability_scores():
            return False

    return True


# Re-exposé pour compat (anciennement défini ici)
__all__ = ["FRENCH_STOP_WORDS", "ImportanceDetector", "TopicCluster"]

logger = structlog.get_logger()


@dataclass
class TopicCluster:
    """Un cluster de contenus regroupés par similarité de titre.

    Représente un "sujet" du jour : plusieurs articles de sources différentes
    couvrant le même événement/thème.
    """

    cluster_id: str
    label: str  # Titre du meilleur article (set par TopicSelector après scoring)
    tokens: set[str]
    contents: list[Content] = field(default_factory=list)
    source_ids: set[UUID] = field(default_factory=set)
    source_domains: set[str] = field(default_factory=set)
    theme: str | None = None  # Thème dominant du cluster

    @property
    def is_trending(self) -> bool:
        """Cluster couvert par ≥3 domaines distincts."""
        return len(self.source_domains) >= 3

    @property
    def is_multi_source(self) -> bool:
        """Cluster couvert par ≥2 domaines distincts."""
        return len(self.source_domains) >= 2


class ImportanceDetector:
    """Détecte les contenus objectivement importants.

    Ce module analyse les contenus pour identifier:
    1. Les articles provenant des feeds "À la Une" des sources de référence
    2. Les sujets tendance (couverts par ≥N sources distinctes)

    Attributes:
        similarity_threshold: Seuil de cosinus IDF pour regrouper les titres (défaut: 0.30)
        min_sources_for_trending: Nombre minimum de sources pour qu'un sujet soit "trending" (défaut: 3)
    """

    def __init__(
        self, similarity_threshold: float = 0.30, min_sources_for_trending: int = 3
    ):
        """Initialise le détecteur d'importance.

        Args:
            similarity_threshold: Seuil de cosinus pondéré IDF [0-1].
                0.30 = valeur calibrée sur corpus annoté (cf. ScoringWeights
                .TOPIC_CLUSTER_COSINE_THRESHOLD).
            min_sources_for_trending: Nombre minimum de sources distinctes
                couvrant un même sujet pour le considérer comme "trending".
        """
        if not 0 <= similarity_threshold <= 1:
            raise ValueError("similarity_threshold doit être entre 0 et 1")
        if min_sources_for_trending < 2:
            raise ValueError("min_sources_for_trending doit être >= 2")

        self.similarity_threshold = similarity_threshold
        self.min_sources_for_trending = min_sources_for_trending

    def normalize_title(self, title: str) -> set[str]:
        """Délègue à `text_similarity.normalize_title` (méthode conservée pour compat)."""
        return _normalize_title(title)

    def jaccard_similarity(self, tokens_a: set[str], tokens_b: set[str]) -> float:
        """Délègue à `text_similarity.jaccard_similarity` (méthode conservée pour compat)."""
        return _jaccard_similarity(tokens_a, tokens_b)

    def build_topic_clusters(
        self,
        contents: list[Content],
        similarity_threshold: float | None = None,
    ) -> list[TopicCluster]:
        """Cluster tous les contenus par similarité de titre.

        Retourne TOUS les clusters (y compris singletons). Chaque cluster
        représente un sujet potentiel pour le digest.

        Le regroupement lui-même est délégué à `topic_clustering.cluster_documents`
        (cosinus pondéré IDF, liaison par centroïde) ; cette méthode y ajoute les
        métadonnées métier (sources, domaines, thème dominant, fold agrégateurs).

        Args:
            contents: Liste des contenus à analyser
            similarity_threshold: Seuil cosinus override (default: self.similarity_threshold)

        Returns:
            Liste de TopicCluster triée par taille décroissante
        """
        if not contents:
            return []

        threshold = (
            similarity_threshold
            if similarity_threshold is not None
            else self.similarity_threshold
        )

        # Phase 1: Regroupement par cosinus pondéré IDF (cf. topic_clustering).
        from app.services.briefing.topic_clustering import cluster_documents
        from app.services.recommendation.scoring_config import ScoringWeights

        # Les titres sans token exploitable sont écartés du clustering, mais on
        # garde la correspondance index → contenu pour reconstruire les clusters.
        indexed: list[tuple[Content, set[str]]] = []
        for content in contents:
            tokens = self.normalize_title(content.title)
            if tokens:
                indexed.append((content, tokens))

        if not indexed:
            return []

        groups = cluster_documents(
            [tokens for _, tokens in indexed],
            threshold=threshold,
            min_tokens=ScoringWeights.TOPIC_CLUSTER_MIN_TOKENS,
        )

        raw_clusters: list[dict] = [
            {
                "tokens": set().union(*(indexed[i][1] for i in group)),
                "contents": [indexed[i][0] for i in group],
            }
            for group in groups
        ]

        # Phase 2: Convertir en TopicCluster avec métadonnées
        topic_clusters: list[TopicCluster] = []

        for raw in raw_clusters:
            cluster_contents: list[Content] = raw["contents"]
            # Fold couverture (agrégateurs + faible fiabilité non curée, B-2) :
            # si le cluster contient au moins une source qui compte comme
            # couverture média distincte, on n'inclut pas les sources foldées
            # (Reddit, ou non curée low/mixed) dans le décompte. Sinon (cluster
            # composé uniquement de sources foldées), on les conserve — un sujet
            # repris uniquement par r/france ou CNEWS mérite encore d'exister.
            counted_source_ids: set[UUID] = set()
            folded_source_ids: set[UUID] = set()
            counted_source_domains: set[str] = set()
            folded_source_domains: set[str] = set()
            for c in cluster_contents:
                domain = _extract_domain(c.url)
                if _counts_toward_coverage(c):
                    counted_source_ids.add(c.source_id)
                    counted_source_domains.add(domain)
                else:
                    folded_source_ids.add(c.source_id)
                    folded_source_domains.add(domain)
            source_ids = counted_source_ids or folded_source_ids
            source_domains = counted_source_domains or folded_source_domains

            # Thème dominant : mode de content.theme, fallback source.theme
            themes: list[str] = []
            for c in cluster_contents:
                t = getattr(c, "theme", None)
                if not t and c.source:
                    t = getattr(c.source, "theme", None)
                if t:
                    themes.append(t)
            theme = Counter(themes).most_common(1)[0][0] if themes else None

            topic_clusters.append(
                TopicCluster(
                    cluster_id=str(uuid4()),
                    # Label initialisé avec le titre du meilleur article du cluster :
                    # sert de référence au LLM et garantit un fallback déterministe non vide.
                    label=cluster_contents[0].title[:80] if cluster_contents else "",
                    tokens=raw["tokens"],
                    contents=cluster_contents,
                    source_ids=source_ids,
                    source_domains=source_domains,
                    theme=theme,
                )
            )

        # Tri par taille décroissante (multi-articles en premier)
        topic_clusters.sort(key=lambda c: len(c.contents), reverse=True)

        logger.info(
            "topic_clustering_complete",
            total_contents=len(contents),
            total_clusters=len(topic_clusters),
            multi_article_clusters=sum(
                1 for c in topic_clusters if len(c.contents) >= 2
            ),
            multi_source_clusters=sum(1 for c in topic_clusters if c.is_multi_source),
            trending_clusters=sum(1 for c in topic_clusters if c.is_trending),
            threshold=threshold,
        )

        return topic_clusters

    def detect_trending_clusters(self, contents: list[Content]) -> set[UUID]:
        """Détecte les contenus faisant partie de sujets tendance.

        Wrapper autour de build_topic_clusters() qui filtre les clusters
        avec ≥min_sources_for_trending sources distinctes.

        Args:
            contents: Liste des contenus à analyser

        Returns:
            Set des UUIDs des contenus faisant partie d'un sujet tendance
        """
        if not contents:
            return set()

        clusters = self.build_topic_clusters(contents)

        trending_content_ids: set[UUID] = set()
        trending_count = 0

        for cluster in clusters:
            if len(cluster.source_domains) >= self.min_sources_for_trending:
                trending_count += 1
                for content in cluster.contents:
                    trending_content_ids.add(content.id)

                logger.debug(
                    "trending_cluster_detected",
                    cluster_size=len(cluster.contents),
                    source_count=len(cluster.source_ids),
                    sample_title=cluster.contents[0].title[:50]
                    if cluster.contents
                    else "",
                )

        logger.info(
            "trending_detection_complete",
            total_contents=len(contents),
            total_clusters=len(clusters),
            trending_clusters=trending_count,
            trending_content_count=len(trending_content_ids),
        )

        return trending_content_ids

    def identify_une_contents(
        self, contents: list[Content], une_guids: set[str]
    ) -> set[UUID]:
        """Identifie les contenus provenant des feeds "À la Une".

        Args:
            contents: Liste des contenus à analyser
            une_guids: Set des GUIDs des articles présents dans les feeds Une

        Returns:
            Set des UUIDs des contenus "À la Une"
        """
        une_content_ids: set[UUID] = set()

        for content in contents:
            if content.guid in une_guids:
                une_content_ids.add(content.id)

        logger.info(
            "une_identification_complete",
            total_contents=len(contents),
            une_guids_count=len(une_guids),
            matched_count=len(une_content_ids),
        )

        return une_content_ids
