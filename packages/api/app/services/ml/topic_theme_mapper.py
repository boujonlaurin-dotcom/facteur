"""Mapping des topics ML (50-topics) vers les thèmes sources (8-themes taxonomy).

Permet de dériver content.theme depuis content.topics[0] après classification ML.
Le thème inféré est utilisé par le scoring pour améliorer la diversité du feed.
"""


# Les 8 thèmes valides de la taxonomie Facteur
VALID_THEMES: set[str] = {
    "tech", "society", "environment", "economy",
    "politics", "culture", "science", "international",
}


# Mapping exhaustif des 50 slugs ML → 8 thèmes broad
TOPIC_TO_THEME: dict[str, str] = {
    # Tech & Science
    "ai": "tech",
    "tech": "tech",
    "cybersecurity": "tech",
    "gaming": "tech",
    "privacy": "tech",
    "space": "science",
    "science": "science",
    # Société
    "politics": "politics",
    "economy": "economy",
    "work": "society",
    "education": "society",
    "health": "society",
    "justice": "society",
    "immigration": "society",
    "inequality": "society",
    "feminism": "society",
    "lgbtq": "society",
    "religion": "society",
    # Environnement
    "climate": "environment",
    "environment": "environment",
    "energy": "environment",
    "biodiversity": "environment",
    "agriculture": "environment",
    "food": "environment",
    # Culture
    "cinema": "culture",
    "music": "culture",
    "literature": "culture",
    "art": "culture",
    "media": "culture",
    "fashion": "culture",
    "design": "culture",
    # Lifestyle → mapped to closest broad theme
    "travel": "culture",
    "gastronomy": "culture",
    "sport": "culture",
    "wellness": "society",
    "family": "society",
    "relationships": "society",
    # Business
    "startups": "economy",
    "finance": "economy",
    "realestate": "economy",
    "entrepreneurship": "economy",
    "marketing": "economy",
    # International
    "geopolitics": "international",
    "europe": "international",
    "usa": "international",
    "africa": "international",
    "asia": "international",
    "middleeast": "international",
    # Autres
    "history": "culture",
    "philosophy": "culture",
    "factcheck": "society",
}


def infer_theme_from_topics(topics: list[str]) -> str | None:
    """Infère le thème broad depuis la liste de topics ML.

    Utilise le premier topic (score ML le plus élevé) pour dériver le thème.

    Args:
        topics: Liste ordonnée de topic slugs (par score décroissant)

    Returns:
        Theme slug (tech, society, etc.) ou None si aucun mapping trouvé
    """
    if not topics:
        return None
    top_topic = topics[0].lower().strip()
    return TOPIC_TO_THEME.get(top_topic)
