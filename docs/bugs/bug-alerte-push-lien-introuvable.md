# Bug — Le clic sur une alerte push mène à « lien introuvable »

**Type** : Bug (hotfix) · **Statut** : implémenté, en attente de vérification device
**Date** : 08/08/2026 · **Branche** : `alertes/lot-a-deeplink` · **Epic** : 30 (Alertes)

---

## Symptôme rapporté

> « J'ai eu des articles intéressants en notif mais quand je clique dessus j'ai
> un lien introuvable. »

Reproductible à 100 %, sur les deux familles d'alertes (source et sujet), depuis
leur mise en service.

---

## Cause racine

`packages/api/app/services/push_composer.py` émettait, pour les deux alertes :

```python
"route": f"/article/{candidate.content_id}",
```

**Cette route n'a jamais été enregistrée dans le `GoRouter` de l'app.** Aucun
`GoRoute` de `apps/mobile/lib/config/routes.dart` n'a le path `/article/:id`.
Les seules routes article enregistrées sont :

| Route | Nature |
|---|---|
| `/flux-continu/content/:id` | canonique (`RouteNames.contentDetail`), branche Tournée du shell |
| `/flaner/content/:id` | branche Flâner du shell |
| `/feed/content/:id` | alias `redirect` historique vers `/flaner/content/:id` |

`RoutePaths.contentDetail = '/content/:id'` est **déclarée mais jamais
enregistrée** — un leurre qui a probablement inspiré le `/article/:id` du
serveur.

Chaîne complète du tap :

1. `PushNotificationService._onNotificationTapped` lit `payload: 'route:…'` ;
2. `openRoute()` fait `GoRouter.of(context).go('/article/<uuid>')` ;
3. aucun match → `errorBuilder` → **« Page non trouvée »**.

⇒ **100 % des alertes push étaient mortes au clic depuis le jour 1** (stories
30.2 puis 30.3).

### Pourquoi ça n'a pas été vu

Les boutons QA `debugShowSourceAlert` / `debugShowTopicAlert` injectaient le
**même** payload cassé : ils reproduisaient fidèlement le bug au lieu de le
révéler. Et aucun test ne confrontait les routes des payloads push à la table
de routage réelle.

### Cause racine secondaire — cold-open

`openRoute()` est appelé depuis `FirebaseMessaging.getInitialMessage()`
(`server_push_service.dart:106`), lui-même déclenché dans les inits différés
juste après `runApp`. À cet instant :

- soit `NotificationService.navigatorKey.currentContext` est encore `null` et
  `openRoute` sortait sans rien faire ;
- soit le `go()` partait, mais la garde `authState.isLoading` du `redirect`
  top-level le renvoyait sur `/splash`, puis le bloc 3 atterrissait sur
  `/flux-continu`.

Dans les deux cas la cible était perdue : même avec la route enregistrée, un tap
en app **froide** aurait ouvert L'Essentiel, pas l'article. Invisible jusqu'ici
parce que la seule route push existante (`/digest`) redirige de toute façon vers
`/flux-continu`.

---

## Correctif

### 1. Client — alias de compatibilité (le vrai correctif)

`apps/mobile/lib/config/routes.dart` enregistre `/article/:id` en `redirect` vers
`articleRouteFor(id)`, sur le modèle exact de `/feed/content/:id` :

```dart
GoRoute(
  path: RoutePaths.articleAlias,           // '/article/:id'
  redirect: (context, state) => articleRouteFor(state.pathParameters['id']!),
),
```

Non négociable et **permanent** : des notifications portant l'ancien payload
dorment déjà dans les tiroirs de notification des utilisateurs, et le backend
`facteur-production` continue d'émettre l'ancienne route jusqu'à la prochaine
release hebdo.

### 2. Serveur — payload canonique

`push_composer.article_route()` émet désormais `/flux-continu/content/<id>`.

**Choix de la cible, vérifié contre `origin/production`** :
`git show origin/production:apps/mobile/lib/config/routes.dart` montre
`/flux-continu/content/:id` (ligne 492), `/flaner/content/:id` (588) et
`/feed/content/:id` (614) — mais **pas** `/article/:id`. Les deux candidats
étaient donc sûrs. `/flux-continu/content/<id>` l'emporte parce que :

- c'est `RouteNames.contentDetail`, la route article la plus ancienne encore
  enregistrée ;
- le retour depuis le lecteur repose sur L'Essentiel, surface d'atterrissage
  post-auth, plutôt que sur Flâner.

Un push émis maintenant s'ouvre correctement **et** sur `main` **et** sur les
binaires `production` en circulation.

### 3. Boutons QA

`showTestSourceAlert` / `showTestTopicAlert` portent la nouvelle route : ils
restent le miroir exact de ce que FCM envoie. C'est leur seule raison d'être.

### 4. Cold-open

`PushNotificationService` parque la cible (`_pendingRoute`) **avant** de
naviguer ; le `redirect` la consomme (`takePendingRoute()`) dans le bloc 3, une
fois l'auth résolue, et la relâche (`clearPendingRoute()`) dès qu'un écran réel
est atteint.

C'est délibérément le **même** chemin que le deep link widget, et pour la même
raison : ne jamais consommer un deep link avant la résolution de l'auth. Le
précédent — cold-open widget qui montait le lecteur session nulle, `401`,
`onAuthError` et déconnexion app-wide — est documenté en C3 de
[bug-widget-fiabilite.md](bug-widget-fiabilite.md). Le mécanisme ajouté ici ne le
réintroduit pas : la cible n'est rejouée qu'**après** `authState.isLoading ==
false` et les gardes d'onboarding / confirmation d'email.

### 5. Voisinage — audit des autres routes push

| Émetteur | Route | Verdict |
|---|---|---|
| `compose_daily_digest` | `/digest` | enregistrée (`redirect` → `/flux-continu`) — OK |
| `onboarding_reengagement_dispatcher` | `/onboarding` | enregistrée — OK |
| `scheduleDailyDigestNotification` | `/digest` | OK |
| `scheduleDailyGoodNewsNotification` | `/digest?serein=1` | route OK, voir ci-dessous |
| `scheduleVeilleNotification` | `/flux-continu` | enregistrée — OK |

`/article/:id` était la seule route morte. **Observation hors périmètre** : le
paramètre `?serein=1` du push « Bonnes nouvelles » n'est lu nulle part dans
`apps/mobile/lib` et le `redirect` de `/digest` le jette. La route résout donc
sans erreur, mais le mode serein n'est pas activé à l'ouverture. Ce n'est pas une
route morte — non corrigé ici, à arbitrer par le PO.

---

## Test de non-régression

`apps/mobile/test/features/notifications/push_route_resolution_test.dart` — c'est
la pièce qui compte, plus que le correctif lui-même.

Pour chaque route émise par le backend (`backendPushRoutes`) et par les
notifications locales (`localPushRoutes`), il vérifie via
`router.configuration.findMatch(uri)` que la route **matche une route
enregistrée** du vrai `GoRouter` de l'app — exactement la condition qui fait
tomber l'`errorBuilder`. Il couvre aussi l'ancien payload `/article/<id>`.

Le test a des dents : il assert qu'une route inventée **et** `RoutePaths.contentDetail`
(`/content/:id`, déclarée mais jamais enregistrée) sont bien rejetées.

Côté serveur, `test_push_composer.py::test_every_composed_route_is_a_known_shape`
verrouille l'ensemble des routes émises. Les deux listes sont jumelles et se
citent mutuellement : ajouter une route côté serveur sans l'ajouter côté mobile
fait rougir le test Python.

**Vérification négative effectuée** : correctif retiré temporairement →
`l'ancien payload /article/<id> reste résolu` et `la cible parquée pendant
isLoading est rejouée` échouent tous les deux ; correctif remis → vert.

---

## Vérification navigateur (Playwright) — limite assumée

Le parcours web ne peut **pas** observer ce bug sans session authentifiée : le
`redirect` top-level évalue ses gardes **avant** le matching de route, donc un
visiteur non connecté qui ouvre
`https://boujonlaurin-dotcom.github.io/facteur/#/article/<uuid>` est renvoyé sur
`/onboarding` — pas sur « Page non trouvée ». Vérifié sur le build staging
déployé (viewport 390x844, sémantique activée) : URL finale `#/onboarding`,
0 erreur console.

Le test unitaire est donc la vérification **plus forte** ici : il interroge la
table de routage réelle (`router.configuration.findMatch`) sans passer par les
gardes d'auth, et a été validé par vérification négative. Le parcours device
authentifié reste à faire par le PO (ci-dessous).

---

## Compatibilité descendante

| Payload | App | Résultat |
|---|---|---|
| `/article/<id>` (ancien) | nouvelle | alias → `/flux-continu/content/<id>` — OK |
| `/article/<id>` (ancien) | ancienne (`production`) | inchangé, toujours cassé — corrigé au prochain déploiement mobile |
| `/flux-continu/content/<id>` (nouveau) | nouvelle | OK |
| `/flux-continu/content/<id>` (nouveau) | ancienne (`production`) | route déjà présente sur `origin/production` — OK |

Aucune migration Alembic : ce lot ne touche pas au schéma.

---

## Fichiers modifiés

- `apps/mobile/lib/config/routes.dart`
- `apps/mobile/lib/core/services/push_notification_service.dart`
- `packages/api/app/services/push_composer.py`
- `packages/api/tests/services/test_push_composer.py`
- `packages/api/tests/services/test_push_alert_dispatcher.py`
- `apps/mobile/test/features/notifications/push_route_resolution_test.dart` (nouveau)

---

## Reste à vérifier par le PO (device)

1. Alerte source réelle (FCM) : tap → lecteur de l'article, app froide **et**
   app chaude.
2. Idem alerte sujet.
3. Bouton QA « Tester une alerte source » : tap → article.
4. Notification portant l'**ancien** payload `/article/<id>` (celles encore dans
   le tiroir) : tap → article.
