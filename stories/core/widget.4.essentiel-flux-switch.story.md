# Story: Widget Android — Switch Essentiel/Flux + simplification du header

## Contexte

Le widget Android actuel (post `widget.3.refonte-ui-scroll-refresh`) n'expose que l'Essentiel du jour : 5 articles plafonnés, header chargé (refresh button + wordmark "Facteur" + streak + sous-titre), CTA "Ouvrir Facteur" en footer, titres tronqués à 2 lignes.

Demande utilisateur (2026-05-06) :

1. Intégrer le **Flux** (feed) en complément de l'Essentiel — switch Essentiel ↔ Flux dans le header.
2. **Simplifier** : retirer wordmark, streak, refresh, sous-titre, et le bouton "Ouvrir Facteur".
3. **Élargir les cartes** : titres tronqués seulement au-delà de 4 lignes (vs 2 aujourd'hui), thumbnail 86dp à droite inchangée. Style ≈ Google News + feed in-app.

Pas d'iOS (aucune extension widget iOS aujourd'hui).

## Décisions UX validées (utilisateur)

- Vignette : conservée à 86dp à droite ; on autorise simplement le titre à monter à 4 lignes.
- Streak : **supprimé** du widget (la valeur reste dispo in-app).
- Source data Flux : **cache feedProvider** poussé depuis Flutter — pas de fetch réseau côté natif. Si le cache est vide au cold-start, empty state explicite ; le widget se peuple en < 1 s dès que l'app charge le feed.
- Cap Flux : ~30 items (compromis Binder ~1 MB).
- Persistance du mode : clé locale `widget_mode` côté natif (par device).

## Tâches

### Track 1 — Plomberie data Flutter

- [ ] `apps/mobile/lib/core/services/widget_service.dart`
  - [ ] Étendre `updateWidget(...)` avec `List<Content>? feedItems`.
  - [ ] Nouveau `_buildFeedArticleList(List<Content>)` (max 30, thumbnails top 10 only) écrivant `feed_articles_json`.
  - [ ] Mapping : `contentId→id`, `topicId/topicLabel`, `source.name/logo`, `is_main=false`, `perspectiveCount`, `publishedAt`.
- [ ] `apps/mobile/lib/features/feed/providers/feed_provider.dart`
  - [ ] Helper `_pushFeedToWidget(items)` debounced 1 s ; appelé après chaque transition `state = AsyncData(...)` (initial, refresh, loadMore).
- [ ] `apps/mobile/test/core/services/widget_service_test.dart`
  - [ ] Cas : `updateWidget(feedItems:)` écrit `feed_articles_json` (taille, ordre, mapping).

### Track 2 — UI Android (XML + drawables)

- [ ] `apps/mobile/android/app/src/main/res/layout/facteur_widget.xml`
  - [ ] Remplacer header + sous-titre par `LinearLayout` horizontal de 2 onglets (`tab_essentiel`, `tab_flux`).
  - [ ] Supprimer `btn_open` (footer).
- [ ] Drawables : `widget_tab_active.xml`, `widget_tab_inactive.xml` (shape simple radius 6dp).
- [ ] `apps/mobile/android/app/src/main/res/layout/widget_article_row.xml`
  - [ ] `row_title` `maxLines` 2 → 4.

### Track 3 — Logic Android (Kotlin)

- [ ] `FacteurWidget.kt`
  - [ ] Constantes `ACTION_SET_MODE_ESSENTIEL`, `ACTION_SET_MODE_FLUX`.
  - [ ] `onReceive` persiste `widget_mode` dans HomeWidgetPlugin SharedPreferences puis re-render.
  - [ ] `renderTabs(views, mode)` peint actif/inactif et câble PendingIntents broadcast.
  - [ ] `bindArticleList` : lit le mode, passe en extra adapter, choisit la `templatePending` deeplink (`digest` vs `feed/content`) et l'empty-state copy.
  - [ ] Supprimer `wireClickIntents` (plus de `btn_open`/`btn_refresh`).
  - [ ] Conserver `ACTION_REFRESH` ? Non — onglet actif re-tappé peut juste re-render. Suppression complète du refresh.
- [ ] `FacteurWidgetService.kt`
  - [ ] `onGetViewFactory` lit l'extra `widget_mode`.
  - [ ] `onDataSetChanged` → bonne clé JSON.
  - [ ] `getViewAt` : `fillInIntent` `digest/<id>` ou `feed/content/<id>`.
- [ ] `WidgetRendering.kt`
  - [ ] `parseArticles(json, maxRows)` paramétrable (5 essentiel / 30 flux).

### Track 4 — VERIFY

- [ ] `flutter test test/core/services/widget_service_test.dart`
- [ ] `flutter analyze`
- [ ] `flutter test`
- [ ] E2E manuel (émulateur) : header simplifié, switch fonctionne, deeplinks par mode, titre 4 lignes, cold-start Flux empty state puis populé.

## Critères d'acceptation

- [ ] Header n'affiche que le segmented control [Essentiel | Flux].
- [ ] Tap onglet bascule la liste sans relancer l'app, mode persisté.
- [ ] Mode Essentiel : 5 articles digest, deeplink `digest/<id>` (inchangé).
- [ ] Mode Flux : ≤ 30 articles feed scrollables, deeplink `feed/content/<id>`.
- [ ] Titres jusqu'à 4 lignes ; troncature `ellipsize=end` au-delà.
- [ ] PR `--base main`, CI verte, `flutter analyze` clean.

## Hors-scope

- Pas d'iOS.
- Pas de fetch réseau natif Android.
- Pas de pull-to-refresh / loading spinner dans le widget (incompatible RemoteViews).
- Pas de modification du flux Essentiel.

## Fichiers modifiés

- `apps/mobile/lib/core/services/widget_service.dart`
- `apps/mobile/lib/features/feed/providers/feed_provider.dart`
- `apps/mobile/test/core/services/widget_service_test.dart`
- `apps/mobile/android/app/src/main/res/layout/facteur_widget.xml`
- `apps/mobile/android/app/src/main/res/layout/widget_article_row.xml`
- `apps/mobile/android/app/src/main/res/drawable/widget_tab_active.xml` (nouveau)
- `apps/mobile/android/app/src/main/res/drawable/widget_tab_inactive.xml` (nouveau)
- `apps/mobile/android/app/src/main/kotlin/com/example/facteur/FacteurWidget.kt`
- `apps/mobile/android/app/src/main/kotlin/com/example/facteur/FacteurWidgetService.kt`
- `apps/mobile/android/app/src/main/kotlin/com/example/facteur/WidgetRendering.kt`
