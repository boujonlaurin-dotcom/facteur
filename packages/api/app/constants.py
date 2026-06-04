"""Product constants — Story 22.1 et au-delà.

Constantes produit partagées (cap, seuils, defaults). Distinct de `app/config.py`
qui porte la config d'environnement (`Settings` pydantic_settings). Ces valeurs
sont hard-codées pour rester en phase avec le mobile (constante miroir
`kFavoriteCap` côté Flutter, cf. plan 22.1).
"""

FAVORITE_CAP: int = 5
"""Cap d'affichage de la « Tournée du jour » (Story 22.2 — révision 2026-05-18).

N'est PLUS un cap dur : l'utilisateur peut avoir > 5 favoris ; seuls les 5
premiers (ordre `position` modifiable) sont retenus pour la Tournée du jour.
Conservé sous le nom `FAVORITE_CAP` pour compat des imports ; sémantiquement
équivalent à `DAILY_TOUR_CAP`. Mirror mobile : `dailyTourCap` dans
`apps/mobile/lib/config/constants.dart`.
"""

MIN_BACKFILL_FAVORITES: int = 2
"""Cible minimum de favoris par user après backfill migration 22a1.

Story 22.1 — décision PO 2026-05-16 : tout user existant doit avoir ≥ 2
favoris pour que la tournée du jour (PR2) soit non-vide. Inférieur à
FAVORITE_CAP (5) pour laisser de la place à la promo mobile post-migration
(sync `theme_priority_*` SharedPrefs → POST favoris).
"""

CANONICAL_THEME_SLUGS: list[str] = [
    "tech",
    "science",
    "society",
    "politics",
    "economy",
    "environment",
    "culture",
    "international",
    "sport",
]
"""Les 9 macro-thèmes Facteur (slugs API). Source mirror de
`macroThemeToApiSlug` côté mobile (`apps/mobile/lib/config/topic_labels.dart`).
Utilisé en dernier recours par le backfill 22a1 si le user n'a aucun signal
(les 2 premiers — tech, science — sont sélectionnés pour atteindre
MIN_BACKFILL_FAVORITES).
"""
