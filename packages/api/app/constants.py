"""Product constants — Story 22.1 et au-delà.

Constantes produit partagées (cap, seuils, defaults). Distinct de `app/config.py`
qui porte la config d'environnement (`Settings` pydantic_settings). Ces valeurs
sont hard-codées pour rester en phase avec le mobile (constante miroir
`kFavoriteCap` côté Flutter, cf. plan 22.1).
"""

FAVORITE_CAP: int = 3
"""Cap dur du nombre de favoris par catégorie (intérêts vs sources, séparés).

Story 22.1 — décision PO 2026-05-15 : cap=3, hard-coded partagé serveur+client,
modifié par redeploy. Cap appliqué séparément aux intérêts (Thèmes+Sujets) et
aux Sources.
"""
