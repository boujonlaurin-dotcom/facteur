# PR — feat(widget): switch Essentiel/Flux + simplification header

## Summary

Refonte du widget Android pour intégrer le Flux (feed) en complément de l'Essentiel du jour, avec switch dans le header. Simplification visuelle et titres jusqu'à 4 lignes pour se rapprocher du style Google News / feed in-app.

- **Switch Essentiel ↔ Flux** dans le header (segmented control). Mode persisté localement (`widget_mode` SharedPreferences) via PendingIntent broadcast — le tap d'onglet écrit la clé puis `notifyAppWidgetViewDataChanged`.
- **Header simplifié** : suppression wordmark "Facteur", streak 🔥, refresh button, sous-titre.
- **Footer simplifié** : suppression du bouton "Ouvrir Facteur".
- **Cartes article** : `maxLines` 2 → 4, thumbnail 86dp inchangée à droite.
- **Flux scrollable** alimenté par le cache de `feedProvider` (jusqu'à 30 items, plafond Binder ~1 MB), poussé en debounced 1 s à chaque mise à jour de l'état du feed (default view, sans filtre). Thumbnails téléchargées seulement pour les 10 premiers items pour rester sous la limite IPC.
- **Tap article** : deeplink dépendant du mode — `digest/<id>` en Essentiel (inchangé), `feed/content/<id>` en Flux (route déjà gérée par `DeepLinkService` + redirect `routes.dart`).
- **Empty state Flux** : « Ouvre Facteur pour charger ton flux » (cold-start friendly, le widget se peuple en < 1 s dès que `feedProvider` charge).

Pas d'iOS (aucune extension widget iOS aujourd'hui). Pas de fetch réseau natif.

## Test plan

- [x] `flutter test test/core/services/widget_service_test.dart` — 9/9 ✅ (Digest + nouveau Feed serialization)
- [x] `flutter test test/core/services/deep_link_service_test.dart` — 10/10 ✅ (route `feed/content/<id>` validée)
- [x] `flutter analyze lib/core/services/widget_service.dart lib/features/feed/providers/feed_provider.dart` — 0 erreurs, 0 warnings/infos imputables aux changements
- [ ] **Test manuel Android** (à effectuer par le reviewer ou en QA) :
  - Header simplifié, segmented control [Essentiel | Flux] uniquement
  - Tap "Flux" → liste bascule, scrollable, deeplink `feed/content/<id>`
  - Tap "Essentiel" → retour aux 5 articles digest, deeplink `digest/<id>`
  - Mode persisté après kill app
  - Cold-start Flux → empty state puis populé après ouverture app
  - Titres longs : jusqu'à 4 lignes sans truncation, ellipsize au-delà
  - Vérifier sur Samsung OneUI si dispo

## Hors-scope

- Pas d'iOS widget extension (n'existe pas).
- Pas de fetch réseau natif (le widget reflète le cache app).
- Pas de pull-to-refresh / loading spinner dans le widget (incompatible RemoteViews).

## Notes

- Test pré-existant `feed_refresh_undo_banner_test.dart` "tapping Annuler while auto-dismiss is animating" échoue sur la branche, **avant** comme **après** mes changements (vérifié via `git stash` → `flutter test` → même échec). Hors scope.

## Story / Doc

- [docs/stories/core/widget.4.essentiel-flux-switch.story.md](../docs/stories/core/widget.4.essentiel-flux-switch.story.md)
