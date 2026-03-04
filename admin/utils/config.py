"""Seuils d'alerte et constantes pour le dashboard Facteur."""

# --- Source Health ---
SOURCE_STALE_MULTIPLIER_WARNING = 2   # delta <= avg_interval * 2 = OK
SOURCE_STALE_MULTIPLIER_CRITICAL = 4  # delta <= avg_interval * 4 = Warning, > = KO
SOURCE_DEFAULT_INTERVAL_HOURS = 24    # Fallback si pas d'historique

# --- User Activity ---
USER_ACTIVE_HOURS = 24       # < 24h = Actif (vert)
USER_SLOWING_DAYS = 7        # < 7j = Ralenti (jaune)
USER_INACTIVE_DAYS = 7       # > 7j = Inactif (rouge)
HEALTHY_ARTICLES_PER_WEEK = 3

# --- Feed Quality ---
DIVERSITY_SCORE_WARNING = 0.3
FRESHNESS_HOURS_WARNING = 48
TOP_SOURCE_PCT_WARNING = 50
MIN_ARTICLES_SERVED_24H = 5

# --- Curation ---
CURATION_LABELS = ("good", "bad", "missing")
