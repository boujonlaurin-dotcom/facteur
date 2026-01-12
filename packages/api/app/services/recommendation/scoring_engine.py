from abc import ABC, abstractmethod
from typing import List, Set, Dict, Any, Optional
from uuid import UUID
import datetime
import structlog

from app.models.content import Content
from app.models.user import UserProfile
from app.models.enums import ContentStatus

logger = structlog.get_logger()

class ScoringContext:
    """Contexte passé à toutes les couches de scoring."""
    def __init__(
        self,
        user_profile: UserProfile,
        user_interests: Set[str],
        user_interest_weights: Dict[str, float],
        followed_source_ids: Set[UUID],
        user_prefs: Dict[str, Any],
        now: datetime.datetime
    ):
        self.user_profile = user_profile
        self.user_interests = user_interests
        self.user_interest_weights = user_interest_weights
        self.followed_source_ids = followed_source_ids
        self.user_prefs = user_prefs
        self.now = now
        
        # Diagnostics pour explicabilité
        self.reasons: Dict[UUID, Dict[str, Any]] = {}

    def add_reason(self, content_id: UUID, layer: str, score: float, details: str):
        if content_id not in self.reasons:
            self.reasons[content_id] = []
        self.reasons[content_id].append({
            "layer": layer,
            "score_contribution": score,
            "details": details
        })


class BaseScoringLayer(ABC):
    """Interface pour une couche de scoring."""
    
    @property
    @abstractmethod
    def name(self) -> str:
        pass

    @abstractmethod
    def score(self, content: Content, context: ScoringContext) -> float:
        """Retourne un score additif pour ce contenu."""
        pass


class ScoringEngine:
    """Moteur qui orchestre le calcul du score via plusieurs layers."""
    
    def __init__(self, layers: List[BaseScoringLayer]):
        self.layers = layers

    def compute_score(self, content: Content, context: ScoringContext) -> float:
        total_score = 0.0
        
        for layer in self.layers:
            try:
                layer_score = layer.score(content, context)
                total_score += layer_score
                
                # Optionnel: log debug si score significatif
                # if abs(layer_score) > 0.1:
                #     context.add_reason(content.id, layer.name, layer_score, "")
                    
            except Exception as e:
                logger.error("start_scoring_layer_error", layer=layer.name, error=str(e))
                # On ne bloque pas tout le scoring pour une erreur de layer
                continue
                
        return total_score
