# Story: Widget Android — Flux iter 2 (typo, images off, profondeur, métriques)

## Contexte

Suite à `widget.4.essentiel-flux-switch` (#580), Laurin veut affiner le mode **Flux** :

- **Lisibilité** : titres plus grands (21sp), poids regular (pas medium ni bold) — Flux ET Essentiel.
- **Densité** : retirer les thumbnails et les numéros préfixes (`1 — Topic`) en Flux. Essentiel garde le rank et la vignette.
- **Profondeur** : passer de 30 à **80 items** côté Flux pour permettre un vrai scroll, sans loadMore depuis le widget (préchargement Flutter, buffer isolé du state in-app).
- **Mesure** : exposition réelle = **scroll max atteint** dans le widget, flushé en event PostHog au prochain foreground app. CTR widget→app déjà couvert par `widget_app_opened` / `widget_article_opened`.
- **Bug deeplink Flux→article** : `deep_link_service.dart::parse` n'extrait l'ID que pour `host=digest` ; `feed/content/<id>` retombe sur `/feed`. Fix dans cette même PR.

Contraintes structurelles (déjà en place) :

- Le widget tourne dans le process du **launcher** (`RemoteViewsService`) — pas d'appel réseau ni de PostHog direct depuis ce process. Toute télémétrie passe par `SharedPreferences` (`home_widget`) puis est flushée par l'app au foreground.
- Binder IPC ≈ 1 MB pour le payload `RemoteViews`. Sans thumbnails, on tient ≥ 80 articles.
- `feedProvider._scheduleWidgetPush` ne mirror que la vue **non filtrée** (déjà debounced 1 s + signature-guarded).

## Décisions UX validées (utilisateur, 2026-05-06)

- **Cap Flux** : 80 items, **0 thumbnail**.
- **Préfetch côté Flutter** : Option A — buffer isolé qui ne mute pas `state.value.items` (pas de side-effect sur le feed in-app).
- **Police** : 21sp `sans-serif` regular pour `row_title`, sur les deux modes.
- **Numéro Flux** : retiré (titre topic seul). Essentiel inchangé.
- **Tracking scroll** : SharedPreferences `widget_flux_max_scroll_position` mis à jour depuis `getViewAt`, flushé en event PostHog `widget_flux_scroll` au prochain foreground.
- **Deeplink Flux→article** : fix de `deep_link_service.dart::parse`.

## Tâches

### Track 1 — Police (XML)

- [x] `apps/mobile/android/app/src/main/res/layout/widget_article_row.xml`
  - [x] `R.id.row_title` : `textSize` 20sp → 21sp, retirer `textStyle="bold"`, retirer `fontFamily="sans-serif-medium"`.

### Track 2 — Kotlin (RemoteViews + tracking)

- [x] `apps/mobile/android/app/src/main/kotlin/com/example/facteur/WidgetRendering.kt`
  - [x] `MAX_ROWS_FLUX` 30 → 80.
- [x] `apps/mobile/android/app/src/main/kotlin/com/example/facteur/FacteurWidgetService.kt`
  - [x] `getViewAt` : en mode Flux, masquer `row_thumbnail` sans appeler `loadBitmap` ; topic line = `topicSegment` seul (pas de `${rank} — `).
  - [x] Tracking scroll : `private var maxPositionSeen = -1` ; mise à jour dans `getViewAt` ; flush idempotent dans `onDataSetChanged()` (en début) et `onDestroy()`. Écriture des 3 clés `widget_flux_*` uniquement si nouvelle position dépasse l'existante.

### Track 3 — Flutter (data + analytics)

- [x] `apps/mobile/lib/core/services/widget_service.dart`
  - [x] `_maxFeedArticles` 30 → 80, suppression de `_maxFeedThumbnails` (toujours 0).
  - [x] `_serializeFeedItem` : ne plus tenter `_downloadIfPresent(item.thumbnailUrl, …)`. Logo source conservé.
  - [x] Nouvelle méthode `readAndClearFluxScrollMetric()` lit + clear les 3 clés `widget_flux_*`.
- [x] `apps/mobile/lib/features/feed/providers/feed_provider.dart`
  - [x] `_scheduleWidgetPush` : `items.take(30) → items.take(80)`.
  - [x] `_prefetchForWidget(initialItems)` : appels `repository.getFeed(page: …)` directs (sans toucher au state in-app ni à `_hasNext`/`_page`) jusqu'à 80 items ou plus de pages, puis `_scheduleWidgetPush(buffer)`. Flag `_widgetDepthFillInProgress` pour éviter les chaînes concurrentes. Abort si filtre devient actif.
  - [x] Trigger : `unawaited(_prefetchForWidget(items))` à la fin de `build()` (cache hit + fetch initial).
- [x] `apps/mobile/lib/core/services/analytics_service.dart`
  - [x] `trackWidgetFluxScrollSession({maxPosition, totalCount, at})` → event `widget_flux_scroll` (Supabase + PostHog) avec `scroll_pct = (maxPosition+1)/totalCount` clampé.
- [x] `apps/mobile/lib/app.dart`
  - [x] `_FacteurAppState with WidgetsBindingObserver` : flush au cold start (post-frame) + `didChangeAppLifecycleState(resumed)`.

### Track 4 — Fix deeplink Flux→article

- [x] `apps/mobile/lib/core/services/deep_link_service.dart`
  - [x] `parse()` : extraire `feed/content/<id>` AVANT le fallback `RoutePaths.feed`. Couvre les deux formats Android (host=feed et host="" + segments.first=feed).

### Track 5 — Tests

- [x] `apps/mobile/test/core/services/widget_service_test.dart`
  - [x] Cap 30 → 80, assert `thumbnail_path == ''` pour tous les items Flux.
- [x] `apps/mobile/test/core/services/deep_link_service_test.dart`
  - [x] `feed/content/<id>` → `target=article`, `route=/feed/content/<id>`, `articleId`, `position`, `topicId`.
  - [x] `feed/content/<id>` avec host vide → idem.
  - [x] `feed` seul → `target=feed`.
  - [x] `feed/content/` (id manquant) → `target=feed` (fallback).

### Track 6 — VERIFY

- [ ] `flutter test` (apps/mobile)
- [ ] `flutter analyze`
- [ ] Test manuel device Android : police, pas d'images, pas de numéros Flux, scroll > 30, deeplink Flux→article ouvre le reader, event `widget_flux_scroll` au foreground.

## Critères d'acceptation

- [ ] Flux : ≤ 80 articles, 0 thumbnail, pas de préfixe rank dans la ligne topic, titres regular 21sp.
- [ ] Essentiel : inchangé (rank, thumbnail, badge "À la Une"), titre regular 21sp.
- [ ] Tap Flux article ouvre `/feed/content/<id>` (le reader), pas `/feed`.
- [ ] Event `widget_flux_scroll` fire au foreground app, props `{max_position, total_count, scroll_pct, at_iso}`.
- [ ] Pas de side-effect sur le feed in-app (pages 2-3 du préfetch ne s'affichent pas dans la liste user).
- [ ] PR `--base main`, CI verte, `flutter analyze` clean.

## Hors-scope

- Pas d'iOS.
- Pas de loadMore depuis le widget.
- Pas de tracking par-row (perf).
- Pas de modification du flux Essentiel (hors typo titre).

## Fichiers modifiés

- `apps/mobile/android/app/src/main/res/layout/widget_article_row.xml`
- `apps/mobile/android/app/src/main/kotlin/com/example/facteur/WidgetRendering.kt`
- `apps/mobile/android/app/src/main/kotlin/com/example/facteur/FacteurWidgetService.kt`
- `apps/mobile/lib/core/services/widget_service.dart`
- `apps/mobile/lib/features/feed/providers/feed_provider.dart`
- `apps/mobile/lib/core/services/analytics_service.dart`
- `apps/mobile/lib/core/services/deep_link_service.dart`
- `apps/mobile/lib/app.dart`
- `apps/mobile/test/core/services/widget_service_test.dart`
- `apps/mobile/test/core/services/deep_link_service_test.dart`
