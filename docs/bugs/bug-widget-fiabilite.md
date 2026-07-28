# Bug — Widget Facteur : refonte fiabilité

**Type** : Bug · **Statut** : implémenté, en attente de vérification device
**Date** : 27/07/2026 · **Branche** : `boujonlaurin-dotcom/widget-refresh-bugs`

---

## Symptômes rapportés

1. Pour certains utilisateurs, les news du widget ne se rafraîchissent **jamais**.
2. Le bouton « Ajouter un Widget » ne fait rien (et est enterré dans Compte).
3. Le widget n'affiche que ~9 articles.
4. Le bouton refresh du widget ne rafraîchit pas et fait planter Flâner.
5. Ouvrir le widget **avant** la tournée du matin casse ensuite les requêtes
   d'articles dans toute l'app.

Ce ne sont pas 5 bugs indépendants : ce sont 4 causes racines, dont une seule
explique déjà la moitié des symptômes.

---

## Diagnostic

### C1 — `home_widget` ne peut jamais atteindre les receivers (applicationId ≠ namespace)

`HomeWidgetPlugin.kt:105` et `:157` (`home_widget-0.7.0+1`) :

```kotlin
val javaClass = Class.forName(qualifiedName ?: "${context.packageName}.${className}")
```

- `context.packageName` = **applicationId** → `com.example.facteur.staging`
  (flavor `beta`) ou `facteur.app` (flavor `playstore`).
- Les receivers vivent dans le **namespace** `com.example.facteur`
  (`android/app/build.gradle.kts:50` ; `AndroidManifest.xml` déclare
  `android:name=".FacteurWidgetLight"`, résolu contre le namespace).

⇒ `ClassNotFoundException` sur **les deux flavors**, à **chaque** appel.
`WidgetService` passait `androidName:` sans `qualifiedAndroidName:` et avalait
l'exception dans un `catch (e) { debugPrint(...) }`.

Conséquences :
- `requestPinWidget()` no-op → « Ajouter un Widget » mort, sans feedback ;
- **aucun `ACTION_APPWIDGET_UPDATE` jamais envoyé**. Les données *sont* écrites
  dans `HomeWidgetPreferences` (ce chemin ne touche pas aux noms de classe),
  mais le widget ne repeint que sur l'alarme système `updatePeriodMillis`
  (30 min) → contenu systématiquement en retard, jamais à la demande.

Cohérent avec Sentry : **zéro** `PlatformException` remontée (tout est catché),
donc aucune contre-preuve.

### C2 — Crash fatal 401 sur le chemin de fraîcheur widget (Sentry FLUTTER-1E, 23 events / 11 users)

```
_FacteurAppState.didChangeAppLifecycleState (app.dart)
_FacteurAppState._ensureWidgetFresh
FeedNotifier.ensureWidgetFresh (feed_provider.dart)
```

`DioException [bad response] 401`, **unhandled / fatal** via
`PlatformDispatcher.onError` : `app.dart` faisait `unawaited(...)` sur
`ensureWidgetFresh`, qui `await refresh()` sans try/catch → l'erreur async
n'avait aucun handler. Feeder amont : **FLUTTER-6** `TimeoutException 0:00:08`
dans `SessionRefresher._defaultRefresh`.

### C3 — Le deep-link widget court-circuitait la porte d'auth → `signOut` app-wide

`config/routes.dart`, **avant** le gate `authState.isLoading → /splash` :

```dart
if (state.uri.scheme == 'io.supabase.facteur') {
  final action = DeepLinkService.parse(state.uri);
  DeepLinkService.instance.clearPending();
  return action.route ?? RoutePaths.fluxContinu;   // ← saute isLoading / onboarding / email
}
```

Cold-open depuis le widget → atterrissage direct sur `/flaner/content/<id>` ou
`/flux-continu/content/<id>` (ces sous-routes échappent volontairement au gate
rituel) alors que `Supabase.currentSession` peut encore être `null`.
`ApiClient` attendait **100 ms** puis partait **en anonyme** → 401 →
`SessionRefresher.refresh(5 s)` échoue au cold boot → `onAuthError(401)` →
`handleSessionExpired` → **`signOut()` complet** → `WidgetService.clear()` vide
le widget.

C'est exactement « j'ouvre le widget avant ma tournée et ensuite plus rien ne
charge » : ce n'est pas une panne de requêtes, c'est une **déconnexion**. Ça
explique aussi une partie des « widgets qui ne se rafraîchissent jamais »
(payload vidé, utilisateur déloggé sans s'en rendre compte).

Aggravant : le cache statique `FeedRepository._defaultViewLastResult`
(fenêtre 5 s) pouvait mémoriser une réponse dégradée/anonyme et la propager à
tous les appelants.

Sentry corrobore : **FLUTTER-Y** `type 'Null' is not a subtype of type
'Perspective'` (`state.extra` null, 20 events) — même chemin cold-restore.

### C4 — Bouton refresh : flag perdu au cold start, effets de bord violents à chaud

- **Cold start** : le flag `refresh=1` était **jeté**. `pendingRoute()` ne
  renvoyait que `action.route`, le redirect perdait `action.refresh` →
  `_onRefreshRequested` jamais appelé → **no-op littéral**.
- **À chaud** :
  - `ref.read(digestProvider.notifier)` **construit** le provider, dont le
    `build()` lance `_loadBothDigests` : timeout 45 s × 5 retries avec backoff
    5/10/15/20/30 s, soit ~80 s de chaîne réseau pour un tap ;
  - au passage `_loadBothDigests` appelle `sereinToggleProvider.initFromApi(...)`
    → peut **basculer le toggle Serein** sous l'utilisateur, ce que `feedProvider`
    et `digestProvider` watchent → rebuild du feed ;
  - `refreshForWidget()` faisait `state = AsyncData(...)` **juste après**
    `router.go('/flaner')` → l'état visible était remplacé pendant que
    `FlanerScreen` se montait. C'est le « plante Flâner ».

### C5 — Symptôme « 9 articles » : la profondeur n'est jamais reconstituée

Les caps sont cohérents à **80 partout** et le parsing Kotlin est non destructif.
**Rien ne tronque à 9** — le payload contenait réellement ~9 lignes :

- les pushes ambiants poussaient `state.items`, c'est-à-dire la liste **visible**
  de Flâner, qui **rétrécit** au fil de la lecture (overlay `_consumedContentIds`) ;
- `_prefetchForWidget` abandonnait dès `!_hasNext` → la profondeur n'était jamais
  restaurée ;
- le garde de signature `'${len}|${first.id}|${last.id}'` laissait passer ce
  rétrécissement mais bloquait toute repush si seul le *milieu* changeait.

### C6 — Rien ne rafraîchissait le widget app fermée

Pas de `workmanager` ni `background_fetch`. `homeWidgetBackgroundCallback` est un
no-op assumé. `firebaseMessagingBackgroundHandler` ne touche jamais
`WidgetService`. L'alarme 30 min ne fait que **repeindre les mêmes octets**
(`onUpdate` relit SharedPreferences, aucun réseau). `initWidgetIfNeeded()` était
**du code mort** — zéro appelant → un widget fraîchement épinglé restait vide.

### C7 (suivi, non corrigé) — Sentry FLUTTER-1D, 3 users, fatal

`RuntimeException: Unable to start activity ComponentInfo{facteur.app/androidx.glance.appwidget.action.ActionTrampolineActivity}`
→ `IllegalArgumentException: List adapter activity trampoline invoked without
specifying target intent`.

Vérifié : `home_widget` 0.7 tire bien `androidx.glance:glance-appwidget:1.0.0`
(`android/build.gradle:54`) alors que nous n'utilisons que RemoteViews et
n'enregistrons aucun receiver Glance. Mais l'AAR n'est pas dans le cache Gradle
local et Conductor n'a pas de JDK : **le manifest mergé n'a pas pu être
inspecté**. Conformément au plan, on ne retire rien sur une activité tierce
exportée sans preuve. À reprendre avec un build Android disponible.

---

## Correctifs livrés

### Lot 1 — C1 : réparer le pont Flutter → receivers

`lib/core/services/widget_service.dart`
- Constantes qualifiées dérivées du **namespace** (`WidgetService.androidNamespace`
  = `com.example.facteur`), avec commentaire sur le piège applicationId ≠ namespace.
- `qualifiedAndroidName:` passé sur **tous** les appels, via `_pushUpdate()`
  (3 `updateWidget` + `requestPinWidget`). `androidName:` gardé en fallback.
- `requestPinWidget()` retourne un `enum WidgetPinResult { requested, unsupported,
  failed }`, en s'appuyant sur `HomeWidget.isRequestPinWidgetSupported()`.
- `WidgetService.isWidgetPinned()` via `HomeWidget.getInstalledWidgets()` — ce
  chemin utilise `getInstalledProvidersForPackage(context.packageName)` et n'est
  **pas** affecté par C1.
- `initWidgetIfNeeded()` (code mort) appelé au bootstrap depuis
  `_initDeferredServices`.

**Garde anti-régression** : `test/core/services/widget_service_test.dart` lit le
`namespace` directement dans `build.gradle.kts` et vérifie qu'il est bien
distinct des applicationId des deux flavors.

### Lot 2 — C3 : le deep-link ne peut plus déconnecter

`lib/config/routes.dart`
- La branche `scheme == 'io.supabase.facteur'` **seed** désormais le pending et
  retourne `/splash` au lieu de router avant l'auth. Le bloc 3 existant consomme
  le pending une fois l'auth résolue — le chemin déjà prévu par le design. Les
  auth callbacks restent traités avant les gates (ils portent la session que les
  gates attendent).
- Tous les `state.extra as X?` durcis via un helper unique `extraAs<T>(state)`
  (9 sites) — corrige **FLUTTER-Y**.

`lib/core/api/api_client.dart`
- L'attente de session passe de 100 ms à un budget borné de 2 s (`_awaitSession`),
  aligné sur l'esprit de `resolveMorningRitualMaxWait`.
- **Écart assumé au plan** : la requête part quand même en anonyme si le budget
  est épuisé (certains endpoints sont publics ; échouer localement aurait été une
  régression à large rayon). Elle est en revanche **marquée**, et un 401 sur une
  requête partie sans header ne déclenche **jamais** `handleSessionExpired`. La
  chaîne C3 est coupée au même endroit, sans casser les appels légitimes.
- Le refresh du chemin 401 n'impose plus 5 s : il hérite du budget adaptatif.

`lib/features/feed/repositories/feed_repository.dart`
- `_defaultViewLastResult` n'est plus mémorisé quand la réponse a été obtenue
  sans session (`ApiClient.hasSession`).

### Lot 3 — C2 : plus de crash fatal sur le chemin de fraîcheur

- `FeedNotifier.ensureWidgetFresh` : `await refresh()` enveloppé dans un
  try/catch qui log en Sentry `warning` et **ne relance pas**.
- `app.dart._ensureWidgetFresh` : `.catchError` explicite sur le `unawaited`.
- `SessionRefresher.resolveRefreshTimeout(lifecycle)` : 8 s en `resumed`, 20 s
  sinon (cold boot / réveil par tap widget) — corrige le feeder FLUTTER-6.

### Lot 4 — C4 : un bouton refresh qui rafraîchit vraiment

- `DeepLinkService.pendingAction()` expose l'action complète (route + `refresh`),
  `navigableRouteFor()` factorise la résolution, `replayRefreshIfRequested()`
  rejoue le side-effect + `trackWidgetAppOpened`. Le routeur les utilise → le
  bouton marche aussi au **cold start**.
- `app.dart` : `container.exists(digestProvider)` avant tout `ref.read(...notifier)`
  → un tap widget ne peut plus amorcer la chaîne 45 s × 5.
- `DigestNotifier.syncWidgetFromRefresh()` devient **mémoire seule** : plus de
  `_loadBothDigests()`, donc plus de bascule Serein parasite.
- `FeedNotifier.refreshForWidget()` **n'écrit plus dans `state`**. Il rafraîchit
  `_globalItems` + le buffer widget et pousse le widget.

### Lot 5 — C5 : profondeur du payload garantie

- Buffer widget dédié `_widgetBuffer` (cap 80), alimenté en **union** (dédup par
  `id`, frais en tête) et **découplé** de l'overlay `_consumedContentIds` : lire
  un article dans l'app ne vide plus le widget.
- `_scheduleWidgetPush` pousse le buffer, pas `state.items`.
- `_prefetchForWidget` : le bail `!_hasNext` est levé (il décrivait la pagination
  *visible*, pas la profondeur widget) ; bornes `_widgetPrefetchMaxPages` et cap
  conservées. Déclenché aussi depuis `ensureWidgetFresh` quand le buffer < 80.
  **Cooldown de 30 min** ajouté avec le bail : un compte qui n'a pas 80 articles
  disponibles n'atteindra jamais le cap, et sans garde il relancerait 4 appels
  `/api/feed/` à chaque build de feed et chaque retour de premier plan (cf.
  `docs/bugs/bug-infinite-load-requests.md`). Le bouton refresh du widget passe
  `force: true` et court-circuite le cooldown.
- Garde de signature étendu à **tous** les ids + péremption 6 h (repush forcé).
- Diagnostic : la profondeur réelle du payload est persistée à chaque push dans
  `widget_last_push_count` (`HomeWidgetPreferences`).
- Bonus nécessaire : les logos de source sont désormais cachés **par URL** et non
  par rang. Le fichier du rang N était réécrit à chaque push, donc une entrée
  conservée d'un push précédent pointait vers les octets d'une *autre* source —
  invisible tant qu'on remplaçait, fatal dès qu'on fusionne. Effet de bord
  bienvenu : plus de re-téléchargement des mêmes logos à chaque push.
  `_cachedLogo` est en **single-flight par URL** : `_buildFeedArticleList`
  sérialise les 80 lignes via `Future.wait`, donc les N articles d'une même
  source arrivaient en parallèle et lançaient N téléchargements concurrents
  écrivant *le même* fichier.

### Lot 6 — C6 : refresh de fond via `workmanager`

`lib/core/services/widget_background_refresh.dart` (nouveau)
- `workmanager: ^0.9.0` ajouté au `pubspec.yaml`.
- Callback dispatcher `@pragma('vm:entry-point')`.
- Dans l'isolate : `Hive.initFlutter()` + `SupabaseHiveStorage` pour restaurer la
  session ; aucune session → **abandon silencieux**, jamais de `signOut`.
- **Dio nu**, sans les interceptors `onAuthError`/`onAuthRecovered` : un 401 en
  background ne peut pas délogger (leçon de C3).
- Réponse parsée par `FeedRepository.parseFeedData` (statique, sans
  `ApiClient`) : un second parseur pour le même endpoint aurait garanti qu'un
  changement de schéma fasse silencieusement retomber le widget à vide.
- `GET feed/?page=1&limit=20` → `WidgetService.updateWidgetMergingFlux()`, qui
  **fusionne** au lieu de remplacer (sinon le payload retomberait de 80 à 20,
  soit exactement le symptôme C5).
- `registerPeriodicTask` toutes les ~1 h, `NetworkType.connected`,
  `requiresBatteryNotLow`, `ExistingPeriodicWorkPolicy.keep`. Annulé au logout à
  côté de `WidgetService.clear()`.

### Lot 7 — CTA « Ajouter le widget »

- `lib/features/feed/widgets/widget_cta_banner.dart` : bandeau en tête de Flâner,
  bâti sur les tokens existants (même idiome que `PinSubjectsBanner`).
- Affiché uniquement si `WidgetService.isWidgetPinned()` renvoie `false` (en cas
  d'incertitude → masqué) ; dismissible, throttle 7 j aligné sur le bandeau
  Lettres. Le throttle passe par le **registre unifié des nudges**
  (`NudgeIds.widgetCtaFeedBanner`, `NudgeFrequency.cooldown`) et non par une clé
  SharedPreferences maison : même horloge testable, même purge, même namespace
  que les autres bandeaux du feed. (`NudgeIds.widgetPinAndroid` n'a pas été
  réemployé : cette entrée sert de fixture `once`/`high` aux tests du
  coordinateur, la repurposer les aurait cassés.)
- `lib/core/services/widget_pin_prompt.dart` : point d'entrée unique qui rend
  toujours compte du résultat (`unsupported` → explication, `failed` → erreur).
  L'entrée Compte est branchée dessus.

### Lot 8 — C7 : trampoline Glance

Non corrigé, documenté ci-dessus. Dépendance confirmée, manifest mergé non
inspectable sans JDK. FLUTTER-1D reste en suivi.

---

## Vérification

### Fait

- `flutter analyze` : aucune **erreur** ; les warnings de `lib/` sont tous
  pré-existants (inférence Dio, `unused_element`…).
- Tests ciblés : `widget_service_test.dart` (garde namespace),
  `deep_link_service_test.dart` (`pendingAction` + `refresh=1` cold start),
  `feed_provider_widget_refresh_test.dart` (buffer qui ne rétrécit pas,
  `refreshForWidget` qui ne mute plus `state`).
- Suite mobile complète comparée à la baseline connue (~27 échecs pré-existants,
  cf. mémoire projet).

### Reste à faire — vérification device (la seule qui prouve C1)

Conductor n'a pas de JDK par défaut (`brew install openjdk@17` + `JAVA_HOME`).

```bash
cd apps/mobile && flutter build apk --debug --flavor beta
```

1. Épingler le widget **depuis le bandeau Flâner** → il doit apparaître
   (aujourd'hui : rien).
2. `adb logcat -s FacteurWidget:D FacteurWidgetSvc:D` → vérifier `onUpdate` /
   `onDataSetChanged` **immédiatement** après une action in-app, pas 30 min plus
   tard. Vérifier `count=` > 9 et croissant jusqu'à 80.
3. Lire 10 articles dans Flâner → le compteur du masthead **ne doit pas** descendre.
4. Tap refresh **app tuée** (cold start) → l'app s'ouvre, le widget se met à jour,
   Flâner ne perd pas son état et ne crashe pas.
5. **Scénario clé** : app tuée, tournée du matin non ouverte, tap sur une ligne du
   widget → l'article s'ouvre après résolution de l'auth, l'utilisateur **reste
   connecté**. Vérifier dans logcat l'absence de
   `⛔️ ApiClient: 401 after refresh attempt` et de `auth_session_expired`.
6. Background : app tuée > 1 h → le contenu du widget doit avoir bougé.
   Forçable via `adb shell cmd jobscheduler run -f <applicationId> <jobId>`.

### Après merge sur `main` (staging)

- Sentry projet `flutter` : **FLUTTER-1E** (23 events / 11 users) et **FLUTTER-Y**
  doivent tomber à zéro ; surveiller FLUTTER-6 et FLUTTER-1D.
- Vérifier `widget_last_push_count` (médiane attendue nettement > 9).

---

## Hors scope explicite

- Crashes **Flux Continu** (FLUTTER-1R/1M/1S/1T/1K/1N, ~30 events fatals sur 5 j :
  `ref` après dispose dans le fan-out progressif, Timer `_maybeTriggerAutoGrow`,
  `ref` dans `dispose()`, `GoRouter.of` sur contexte mort) et **FLUTTER-1X**
  (guided tour, `No ProviderScope found`, marqué *escalating*) : famille distincte,
  workspace dédié. **À signaler au PO.**
- Backend `PYTHON-3C` (`IdleInTransactionSessionTimeout` dans `_build_carousels`) :
  cause DB indépendante du widget.
- Pas de widget iOS (aucune extension, aucun app group) — tout ce plan est Android.
