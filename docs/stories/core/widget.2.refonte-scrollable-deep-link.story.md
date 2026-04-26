# Story: Widget Android — Refonte scrollable + fix deep link + instrumentation

## Contexte

Le widget actuel (cf. `widget.1.android-home-widget.md`) souffre de 3 défauts critiques :

1. **Bug deep link** : taper sur le widget ouvre l'app sur "Page non trouvée: io.supabase.facteur://digest/" car aucun handler `app_links` n'est wiré côté Flutter — GoRouter reçoit l'URI brut.
2. **Vide chez certains utilisateurs** : `WidgetService.updateWidget()` n'est appelé qu'après un fetch digest réussi. Users qui posent le widget sans ouvrir l'app voient un placeholder figé.
3. **Design désaligné** : 2 cartes côte-à-côte non scrollables, aucun rang/catégorie/badge "À la Une"/source logos/temps comme dans le vrai Essentiel.

**Objectif** : widget fonctionnel, scrollable (5 articles), aligné Essentiel, instrumenté PostHog. Android-only (iOS sera fait plus tard).

## Décisions UX validées

- Tap sur article → reader direct (`/feed/content/:id`)
- Liste verticale scrollable façon Essentiel : image 60×60 + titre 2 lignes + source + temps
- Refonte en 1 seule PR
- iOS hors scope (aucun WidgetExtension n'existe)

## Architecture cible

### Tap article
```
Widget row tap → PendingIntent ACTION_VIEW
  uri = io.supabase.facteur://digest/<contentId>?pos=<n>&topicId=<id>
  → MainActivity (singleTop)
  → DeepLinkService (NOUVEAU, app_links package)
  → GoRouter.go('/feed/content/<id>')
  → ContentDetailScreen
```

### Données
```
DigestNotifier → WidgetService.updateWidget(digest)
  → HomeWidget.saveWidgetData('articles_json', JSON 5 articles) [NOUVEAU]
  → AppWidgetProvider.onUpdate
  → setRemoteAdapter(ListView, FacteurWidgetService) [NOUVEAU]
  → FacteurWidgetRemoteViewsFactory parse JSON → 5 rows
```

## Tâches

### 1. Setup
- [ ] Ajouter `app_links` à `pubspec.yaml`
- [ ] `flutter pub get`

### 2. Deep link routing (P0)
- [ ] Créer `lib/core/services/deep_link_service.dart` (singleton, listen `AppLinks().uriLinkStream` + `getInitialAppLink`)
- [ ] Mapper `digest`, `digest/<id>`, `feed`, ignorer `login-callback`
- [ ] Bootstrap dans `app.dart` après init router
- [ ] Stocker URI pendant si user non auth, rejouer après login
- [ ] Tests `deep_link_service_test.dart`

### 3. WidgetService refonte
- [ ] Sérialiser 5 articles JSON (id, rank, topic_label, is_main, title, source_name, source_logo_path, thumbnail_path, perspective_count, published_at_iso)
- [ ] Ajouter clé `articles_updated_at` (epoch ms)
- [ ] Méthode `clear()` (appelée au logout)
- [ ] Méthode `initWidgetIfNeeded()` (placeholder JSON si vide au boot)
- [ ] Tests `widget_service_test.dart`

### 4. Android scrollable widget
- [ ] `FacteurWidgetService.kt` (RemoteViewsService)
- [ ] `FacteurWidgetRemoteViewsFactory.kt` (parse JSON, getViewAt, fillInIntent article_id)
- [ ] `widget_article_row.xml` (rang | catégorie + titre 2 lignes + source + +N + temps | image 60×60)
- [ ] `widget_loading_view.xml`
- [ ] `colors.xml` palette Facteur
- [ ] Refonte `facteur_widget.xml` (header + ListView + footer "Ouvrir Facteur")
- [ ] Refonte `FacteurWidget.kt` (setRemoteAdapter + setPendingIntentTemplate + notifyAppWidgetViewDataChanged)
- [ ] Déclarer `FacteurWidgetService` dans `AndroidManifest.xml`

### 5. Empty/stale state
- [ ] Côté Flutter : `initWidgetIfNeeded()` au boot authenticated
- [ ] Côté Kotlin : row placeholder si JSON absent ou parse fail
- [ ] Côté Kotlin : bandeau "Mets à jour ton essentiel" si `articles_updated_at` > 36h

### 6. Instrumentation PostHog
- [ ] `trackWidgetPinRequested` / `trackWidgetPinDismissed` dans `analytics_service.dart`
- [ ] `trackWidgetAppOpened(target, articleId?, position?, topicId?)` 
- [ ] `trackWidgetArticleOpened` (alias funnel)
- [ ] Capture depuis `DeepLinkService` + `widget_pin_nudge.dart`

### 7. Logout cleanup
- [ ] `AuthStateNotifier.signOut()` appelle `WidgetService.clear()`

### 8. Tests + verify
- [ ] `flutter test` (incl. nouveaux tests)
- [ ] `flutter analyze`
- [ ] Build APK debug

## Fichiers (à finaliser à la fin)

### Flutter (NEW)
- `lib/core/services/deep_link_service.dart`
- `test/core/services/deep_link_service_test.dart`
- `test/core/services/widget_service_test.dart`

### Flutter (MODIFIED)
- `pubspec.yaml`
- `lib/core/services/widget_service.dart`
- `lib/core/services/analytics_service.dart`
- `lib/app.dart`
- `lib/core/auth/auth_state.dart`
- `lib/features/digest/widgets/widget_pin_nudge.dart`

### Android (NEW)
- `android/app/src/main/kotlin/com/example/facteur/FacteurWidgetService.kt`
- `android/app/src/main/kotlin/com/example/facteur/FacteurWidgetRemoteViewsFactory.kt`
- `android/app/src/main/res/layout/widget_article_row.xml`
- `android/app/src/main/res/layout/widget_loading_view.xml`

### Android (MODIFIED)
- `android/app/src/main/kotlin/com/example/facteur/FacteurWidget.kt`
- `android/app/src/main/res/layout/facteur_widget.xml`
- `android/app/src/main/res/values/colors.xml`
- `android/app/src/main/AndroidManifest.xml`

## Verification (test plan E2E)

1. Build APK debug, install
2. Add widget — placeholder OK
3. Login + digest fetch — widget se met à jour, 5 articles, scroll fluide
4. Tap header → `/digest`
5. Tap row article → `/feed/content/<id>` directement
6. Tap "Ouvrir Facteur" → `/digest`
7. Cold start tap widget → routing différé après auto-login
8. Logout → widget redevient placeholder
9. PostHog Live → events `widget_app_opened`, `widget_article_opened`, `widget_pin_requested`

## Risques

- `app_links` peut intercepter `io.supabase.facteur://login-callback` → DeepLinkService doit explicitement ignorer ce path
- Backward-compat OK : anciennes clés SharedPrefs simplement ignorées

## Status

- [x] Implémentation (toutes tasks 1-7 ✓)
- [x] Tests unitaires passing (13/13 — DeepLinkService 8/8 + WidgetService 5/5)
- [ ] PR créée
- [ ] E2E manuel sur device Android (build APK requis — pas de SDK Android local)
