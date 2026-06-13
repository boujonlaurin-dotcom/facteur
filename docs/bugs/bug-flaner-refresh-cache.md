# Bug — Flâner refresh/cache auth rebuild regressions

## Contexte
- Le retour au premier plan sur l'onglet Flâner déclenchait un refresh trop agressif.
- Les rebuilds du `feedProvider` liés à l'auth pouvaient réinitialiser des filtres sans changement réel d'utilisateur.
- Le cache local du feed par défaut ne séparait pas explicitement toutes les variantes utiles du mode normal vs `serein`.
- `flutter analyze` était en plus bloqué par un test thème obsolète, hors diff fonctionnel.

## Décisions d'implémentation
- Extraire la règle de refresh foreground de Flâner dans `shouldRefreshFlanerOnForeground()` avec un seuil de `30 minutes`, testée isolément.
- Restreindre l'observation auth du `feedProvider` aux champs qui changent réellement l'accès au feed, pour éviter les rebuilds sur rotation JWT seule.
- Préserver la sélection de filtres pour un même utilisateur, et la remettre à zéro uniquement sur logout ou vrai changement d'utilisateur.
- Séparer le cache feed par variante `normal` / `serein`, en gardant la lecture legacy `feed:{userId}` pour le mode normal.
- Corriger le test thème pour refléter l'API actuelle `AppThemeMode` / `commitThemeMode`.

## Fichiers principaux
- `apps/mobile/lib/app.dart`
- `apps/mobile/lib/features/feed/providers/feed_preload_provider.dart`
- `apps/mobile/lib/features/feed/providers/feed_provider.dart`
- `apps/mobile/lib/features/feed/services/feed_cache_service.dart`
- `apps/mobile/test/app_lifecycle_test.dart`
- `apps/mobile/test/features/feed/feed_provider_auth_filter_test.dart`
- `apps/mobile/test/features/settings/theme_provider_test.dart`

## Vérification
- Ciblé:
  - `flutter test test/app_lifecycle_test.dart test/features/feed/feed_provider_auth_filter_test.dart test/features/feed/feed_cache_service_test.dart test/features/feed/feed_refresh_recovery_test.dart test/features/feed/personalization_logic_test.dart`
- Global mobile à exécuter avant PR:
  - `flutter test`
  - `flutter analyze`

## Risques revus
- Race potentielle autour des `scheduleMicrotask` de sync Riverpod: acceptable tant que la mutation différée reste limitée au reset/owner sync.
- Risque de stale UX sur Flâner: volontairement réduit via refresh au retour premier plan seulement si `elapsed == null` ou `>= 30 min`.
- Risque de collision cache entre modes feed: couvert par les clés variantes + tests de séparation.
