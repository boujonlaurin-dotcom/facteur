# Story: Widget Android — Refonte UI scroll + bouton refresh + fix tap article

## Contexte

Suite à `widget.2.refonte-scrollable-deep-link.story.md`, deux régressions persistent en prod (captures v34/v35) :

1. **Tap sur article ouvre `Page non trouvée: io.supabase.facteur://digest/<id>`** — l'URI custom-scheme arrive brute dans GoRouter (via `PlatformRouteInformationProvider`) et tombe sur `errorBuilder` avant que `DeepLinkService` (app_links) n'ait le temps de router. Bug critique : tap = écran d'erreur.
2. **Widget pas scrollable** — le 5ᵉ article est tronqué quand la cell est petite (la précédente tentative ListView avait été retirée à cause d'un bug Samsung One UI).
3. **Densité visuelle** — titres 15sp, vignettes 60dp, paddings serrés : illisible/peu engageant.
4. **Bandeau "Mets à jour ton essentiel" inutile** — non interactif, prend de la place ; remplacé par un bouton refresh local.

## Décisions UX validées (utilisateur)

- **Refresh button** : re-render local depuis SharedPrefs (pas de fetch réseau).
- **5 articles** : nombre inchangé.
- **Scroll** : retour à `ListView + RemoteViewsService`, gating sur Samsung One UI lors du VERIFY ; fallback inline + paddings réduits si régression.
- **Stale banner supprimé** : pas de detection 36h (compromis assumé).
- **Routing** : on garde les 2 chemins (redirect GoRouter + DeepLinkService) — idempotents, et DeepLinkService conserve l'instrumentation analytics.

## Tâches

### Track 4 — Fix bug "Page non trouvée" (P0, fait en premier)

- [ ] `lib/config/routes.dart` : ajouter dans `redirect` une interception du scheme `io.supabase.facteur` qui appelle `DeepLinkService.parse` et retourne la route interne (ou `RoutePaths.feed` en fallback). Placer AVANT la logique auth.
- [ ] `test/config/routes_redirect_test.dart` (ou existing test file) : cas widget tap article → route `/feed/content/<id>`.
- [ ] Vérifier que le double routing (redirect + DeepLinkService._route) reste idempotent.

### Track 2 + 3 — Sizing bumps + refresh button + suppression stale banner

- [ ] `widget_article_row.xml` : titre 15→17sp, thumb 60→72dp, logo 16→18dp, meta 11→12sp, padding row 10→12dp, marginEnd 8→12dp.
- [ ] `FacteurWidget.kt` : ajuster `loadBitmap(... , 72)` et `loadBitmap(... , 18)` pour matcher la décode resolution.
- [ ] `facteur_widget.xml` : remplacer `RelativeLayout widget_header` par un layout 3 colonnes (refresh icon | "Facteur" | streak), supprimer `stale_banner`.
- [ ] `FacteurWidget.kt` : supprimer `STALE_THRESHOLD_MS` + bloc isStale ; supprimer `setOnClickPendingIntent(R.id.stale_banner, ...)`.
- [ ] `FacteurWidget.kt` : ajouter `ACTION_REFRESH` + `onReceive` qui appelle `notifyAppWidgetViewDataChanged` et re-déclenche `onUpdate`.
- [ ] Drawable `ic_widget_refresh.xml` (vector 24dp, accent color).
- [ ] `wireClickIntents` : câbler `R.id.btn_refresh` sur le PendingIntent broadcast `ACTION_REFRESH`.

### Track 1 — Re-introduction ListView + RemoteViewsService (gating Samsung)

- [ ] NEW `FacteurWidgetService.kt` : `RemoteViewsService` + `RemoteViewsFactory`, lit `articles_json` via `HomeWidgetPlugin.getData`, déplace `loadBitmap`/`roundCorners`/`formatTime` dans un `WidgetRendering.kt` partagé.
- [ ] `facteur_widget.xml` : remplacer `LinearLayout articles_container` par `ListView articles_list` + `TextView empty_view`.
- [ ] `FacteurWidget.kt` `onUpdate` : `setRemoteAdapter` + `setEmptyView` + `setPendingIntentTemplate` + `notifyAppWidgetViewDataChanged`.
- [ ] `AndroidManifest.xml` : déclarer `<service android:name=".FacteurWidgetService" android:permission="android.permission.BIND_REMOTEVIEWS" android:exported="false" />`.
- [ ] **VERIFY OBLIGATOIRE** sur Samsung One UI. En cas d'échec : revert Track 1, garder inline rendering + réduire paddings 12→6dp pour faire tenir 5 rows dans la cell la plus petite.

## Fichiers

### Flutter (MODIFIED)
- `apps/mobile/lib/config/routes.dart`
- `apps/mobile/test/core/services/deep_link_service_test.dart` (cas additionnel)
- `apps/mobile/test/config/routes_redirect_test.dart` (NEW)

### Android (MODIFIED)
- `apps/mobile/android/app/src/main/kotlin/com/example/facteur/FacteurWidget.kt`
- `apps/mobile/android/app/src/main/res/layout/facteur_widget.xml`
- `apps/mobile/android/app/src/main/res/layout/widget_article_row.xml`
- `apps/mobile/android/app/src/main/AndroidManifest.xml`

### Android (NEW)
- `apps/mobile/android/app/src/main/kotlin/com/example/facteur/FacteurWidgetService.kt`
- `apps/mobile/android/app/src/main/kotlin/com/example/facteur/WidgetRendering.kt`
- `apps/mobile/android/app/src/main/res/drawable/ic_widget_refresh.xml`

## Verify

- `cd apps/mobile && flutter test`
- `cd apps/mobile && flutter analyze`
- `cd apps/mobile && flutter build apk --debug`
- Manuel : install APK, ajouter widget, tap article → `/feed/content/<id>` (PAS `Page non trouvée`), tap refresh → re-render, scroll OK sur cell réduite, **test Samsung One UI**.

## Status

- [ ] Track 4 (deep link fix) implémenté + tests
- [ ] Track 2+3 (sizing + refresh) implémentés
- [ ] Track 1 (ListView) implémenté ou fallback documenté
- [ ] VERIFY (flutter test + analyze + APK)
- [ ] PR créée vers `main`
