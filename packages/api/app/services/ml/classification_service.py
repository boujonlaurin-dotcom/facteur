"""
ClassificationService: Zero-shot classification using mDeBERTa.

Part of Story 4.2-US-3 - ML classification in worker.
"""

from __future__ import annotations

import asyncio
import time
from typing import TYPE_CHECKING

import structlog

from app.config import get_settings

if TYPE_CHECKING:
    from transformers import Pipeline

log = structlog.get_logger()


class ClassificationService:
    """
    Service de classification zero-shot utilisant CamemBERT.
    
    Classifie les titres et descriptions d'articles dans la taxonomie 50-topics.
    Le modèle est chargé en lazy-loading uniquement si ML_ENABLED=true.
    """
    
    # 50 labels candidats en français pour la classification zero-shot
    CANDIDATE_LABELS_FR: list[str] = [
        # Tech & Science
        "intelligence artificielle",
        "technologie",
        "cybersécurité",
        "jeux vidéo",
        "espace et astronomie",
        "science",
        "données et vie privée",
        # Société
        "politique",
        "économie",
        "emploi et travail",
        "éducation",
        "santé",
        "justice et droit",
        "immigration",
        "inégalités sociales",
        "féminisme et droits des femmes",
        "LGBTQ+",
        "religion",
        # Environnement
        "climat",
        "environnement",
        "énergie",
        "biodiversité",
        "agriculture",
        "alimentation",
        # Culture
        "cinéma",
        "musique",
        "littérature",
        "art",
        "médias",
        "mode",
        "design",
        # Lifestyle
        "voyage",
        "gastronomie",
        "sport",
        "bien-être",
        "famille et parentalité",
        "relations et amour",
        # Business
        "startups",
        "finance",
        "immobilier",
        "entrepreneuriat",
        "marketing",
        # International
        "géopolitique",
        "Europe",
        "États-Unis",
        "Afrique",
        "Asie",
        "Moyen-Orient",
        # Autres
        "histoire",
        "philosophie",
        "fact-checking",
    ]
    
    # Mapping des labels français vers les slugs normalisés
    LABEL_TO_SLUG: dict[str, str] = {
        "intelligence artificielle": "ai",
        "technologie": "tech",
        "cybersécurité": "cybersecurity",
        "jeux vidéo": "gaming",
        "espace et astronomie": "space",
        "science": "science",
        "données et vie privée": "privacy",
        "politique": "politics",
        "économie": "economy",
        "emploi et travail": "work",
        "éducation": "education",
        "santé": "health",
        "justice et droit": "justice",
        "immigration": "immigration",
        "inégalités sociales": "inequality",
        "féminisme et droits des femmes": "feminism",
        "LGBTQ+": "lgbtq",
        "religion": "religion",
        "climat": "climate",
        "environnement": "environment",
        "énergie": "energy",
        "biodiversité": "biodiversity",
        "agriculture": "agriculture",
        "alimentation": "food",
        "cinéma": "cinema",
        "musique": "music",
        "littérature": "literature",
        "art": "art",
        "médias": "media",
        "mode": "fashion",
        "design": "design",
        "voyage": "travel",
        "gastronomie": "gastronomy",
        "sport": "sport",
        "bien-être": "wellness",
        "famille et parentalité": "family",
        "relations et amour": "relationships",
        "startups": "startups",
        "finance": "finance",
        "immobilier": "realestate",
        "entrepreneuriat": "entrepreneurship",
        "marketing": "marketing",
        "géopolitique": "geopolitics",
        "Europe": "europe",
        "États-Unis": "usa",
        "Afrique": "africa",
        "Asie": "asia",
        "Moyen-Orient": "middleeast",
        "histoire": "history",
        "philosophie": "philosophy",
        "fact-checking": "factcheck",
    }
    
    def __init__(self) -> None:
        """Initialise le service. Charge le modèle seulement si ML_ENABLED=true."""
        self.classifier: Pipeline | None = None
        self._model_loaded = False
        
        settings = get_settings()
        if settings.ml_enabled:
            self._load_model()
    
    def _load_model(self) -> None:
        """Charge le pipeline de classification zero-shot."""
        if self._model_loaded:
            return
        
        log.info("classification_service.loading_model", model="MoritzLaurer/mDeBERTa-v3-base-xnli-multilingual-nli-2mil7")
        
        try:
            from transformers import pipeline
            
            # Use mDeBERTa multilingual model trained for NLI/zero-shot classification
            # This model supports French and is specifically trained for this task
            # device=-1 forces CPU usage
            self.classifier = pipeline(
                task="zero-shot-classification",
                model="MoritzLaurer/mDeBERTa-v3-base-xnli-multilingual-nli-2mil7",
                device=-1,
            )
            self._model_loaded = True
            log.info("classification_service.model_loaded")
            
        except Exception as e:
            log.error("classification_service.load_error", error=str(e))
            raise
    
    async def classify_async(
        self,
        title: str,
        description: str = "",
        top_k: int = 3,
        threshold: float = 0.3,
    ) -> list[str]:
        """
        Async wrapper for classification.
        Runs the blocking classifier in thread pool to not block event loop.
        
        Args:
            title: Titre de l'article
            description: Description/résumé optionnel
            top_k: Nombre maximum de topics à retourner (défaut: 3)
            threshold: Score minimum pour inclure un topic (défaut: 0.3)
            
        Returns:
            Liste des slugs de topics (ex: ['ai', 'tech', 'startups'])
        """
        if not self.classifier:
            log.warning("classification_service.classifier_not_loaded")
            return []
        
        loop = asyncio.get_event_loop()
        return await loop.run_in_executor(
            None,
            self._classify_sync,
            title,
            description,
            top_k,
            threshold,
        )

    def classify(
        self,
        title: str,
        description: str = "",
        top_k: int = 3,
        threshold: float = 0.3,
    ) -> list[str]:
        """
        Classifie un article basé sur son titre et sa description (synchrone).
        
        Note: Pour usage dans async contexts, préférer classify_async().
        
        Args:
            title: Titre de l'article
            description: Description/résumé optionnel
            top_k: Nombre maximum de topics à retourner (défaut: 3)
            threshold: Score minimum pour inclure un topic (défaut: 0.3)
            
        Returns:
            Liste des slugs de topics (ex: ['ai', 'tech', 'startups'])
        """
        return self._classify_sync(title, description, top_k, threshold)
    
    def _classify_sync(
        self,
        title: str,
        description: str,
        top_k: int,
        threshold: float,
    ) -> list[str]:
        """
        Synchronous classification (runs in thread pool).
        
        Args:
            title: Titre de l'article
            description: Description/résumé optionnel
            top_k: Nombre maximum de topics à retourner
            threshold: Score minimum pour inclure un topic
            
        Returns:
            Liste des slugs de topics
        """
        if not self.classifier:
            log.warning("classification_service.classifier_not_loaded")
            return []
        
        # Combine titre et description pour plus de contexte
        text = f"{title}. {description}".strip() if description else title
        
        if not text:
            return []
        
        try:
            start_time = time.time()
            
            result = self.classifier(
                text,
                candidate_labels=self.CANDIDATE_LABELS_FR,
                multi_label=True,
            )
            
            elapsed_ms = (time.time() - start_time) * 1000
            
            # Extrait les labels avec score > threshold
            topics: list[str] = []
            for label, score in zip(result["labels"], result["scores"]):
                if score >= threshold and len(topics) < top_k:
                    slug = self.LABEL_TO_SLUG.get(label)
                    if slug:
                        topics.append(slug)
            
            log.debug(
                "classification_service.classified",
                text=text[:100],
                topics=topics,
                elapsed_ms=round(elapsed_ms, 2),
            )
            
            return topics
            
        except Exception as e:
            log.error("classification_service.classify_error", error=str(e))
            return []
    
    def is_ready(self) -> bool:
        """Retourne True si le modèle est chargé et prêt."""
        return self._model_loaded and self.classifier is not None
    
    def get_stats(self) -> dict:
        """
        Get service statistics for monitoring.
        
        Returns:
            Dict avec les stats du service de classification
        """
        return {
            "model_loaded": self._model_loaded,
            "classifier_ready": self.classifier is not None,
            "model_name": "MoritzLaurer/mDeBERTa-v3-base-xnli-multilingual-nli-2mil7",
            "candidate_labels_count": len(self.CANDIDATE_LABELS_FR),
            "device": "CPU",
        }


# Singleton instance (lazy-loaded)
_classification_service: ClassificationService | None = None


def get_classification_service() -> ClassificationService:
    """Retourne l'instance singleton du service de classification."""
    global _classification_service
    if _classification_service is None:
        _classification_service = ClassificationService()
    return _classification_service
