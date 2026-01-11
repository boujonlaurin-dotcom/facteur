"""Estimation de durée de lecture."""

import re
from typing import Optional


def estimate_reading_time(
    text: str,
    words_per_minute: int = 200,
) -> int:
    """
    Estime le temps de lecture d'un texte en secondes.
    
    Args:
        text: Le texte à analyser
        words_per_minute: Vitesse de lecture moyenne (défaut: 200 WPM)
    
    Returns:
        Durée estimée en secondes
    """
    if not text:
        return 300  # 5 minutes par défaut

    # Nettoyer le HTML si présent
    clean_text = re.sub(r"<[^>]+>", " ", text)

    # Compter les mots
    words = len(clean_text.split())

    # Calculer le temps en minutes puis convertir en secondes
    minutes = words / words_per_minute
    seconds = int(minutes * 60)

    # Minimum 60 secondes, maximum 1 heure
    return max(60, min(seconds, 3600))


def format_duration(seconds: int) -> str:
    """
    Formate une durée en secondes en string lisible.
    
    Examples:
        - 120 -> "2 min"
        - 3600 -> "1h"
        - 5400 -> "1h 30min"
    """
    if seconds < 60:
        return f"{seconds}s"

    minutes = seconds // 60
    hours = minutes // 60
    remaining_minutes = minutes % 60

    if hours == 0:
        return f"{minutes} min"
    elif remaining_minutes == 0:
        return f"{hours}h"
    else:
        return f"{hours}h {remaining_minutes}min"

