"""Helpers partagés pour les surfaces de recommandation (feed, digest, essentiel).

Centralise les primitives qui étaient dupliquées avec valeurs divergentes :
- Score de couverture (perspectives multi-sources) : `compute_coverage_score`
- Diversification générique 1-par-clé : `diversify`
- Parse des entités nommées d'un article : `iter_entity_names`
"""

from app.services.recommendation.helpers.coverage_score import compute_coverage_score
from app.services.recommendation.helpers.diversification import diversify
from app.services.recommendation.helpers.entities import iter_entity_names
from app.services.recommendation.helpers.keyword_match import matches_word_boundary

__all__ = [
    "compute_coverage_score",
    "diversify",
    "iter_entity_names",
    "matches_word_boundary",
]
