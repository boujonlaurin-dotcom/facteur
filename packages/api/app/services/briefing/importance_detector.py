"""Module de détection d'importance pour le briefing quotidien.

Story 4.4: Top 3 Briefing Quotidien
Ce module détecte les contenus objectivement importants via:
1. Parsing des feeds "À la Une" des sources de référence
2. Clustering des titres par similarité Jaccard pour détecter les sujets tendance

Architecture: Ce module est DÉCOUPLÉ du ScoringEngine. Il consomme les contenus
bruts et produit des flags d'importance qui seront utilisés par Top3Selector.
"""

import re
import unicodedata
from typing import List, Set, Optional
from uuid import UUID

import structlog

from app.models.content import Content

logger = structlog.get_logger()

# Stop words français courants (à filtrer des titres)
FRENCH_STOP_WORDS = frozenset([
    "le", "la", "les", "un", "une", "des", "du", "de", "au", "aux",
    "ce", "ces", "cet", "cette", "mon", "ton", "son", "ma", "ta", "sa",
    "mes", "tes", "ses", "notre", "votre", "leur", "nos", "vos", "leurs",
    "qui", "que", "quoi", "dont", "où", "quel", "quelle", "quels", "quelles",
    "et", "ou", "mais", "donc", "or", "ni", "car", "pour", "par", "avec",
    "sans", "sous", "sur", "dans", "en", "à", "est", "sont", "a", "ont",
    "il", "elle", "ils", "elles", "on", "nous", "vous", "je", "tu",
    "se", "ne", "pas", "plus", "très", "aussi", "tout", "tous", "toute",
    "même", "autres", "autre", "entre", "après", "avant", "comme", "être",
    "faire", "fait", "dit", "peut", "faut", "doit", "si", "quand", "comment"
])


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
        self, 
        similarity_threshold: float = 0.4,
        min_sources_for_trending: int = 3
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

    def normalize_title(self, title: str) -> Set[str]:
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
        text = unicodedata.normalize('NFD', text)
        text = ''.join(c for c in text if unicodedata.category(c) != 'Mn')
        
        # Remove punctuation and numbers
        text = re.sub(r'[^\w\s]', ' ', text)
        text = re.sub(r'\d+', '', text)
        
        # Tokenize and filter
        tokens = text.split()
        tokens = [t for t in tokens if len(t) >= 3 and t not in FRENCH_STOP_WORDS]
        
        return set(tokens)

    def jaccard_similarity(self, tokens_a: Set[str], tokens_b: Set[str]) -> float:
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

    def detect_trending_clusters(
        self, 
        contents: List[Content]
    ) -> Set[UUID]:
        """Détecte les contenus faisant partie de sujets tendance.
        
        Algorithme de clustering simple:
        1. Pour chaque contenu, tokeniser le titre
        2. Comparer avec les clusters existants (similarité Jaccard)
        3. Si match >= seuil, ajouter au cluster existant
        4. Sinon, créer un nouveau cluster
        5. Retourner les contenus des clusters avec ≥N sources distinctes
        
        Args:
            contents: Liste des contenus à analyser
            
        Returns:
            Set des UUIDs des contenus faisant partie d'un sujet tendance
        """
        if not contents:
            return set()
        
        # Structure: List[{tokens: Set[str], contents: List[Content]}]
        clusters: List[dict] = []
        
        for content in contents:
            tokens = self.normalize_title(content.title)
            
            if not tokens:
                continue
            
            # Chercher un cluster existant avec similarité suffisante
            matched_cluster = None
            best_similarity = 0.0
            
            for cluster in clusters:
                sim = self.jaccard_similarity(tokens, cluster["tokens"])
                if sim > best_similarity and sim >= self.similarity_threshold:
                    best_similarity = sim
                    matched_cluster = cluster
            
            if matched_cluster:
                # Ajouter au cluster existant
                matched_cluster["contents"].append(content)
                # Optionnel: mettre à jour les tokens du cluster (union)
                # matched_cluster["tokens"] |= tokens
            else:
                # Créer un nouveau cluster
                clusters.append({
                    "tokens": tokens,
                    "contents": [content]
                })
        
        # Identifier les clusters "trending" (≥N sources distinctes)
        trending_content_ids: Set[UUID] = set()
        
        for cluster in clusters:
            # Compter les sources distinctes dans ce cluster
            source_ids = set(c.source_id for c in cluster["contents"])
            
            if len(source_ids) >= self.min_sources_for_trending:
                # Ce cluster est trending
                for content in cluster["contents"]:
                    trending_content_ids.add(content.id)
                    
                logger.debug(
                    "trending_cluster_detected",
                    cluster_size=len(cluster["contents"]),
                    source_count=len(source_ids),
                    sample_title=cluster["contents"][0].title[:50] if cluster["contents"] else ""
                )
        
        logger.info(
            "trending_detection_complete",
            total_contents=len(contents),
            total_clusters=len(clusters),
            trending_clusters=sum(
                1 for c in clusters 
                if len(set(x.source_id for x in c["contents"])) >= self.min_sources_for_trending
            ),
            trending_content_count=len(trending_content_ids)
        )
        
        return trending_content_ids

    def identify_une_contents(
        self, 
        contents: List[Content],
        une_guids: Set[str]
    ) -> Set[UUID]:
        """Identifie les contenus provenant des feeds "À la Une".
        
        Args:
            contents: Liste des contenus à analyser
            une_guids: Set des GUIDs des articles présents dans les feeds Une
            
        Returns:
            Set des UUIDs des contenus "À la Une"
        """
        une_content_ids: Set[UUID] = set()
        
        for content in contents:
            if content.guid in une_guids:
                une_content_ids.add(content.id)
        
        logger.info(
            "une_identification_complete",
            total_contents=len(contents),
            une_guids_count=len(une_guids),
            matched_count=len(une_content_ids)
        )
        
        return une_content_ids
