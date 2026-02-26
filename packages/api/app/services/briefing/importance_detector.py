"""Module de détection d'importance et clustering pour le briefing quotidien.

Story 4.4: Top 3 Briefing Quotidien
Epic 10+: Digest "Sujets du jour" — clustering universel

Ce module détecte les contenus objectivement importants via:
1. Parsing des feeds "À la Une" des sources de référence
2. Clustering des titres par similarité Jaccard pour détecter les sujets tendance
3. Clustering universel pour regrouper les articles par sujet (build_topic_clusters)

Architecture: Ce module est DÉCOUPLÉ du ScoringEngine. Il consomme les contenus
bruts et produit des clusters/flags d'importance utilisés par TopicSelector et Top3Selector.
"""

import re
import unicodedata
from collections import Counter
from dataclasses import dataclass, field
from uuid import UUID, uuid4

import structlog

from app.models.content import Content

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
    theme: str | None = None  # Thème dominant du cluster

    @property
    def is_trending(self) -> bool:
        """Cluster couvert par ≥3 sources distinctes."""
        return len(self.source_ids) >= 3

    @property
    def is_multi_source(self) -> bool:
        """Cluster couvert par ≥2 sources distinctes."""
        return len(self.source_ids) >= 2


# Stop words français courants (à filtrer des titres).
# IMPORTANT: Les mots sont en version SANS ACCENT car normalize_title() strip les accents.
# Enrichi avec les mots news-génériques de StoryService.STOPWORDS pour éviter les faux clusters.
FRENCH_STOP_WORDS = frozenset(
    [
        # --- Articles, pronoms, déterminants ---
        "le",
        "la",
        "les",
        "un",
        "une",
        "des",
        "du",
        "de",
        "au",
        "aux",
        "ce",
        "ces",
        "cet",
        "cette",
        "mon",
        "ton",
        "son",
        "ma",
        "ta",
        "sa",
        "mes",
        "tes",
        "ses",
        "notre",
        "votre",
        "leur",
        "nos",
        "vos",
        "leurs",
        "qui",
        "que",
        "quoi",
        "dont",
        "quel",
        "quelle",
        "quels",
        "quelles",
        "il",
        "elle",
        "ils",
        "elles",
        "on",
        "nous",
        "vous",
        "je",
        "tu",
        "se",
        "ne",
        "pas",
        "plus",
        "moins",
        "tres",
        "aussi",
        "tout",
        "tous",
        "toute",
        "meme",
        "autres",
        "autre",
        # --- Conjonctions, prépositions ---
        "et",
        "ou",
        "mais",
        "donc",
        "or",
        "ni",
        "car",
        "pour",
        "par",
        "avec",
        "sans",
        "sous",
        "sur",
        "dans",
        "en",
        "est",
        "sont",
        "ont",
        "entre",
        "apres",
        "avant",
        "comme",
        "vers",
        "chez",
        "face",
        "contre",
        "selon",
        "suite",
        "depuis",
        "lors",
        "durant",
        "pendant",
        # --- Verbes courants ---
        "etre",
        "avoir",
        "faire",
        "fait",
        "dit",
        "peut",
        "faut",
        "doit",
        "ete",
        "sera",
        "peuvent",
        "vont",
        "veut",
        "alors",
        "si",
        "quand",
        "comment",
        "pourquoi",
        "combien",
        # --- Adverbes ---
        "encore",
        "toujours",
        "jamais",
        "souvent",
        "bien",
        "mal",
        "peu",
        "beaucoup",
        "trop",
        "assez",
        "vraiment",
        # --- Noms news-génériques (causent les faux clusters) ---
        "monde",
        "pays",
        "president",
        "gouvernement",
        "ministre",
        "politique",
        "economie",
        "societe",
        "histoire",
        "international",
        "national",
        "local",
        # --- Adjectifs courants ---
        "nouveau",
        "nouvelle",
        "nouveaux",
        "nouvelles",
        "grand",
        "grande",
        "grands",
        "grandes",
        "petit",
        "petite",
        "petits",
        "petites",
        "premier",
        "premiere",
        "dernier",
        "derniere",
        # --- Temporels ---
        "annee",
        "annees",
        "jour",
        "jours",
        "fois",
        "temps",
        "heure",
        "heures",
        "minute",
        "minutes",
        # --- Nombres ---
        "deux",
        "trois",
        "quatre",
        "cinq",
        # --- Personnes/lieux génériques ---
        "personnes",
        "gens",
        "hommes",
        "femmes",
        "enfants",
        "ville",
        "villes",
        "region",
        "zone",
        "secteur",
        # --- Abstraits ---
        "question",
        "probleme",
        "solution",
        "projet",
        "plan",
        "mesure",
        "effet",
        "impact",
        "consequence",
        "resultat",
        "cause",
        "raison",
        # --- Géo génériques ---
        "europe",
        "europeen",
        "europeenne",
        "americain",
        "occidental",
        # --- News filler ---
        "informations",
        "article",
        "articles",
        "savoir",
        "retenir",
        "exclusif",
        "exclusive",
        "urgent",
        "breaking",
        "video",
        "photo",
        "photos",
        "images",
        "podcast",
        "interview",
        "analyse",
        "decryptage",
        "explications",
        "enquete",
        "dossier",
        "revele",
        "montre",
        "indique",
        "suggere",
        "affirme",
        "estime",
    ]
)


class ImportanceDetector:
    """Détecte les contenus objectivement importants.

    Ce module analyse les contenus pour identifier:
    1. Les articles provenant des feeds "À la Une" des sources de référence
    2. Les sujets tendance (couverts par ≥N sources distinctes)

    Attributes:
        similarity_threshold: Seuil de similarité Jaccard pour regrouper les titres (défaut: 0.4)
        min_sources_for_trending: Nombre minimum de sources pour qu'un sujet soit "trending" (défaut: 3)
    """

    def __init__(
        self, similarity_threshold: float = 0.4, min_sources_for_trending: int = 3
    ):
        """Initialise le détecteur d'importance.

        Args:
            similarity_threshold: Seuil de similarité Jaccard [0-1].
                0.4 = environ 40% des mots en commun.
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
        """Normalise un titre en ensemble de tokens.

        Transformations appliquées:
        1. Conversion en minuscules
        2. Suppression des accents
        3. Suppression de la ponctuation
        4. Tokenisation par espaces
        5. Filtrage des stop words
        6. Filtrage des tokens < 3 caractères

        Args:
            title: Titre brut de l'article

        Returns:
            Ensemble de tokens normalisés
        """
        if not title:
            return set()

        # Lowercase
        text = title.lower()

        # Remove accents (NFD decomposition puis filtrage des marques diacritiques)
        text = unicodedata.normalize("NFD", text)
        text = "".join(c for c in text if unicodedata.category(c) != "Mn")

        # Remove punctuation and numbers
        text = re.sub(r"[^\w\s]", " ", text)
        text = re.sub(r"\d+", "", text)

        # Tokenize and filter
        tokens = text.split()
        tokens = [t for t in tokens if len(t) >= 3 and t not in FRENCH_STOP_WORDS]

        return set(tokens)

    def jaccard_similarity(self, tokens_a: set[str], tokens_b: set[str]) -> float:
        """Calcule la similarité de Jaccard entre deux ensembles de tokens.

        Similarité de Jaccard = |A ∩ B| / |A ∪ B|

        Args:
            tokens_a: Premier ensemble de tokens
            tokens_b: Deuxième ensemble de tokens

        Returns:
            Score de similarité entre 0.0 (rien en commun) et 1.0 (identiques)
        """
        if not tokens_a or not tokens_b:
            return 0.0

        intersection = len(tokens_a & tokens_b)
        union = len(tokens_a | tokens_b)

        if union == 0:
            return 0.0

        return intersection / union

    def build_topic_clusters(
        self,
        contents: list[Content],
        similarity_threshold: float | None = None,
    ) -> list[TopicCluster]:
        """Cluster tous les contenus par similarité de titre.

        Retourne TOUS les clusters (y compris singletons). Chaque cluster
        représente un sujet potentiel pour le digest.

        Algorithme identique à detect_trending_clusters mais retourne
        la structure complète au lieu de filtrer sur le trending.

        Args:
            contents: Liste des contenus à analyser
            similarity_threshold: Seuil Jaccard override (default: self.similarity_threshold)

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

        # Phase 1: Clustering Jaccard (même algo que detect_trending_clusters)
        raw_clusters: list[dict] = []

        from app.services.recommendation.scoring_config import ScoringWeights

        for content in contents:
            tokens = self.normalize_title(content.title)
            if not tokens:
                continue

            # Minimum token constraint: very short titles become singletons
            if len(tokens) < ScoringWeights.TOPIC_CLUSTER_MIN_TOKENS:
                raw_clusters.append(
                    {
                        "tokens": tokens,
                        "contents": [content],
                    }
                )
                continue

            matched_cluster = None
            best_similarity = 0.0

            for cluster in raw_clusters:
                sim = self.jaccard_similarity(tokens, cluster["tokens"])
                if sim > best_similarity and sim >= threshold:
                    best_similarity = sim
                    matched_cluster = cluster

            if matched_cluster:
                matched_cluster["contents"].append(content)
                # Evolve cluster tokens with cap to prevent drift
                merged = matched_cluster["tokens"] | tokens
                if len(merged) <= ScoringWeights.TOPIC_CLUSTER_MAX_TOKENS:
                    matched_cluster["tokens"] = merged
            else:
                raw_clusters.append(
                    {
                        "tokens": tokens,
                        "contents": [content],
                    }
                )

        # Phase 2: Convertir en TopicCluster avec métadonnées
        topic_clusters: list[TopicCluster] = []

        for raw in raw_clusters:
            cluster_contents: list[Content] = raw["contents"]
            source_ids = {c.source_id for c in cluster_contents}

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
                    label="",  # Set par TopicSelector après scoring
                    tokens=raw["tokens"],
                    contents=cluster_contents,
                    source_ids=source_ids,
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
            if len(cluster.source_ids) >= self.min_sources_for_trending:
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
