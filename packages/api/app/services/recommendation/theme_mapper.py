"""Mapping entre source.theme et user_interests pour fix bug matching."""
from typing import Set
from app.models.source import Source

# Mapping : Source.theme (labels lisibles) → user_interest slugs
THEME_TO_USER_SLUGS = {
    "Tech & Futur": ["tech", "science", "tech & futur"],
    "Société & Climat": ["society", "environment", "société & climat", "societe & climat"],
    "Économie": ["economy", "business", "économie", "economie"],
    "Géopolitique": ["politics", "international", "géopolitique", "geopolitique"],
    "Culture & Idées": ["culture", "culture & idées", "culture & idees"],
}

def get_user_slugs_for_source(source: Source) -> Set[str]:
    """
    Retourne les user_interest slugs compatibles avec une source.
    
    Args:
        source: Instance Source avec theme en label lisible
        
    Returns:
        Set de slugs normalisés (ex: {"tech", "science"})
        
    Example:
        >>> source = Source(theme="Tech & Futur")
        >>> get_user_slugs_for_source(source)
        {'tech', 'science'}
    """
    # Si le thème de la source est None, retourner un set vide
    if not source.theme:
        return set()

    # Try exact match first
    mapped_slugs = THEME_TO_USER_SLUGS.get(source.theme, [])
    
    # If no match, try case-insensitive lookup (fallback)
    if not mapped_slugs:
        # Build normalized map on the fly (could be cached but dict is small)
        normalized_map = {k.lower().strip(): v for k, v in THEME_TO_USER_SLUGS.items()}
        mapped_slugs = normalized_map.get(source.theme.lower().strip(), [])

    return set(mapped_slugs)
