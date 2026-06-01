# Fix Flâner refresh cache

Corrige un ensemble de régressions mobiles autour de Flâner: refresh trop fréquent au retour premier plan, perte de filtres lors de rebuilds auth sans changement d'utilisateur, et collision potentielle entre caches `normal` / `serein`.

## Quoi
- extrait et teste la règle `shouldRefreshFlanerOnForeground()` avec un seuil de 30 minutes,
- stabilise `feedProvider` pour ignorer les rebuilds liés à la seule rotation JWT et conserver les filtres pour le même utilisateur,
- remet les filtres à zéro uniquement sur logout ou vrai changement d'utilisateur,
- sépare le cache feed par variante `normal` / `serein` avec fallback legacy pour `normal`,
- corrige `theme_provider_test.dart` pour l'API actuelle `AppThemeMode`.

## Pourquoi
- éviter des refresh Flâner inutiles en revenant rapidement dans l'app,
- empêcher la perte de contexte filtre lors de rebuilds auth sans impact fonctionnel,
- garantir qu'un cache `serein` ne pollue pas la vue normale, et inversement,
- débloquer `flutter analyze` pour permettre une PR conforme.

## Comment ça a été vérifié
- [x] Tests ciblés feed/lifecycle:
  - `flutter test test/app_lifecycle_test.dart test/features/feed/feed_provider_auth_filter_test.dart test/features/feed/feed_cache_service_test.dart test/features/feed/feed_refresh_recovery_test.dart test/features/feed/personalization_logic_test.dart`
- [ ] `flutter test`
  - Bloqué par des échecs hors diff dans `test/features/custom_topics/widgets/topic_chip_test.dart` et `test/features/custom_topics/widgets/topic_explorer_screen_test.dart`
- [ ] `flutter analyze`
  - Le `undefined_method` de `theme_provider_test.dart` est corrigé, mais `flutter analyze` reste rouge à cause de centaines d'`info`/`warning` historiques hors périmètre
- [x] Review finale du diff

## Zones à risque
- synchronisation différée via `scheduleMicrotask` entre owner/reset et provider de sélection,
- UX potentiellement plus stale sur retour premier plan < 30 min, choix volontaire pour réduire les refresh inutiles,
- persistance des filtres lors des rebuilds auth intermédiaires.
