# Bug — Widget Facteur : le widget doit être Flâner

**Type** : Bug · **Statut** : implémenté, vérification device requise
**Date** : 11/08/2026 · **Branche** : `claude/widget-facteur-android-bugs-3vu748`
**Device rapporteur** : Pixel 9 (Android 15/16)

> Suite de [`bug-widget-fiabilite.md`](bug-widget-fiabilite.md) (27/07/2026). Les
> Lots 1→8 de cette itération sont bien en place ; ils ne suffisent pas, parce
> qu'ils traitaient la **plomberie** (pont Flutter→receivers, deep link qui
> déloggue, profondeur du payload, refresh de fond) sans toucher au **contenu**
> du widget. Le symptôme principal restant — « mon feed n'a pas bougé depuis
> 14 jours » — vient de là.

---

## Symptômes rapportés

| # | Symptôme |
|---|----------|
| S1 | Le feed du widget ne se met plus à jour (14 jours de retard) |
| S2 | En scrollant **sous** les 5 premiers articles figés, on retrouve des articles marqués « à l'instant » / « il y a quelques minutes » alors qu'ils datent de plusieurs jours |
| S3 | Le clic sur un article renvoie **parfois** vers l'app (L'Essentiel), **parfois** vers l'article |
| S4 | Le bouton refresh 🔄 ne rafraîchit rien dans l'interface du widget |
| S5 | Retour arrière après ouverture d'un article depuis le widget → page vide, fond gris |
| S6 | Pas d'heure de dernière mise à jour fiable |
| S7 | Masthead : pastille « F » générique, wordmark en gras système (pas Fraunces) |

---

## Diagnostic

### D1 — Un bloc « Essentiel » gelé squatte les 5 premières lignes (⇒ S1, S3)

`WidgetService.mergeForWidget` construit le payload **Essentiel d'abord, Flux
ensuite** :

```dart
for (final e in essentiel) { ... result.add({...e, 'source_kind': 'essentiel'}); }
for (final f in flux)      { ... result.add({...f, 'source_kind': 'flux'}); }
```

La partie Essentiel vient de la clé `articles_json`, écrite **uniquement** par
`DigestNotifier._syncWidget()` (`digest_provider.dart:293`). Or L'Essentiel a
fusionné dans la Tournée du jour lors du cleanup post-unification : ce provider
n'est plus construit dans le parcours nominal. Conséquences en chaîne :

- `articles_json` conserve **indéfiniment** le dernier snapshot digest écrit —
  ici vieux de 14 jours ;
- ce bloc est **en tête** du payload, donc jamais évincé par le cap de 80 ;
- `updateWidgetMergingFlux` (refresh de fond WorkManager, Lot 6) ne fusionne que
  la partie **Flux** : elle se rafraîchit bien, mais **sous** le bloc gelé ;
- `clear()` et `initWidgetIfNeeded()` ne purgent pas cette clé.

⇒ L'utilisateur voit 5 articles figés en haut et du contenu plus frais en
dessous : **exactement** S1 + S2-partie-1. Ce n'est pas une panne de
rafraîchissement, c'est un **en-tête fossile**.

D1 explique aussi S3 : les lignes Essentiel émettent
`io.supabase.facteur://digest/<id>` → `/flux-continu/content/<id>` (Tournée),
les lignes Flux émettent `feed/content/<id>` → `/flaner/content/<id>`. Deux
destinations différentes selon la ligne tapée, plus un repli sur
`/flux-continu` quand l'id du digest fossile n'existe plus côté serveur.

### D2 — « à l'instant » sur des articles vieux de plusieurs jours (⇒ S2)

`Content.fromJson` (`content_model.dart:400`) :

```dart
publishedAt: DateTime.tryParse(json['published_at'] as String? ?? '') ??
    DateTime.now(),
```

Le repli `DateTime.now()` est raisonnable pour l'UI in-app (l'article est en
haut du feed, on le voit passer). Il est **toxique** pour le widget : la valeur
est sérialisée telle quelle dans `published_at_iso`, **figée** dans
`HomeWidgetPreferences`, et relue des jours plus tard par
`WidgetRendering.formatTime`, qui calcule un delta contre `now()`. Un article
sérialisé avec un `published_at` manquant reste donc affiché « à l'instant »
tant qu'il n'est pas évincé du buffer de 80.

Aggravant : `formatTime` n'a **aucun garde-fou** sur les dates futures — un
delta négatif tombe dans `minutes < 1` → « à l'instant ».

### D3 — Ordre non chronologique (⇒ S2)

Ni `FeedNotifier.mergeIntoWidgetBuffer` ni `WidgetService.mergeForWidget` ne
trient par date : l'ordre est celui de **l'arrivée réseau** (page fraîche en
tête, ancien buffer derrière). Après une fusion de fond (20 lignes fraîches sur
un buffer de 80), l'ordre s'entremêle. Le widget doit refléter Flâner, qui est
chronologique.

### D4 — Le bouton refresh n'est pas un refresh du widget (⇒ S4)

```kotlin
data = Uri.parse("io.supabase.facteur://feed?refresh=1")
PendingIntent.getActivity(context, ..., refreshIntent, ...)
```

Le bouton **ouvre l'app**. C'est ce qui avait été livré au Lot 4, et ça marche
au sens strict (le flux est refetché puis repoussé), mais du point de vue de
l'utilisateur *dans le widget* : rien ne bouge, on est éjecté de son écran
d'accueil. Attendu : refresh **en place**, sans quitter le launcher.

Le chemin existe déjà et n'était pas branché :
`HomeWidget.registerInteractivityCallback(homeWidgetBackgroundCallback)` est
appelé au boot (`main.dart:416`) et le callback est un **no-op assumé**
(`main.dart:517`). Côté Kotlin, `home_widget` 0.7 expose
`HomeWidgetBackgroundIntent.getBroadcast(context, uri)` : un PendingIntent qui
réveille un isolate Dart **sans UI**.

### D5 — L'heure du masthead est celle du repaint, pas celle de la donnée (⇒ S6)

```kotlin
val hour = LocalTime.now().format(DateTimeFormatter.ofPattern("H'h'mm", ...))
```

`onUpdate` est rejoué par l'alarme système `updatePeriodMillis` (30 min) **sans
toucher au réseau** : l'heure affichée avance toutes les 30 minutes sur une
donnée vieille de 14 jours. Le widget mentait activement sur sa fraîcheur.

`articles_updated_at` (epoch millis) est pourtant déjà écrit côté Flutter —
simplement jamais relu côté natif. Et il n'était pas écrit sur le chemin
`updateWidget(feedItems:)`, seulement sur `digest:` et `updateWidgetMergingFlux`.

### D6 — Retour arrière → écran vide (⇒ S5)

Cold start depuis le widget : `routes.dart` (bloc 3 du `redirect`) renvoie
**directement** `/flaner/content/<id>`. Or cette sous-route est déclarée avec
`parentNavigatorKey: NotificationService.navigatorKey` (navigateur racine) :
GoRouter **n'empile pas** `/flaner` en dessous. La pile racine ne contient donc
que le lecteur d'article. Un `pop` sort de la pile sans destination →
`Navigator` vide → fond gris.

À chaud le chemin est différent (`router.push` sur une pile déjà peuplée) et le
retour fonctionne : d'où l'intermittence perçue.

### D7 — Masthead hors design system (⇒ S7)

`facteur_widget_light.xml` : la « pastille F » est un `TextView` avec la lettre
`F` sur un rectangle arrondi, et le wordmark utilise `android:textStyle="bold"`
(gras système). `res/font/fraunces_bold.ttf` **existe déjà** dans le projet et
n'est référencé nulle part.

### D8 — Aucune CI mobile (⇒ cause de la récurrence)

`.github/workflows/` : `ci-tests.yml` ne lance que `pytest` sur
`packages/api/**`. `build-apk.yml` / `build-aab.yml` compilent sans jamais
lancer `flutter test` ni `flutter analyze`. **Aucun test Dart n'a jamais gardé
une release.** C'est la raison structurelle pour laquelle ce widget casse à
chaque itération : les tests écrits au Lot 1→8 existent mais ne sont exécutés
que localement, à la main.

---

## Correctifs

### Lot A — Le widget **est** Flâner (D1, D3)

- `WidgetService` : suppression complète de la voie Essentiel. Plus de
  paramètre `digest:`, plus de clé `articles_json` dans le payload, plus de
  `source_kind`. Le widget sérialise **uniquement** le buffer Flâner.
- `mergeForWidget` → `buildWidgetPayload` : dédup par `id`, **tri
  `published_at` décroissant**, cap 80, rangs réindexés après tri.
- `FeedNotifier.mergeIntoWidgetBuffer` trie également en chrono desc, pour que
  le buffer en mémoire et le payload poussé soient dans le même ordre.
- `DigestNotifier._syncWidget()` / `syncWidgetFromRefresh()` supprimés — le
  digest ne pousse plus rien vers le widget.
- **Migration** : `WidgetService.purgeLegacyEssentielPayload()` est appelée au
  boot (avant `initWidgetIfNeeded`). Elle vide `articles_json`,
  `digest_status`, `digest_progress` et **réécrit** `widget_articles_json`
  depuis le seul `feed_articles_json`. Sans elle, les installs existantes
  garderaient leur bloc fossile jusqu'à la prochaine fusion de fond.
- Deep link unique : toutes les lignes émettent
  `io.supabase.facteur://feed/content/<id>` → `/flaner/content/<id>`.

### Lot B — Horodatages honnêtes (D2, D5)

- `Content.publishedAtRaw` (nullable) : la date **réellement** reçue, sans le
  repli `DateTime.now()`. `Content.publishedAt` garde son comportement pour
  l'UI in-app (aucune régression d'affichage).
- `WidgetService` sérialise `published_at_iso` depuis `publishedAtRaw` : chaîne
  **vide** quand la date est inconnue → le widget n'affiche rien plutôt que de
  mentir.
- `WidgetRendering.formatTime` : garde-fou sur les deltas négatifs (date future
  ⇒ chaîne vide) et seuil « à l'instant » resserré à < 2 min.
- `articles_updated_at` est écrit sur **tous** les chemins de push.
- Le masthead affiche `Maj HHhMM` / `Maj hier HHhMM` / `Maj le JJ/MM` lu depuis
  `articles_updated_at` (`WidgetRendering.formatUpdatedAt`), plus jamais
  `LocalTime.now()`.

### Lot C — Refresh en place, sans ouvrir l'app (D4)

- `FacteurWidget.onReceive` intercepte `ACTION_FACTEUR_WIDGET_REFRESH` :
  1. repeint immédiatement le masthead en « Mise à jour… » (retour visuel
     instantané, le reproche principal de S4) ;
  2. déclenche `HomeWidgetBackgroundIntent.getBroadcast(context,
     facteur://widget-refresh)` → isolate Dart sans UI.
- `homeWidgetBackgroundCallback` (`main.dart`) n'est plus un no-op : sur l'URI
  `widget-refresh`, il exécute `WidgetBackgroundRefresh.run()` — le même code
  que la tâche horaire (session Hive, Dio nu sans interceptor auth, fusion et
  non remplacement). En cas d'échec il repousse le payload courant pour sortir
  de l'état « Mise à jour… ».
- Le bouton n'ouvre plus l'app. Le tap sur le **masthead** (logo + wordmark)
  reste le chemin « ouvrir Flâner ».

> **Pull-to-refresh : impossible, et ce n'est pas un arbitrage.** Un widget
> d'écran d'accueil Android est un arbre `RemoteViews` inflaté dans le process
> du launcher ; la liste blanche de vues supportées ne contient ni
> `SwipeRefreshLayout` ni aucun conteneur capable d'intercepter un geste
> vertical — ce geste appartient au launcher (scroll de la liste, puis scroll
> de l'écran d'accueil). Aucune app du Play Store n'en propose. Le bouton 🔄 +
> le refresh horaire + le push à chaque ouverture d'app couvrent le besoin.

### Lot D — Retour arrière (D6)

`routes.dart`, bloc 3 : un deep link widget de type `article` ne renvoie plus
la route du lecteur. Il renvoie `/flaner` **et** programme un
`router.push(<route article>)` au premier frame. La pile devient
`/flaner` → lecteur : le retour arrière ramène sur Flâner, jamais sur l'écran
d'accueil ni sur du vide.

Le chemin à chaud (`DeepLinkService._route`) fait déjà `router.push` ; il gagne
un garde-fou symétrique — si la pile racine ne peut pas `pop`, on `go('/flaner')`
avant de `push`.

### Lot E — Masthead au design system (D7)

- `drawable/ic_facteur_mark_{light,dark}.xml` : la marque Facteur (enveloppe),
  reprise du tracé de `ic_stat_facteur.xml`, teintée à l'accent de chaque
  variante — remplace la pastille « F ».
- Wordmark « Facteur » en `android:fontFamily="@font/fraunces_bold"` (la police
  était déjà dans `res/font/`, inutilisée).
- Le masthead entier (marque + wordmark) reste la zone de tap « ouvrir
  Flâner » ; le 🔄 est isolé à droite.

### Lot F — QA : le widget ne peut plus casser en silence (D8)

- **`.github/workflows/mobile-tests.yml`** (nouveau) : sur toute PR touchant
  `apps/mobile/**`, lance `flutter analyze --no-fatal-infos` et le **paquet de
  tests widget** :
  ```
  test/core/services/widget_service_test.dart
  test/core/services/deep_link_service_test.dart
  test/features/feed/feed_provider_widget_refresh_test.dart
  test/android/widget_resources_test.dart
  ```
  Périmètre volontairement ciblé : la suite mobile complète porte ~27 échecs
  pré-existants (cf. mémoire projet) et un gate global serait rouge dès le
  premier jour, donc ignoré. Ce paquet-là, lui, est **vert et bloquant**. La
  dette « suite complète verte » est traçée hors de ce bug.
- **`test/android/widget_resources_test.dart`** (nouveau) : garde sur les
  ressources natives que Dart ne compile pas — présence de la police Fraunces,
  absence de la pastille « F », référence au logo dans les deux layouts,
  déclaration des receivers/service dans le manifest, et cohérence des ids de
  vues entre layouts et Kotlin. Ces régressions-là (renommer un `@+id`, retirer
  un layout) ne cassent aucun test Dart existant mais vident le widget sur le
  device.
- **`docs/qa/scripts/verify_widget.sh`** (nouveau) : checklist device
  scriptée — `adb` logcat filtré, `dumpsys appwidget`, déclenchement forcé du
  job WorkManager, tap simulé sur une ligne, vérification du back stack.

---

## Vérification

### Faite

- Revue statique complète du chemin widget (Dart + Kotlin + XML + routes).
- Tests unitaires écrits (voir Lot F).

### Non faite — limite d'environnement, à faire avant merge

L'environnement d'exécution de cette session **n'a ni le SDK Flutter ni le SDK
Android** (`which flutter` → vide, `ANDROID_HOME` vide) : `flutter test`,
`flutter analyze` et `flutter build apk` n'ont **pas** pu être lancés ici. La
CI ajoutée au Lot F exécutera les deux premiers sur la PR ; le build APK et la
vérification device restent à faire.

### Checklist device (Pixel 9, flavor `beta`)

```bash
cd apps/mobile && flutter build apk --debug --flavor beta
adb install -r build/app/outputs/flutter-apk/app-beta-debug.apk
bash docs/qa/scripts/verify_widget.sh
```

| # | Scénario | Attendu |
|---|----------|---------|
| V1 | Épingler le widget, ouvrir l'app une fois | ≥ 20 lignes, toutes issues de Flâner |
| V2 | Comparer les 10 premières lignes à l'onglet Flâner | même ordre, même contenu |
| V3 | Lire les horodatages | aucun « à l'instant » sur un article de la veille ; rien d'affiché si date inconnue |
| V4 | Masthead | logo Facteur + « Facteur » en Fraunces Bold + `Maj HHhMM` |
| V5 | Tap 🔄 | « Mise à jour… » immédiat, **l'app ne s'ouvre pas**, contenu rafraîchi ≤ 15 s |
| V6 | Tap sur une ligne (app tuée) | ouvre l'article dans Flâner |
| V7 | Depuis V6, retour arrière | atterrit sur **Flâner**, jamais sur du vide ni l'écran d'accueil |
| V8 | Laisser 1 h, app tuée | l'horodatage `Maj` a bougé |
| V9 | Logout | widget vidé, tâche de fond annulée |

---

## Hors scope explicite

- **Widget iOS.** Il n'existe aucune extension WidgetKit ni App Group dans le
  projet (`apps/mobile/ios/` n'a que `Runner`). C'est un chantier à part
  entière — cible WidgetKit, App Group partagé, réécriture du transport
  `home_widget` côté iOS, provisioning profile dédié — et il ne partage aucune
  ligne de code avec les correctifs ci-dessus. Le « si possible Apple » de la
  demande est donc traité comme une **story de suite**, pas comme une partie de
  ce bug. Les changements Dart de ce lot (payload chronologique, dates
  honnêtes, deep link unique vers Flâner) sont le socle qu'une extension iOS
  consommerait tel quel.
- Suite mobile complète verte (~27 échecs pré-existants) — dette séparée.
- Crashes Flux Continu (FLUTTER-1R/1M/1S/1T/1K/1N) — famille distincte.
