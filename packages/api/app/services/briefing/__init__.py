"""Module Briefing pour le Top 3 quotidien.

Story 4.4: Top 3 Briefing Quotidien
Ce module contient les composants pour générer le briefing quotidien:
- ImportanceDetector: Détecte les contenus objectivement importants
- Top3Selector: Sélectionne les 3 meilleurs articles avec contraintes
"""

from app.services.briefing.importance_detector import ImportanceDetector
from app.services.briefing.top3_selector import Top3Selector

__all__ = [
    "ImportanceDetector",
    "Top3Selector",
]
