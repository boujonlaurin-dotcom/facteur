"""Module Briefing — détection de l'importance des clusters.

Le Top3Selector et le job daily_top3 ont été supprimés lors du cleanup
post-unification ; seul ImportanceDetector subsiste, réutilisé par le
pipeline éditorial pour le clustering de sujets.
"""

from app.services.briefing.importance_detector import ImportanceDetector

__all__ = [
    "ImportanceDetector",
]
