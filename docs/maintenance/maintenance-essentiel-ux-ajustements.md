# Maintenance — Ajustements UX/UI L'Essentiel, Sticky Header, Flamme & Météo

> Type : **Maintenance UI**. Lot de 5 ajustements indépendants sur l'écran
> L'Essentiel (interne *Flux Continu*) + 2 détails transverses (flamme streak,
> modal météo). Aucun changement backend / DB / Alembic. Plan confirmé PO.

## Décisions PO confirmées

- **Fold gated lecture** : une section dont les cartes « previewed » ne sont pas
  toutes lues ne se replie **jamais** automatiquement. Carte Essentiel = ses 5
  articles lus.
- **Flamme streak** : resize **uniquement** dans `StreakIndicator` (header
  d'accueil).
- **Météo jours suivants** : afficher le **max** en gros (quitte à le dupliquer
  avec la plage min/max).

## Changements

1. **Fold gated lecture** — nouveau prédicat `allPreviewArticlesRead(FluxSection)`
   dans `flux_continu_models.dart`, gaté aux 2 sites d'appel écran
   (`_maybeFoldSections`, `_markSectionsAboveAsScrolledPast`). Le repli manuel
   (`foldLocally`) reste non gaté.
2. **Grille déplacée** — `GrilleCtaCard` rendue juste après la section « Actus du
   jour » (`DigestTopicSection` `kind == essentiel`). Le sliver grille bas
   devient un fallback `if (!hasActus)`.
3. **Sticky header** — highlight sur le **texte** (style « Couverture médiatique »
   / `DiffTitle`), retrait du point et du wash arrondi pleine-chip.
4. **Flamme streak** — 16 → 22px (+40%) dans `StreakIndicator` (actif + loading).
5. **Modal météo** — `_DayRow` : max en gros (`fraunces`) + plage min/max
   conservée, asset météo 40 → 52px.

## Fichiers modifiés

| Fichier | Changement |
|---|---|
| `models/flux_continu_models.dart` | + `allPreviewArticlesRead()` |
| `screens/flux_continu_screen.dart` | gate fold ×2 ; déplacement Grille + fallback |
| `widgets/sticky_tab_bar.dart` | highlight texte + retrait points |
| `gamification/widgets/streak_indicator.dart` | flamme 16→22 |
| `widgets/weather_detail_sheet.dart` | `_DayRow` max gros + asset 52 |

## Tests

- `flux_continu_models_test.dart` — group `allPreviewArticlesRead`.
- Widget test placement Grille (Actus présent / absent / replié).
- `flutter analyze` propre + tests ciblés `flux_continu/` & `gamification/` verts.

## Statut

- [x] Plan confirmé PO
- [x] Change 1 — fold gated
- [x] Change 2 — Grille déplacée
- [x] Change 3 — sticky header highlight texte
- [x] Change 4 — flamme streak +40%
- [x] Change 5 — météo max gros
- [x] Tests ajoutés
- [ ] VERIFY (flutter analyze + tests ciblés)
- [ ] PR `--base main`
