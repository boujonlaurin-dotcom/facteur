# feat(activation): onboarding sans compte — session anonyme convertie à `finalize` (story 31.1)

## Pourquoi

Funnel prod 90 j : **37 % seulement des installs créent un compte**. 82 installs sur 130 (63 %)
n'émettent aucun event produit — médiane 162 secondes, 1 jour d'activité, **0 % de rétention à J1,
J7 et J30**. En face, les 48 activés se rétiennent très bien (J7 77 %, J30 67 %) et l'onboarding
lui-même se termine à 91 %. Le produit ne perd pas ses utilisateurs à l'usage, il les perd avant :
un nouvel install tombait **directement sur `/login`**, zéro exposition produit avant de devoir
créer un compte puis confirmer son email.

Doc : `docs/stories/core/31.1.onboarding-sans-compte.md`. C'est la PR 1 sur 3 du plan d'activation,
celle qui porte l'essentiel du gain ; à mesurer seule avant les deux autres.

## Ce que fait la PR

Le premier lancement ouvre une **session anonyme Supabase** au lieu de rediriger vers `/login`.
L'utilisateur déroule les 13 étapes, et le compte se crée à `finalize` — sur le **même `user.id`**,
donc thèmes, sous-sujets et sources choisis avant le compte restent attachés. Aucun endpoint
dupliqué, aucun buffer local : les écrans `sources` / `swipe` / `subtopics` continuent d'appeler les
endpoints authentifiés existants avec un vrai JWT.

**Mobile**
- `auth_state.dart` : `isAnonymous`, `signInAnonymously()` au cold boot, `convertAnonymousToAccount()`
  (password puis email, sans jamais vider les box locales), `pendingEmailConfirmation` persisté en
  Hive pour survivre à un kill entre conversion et confirmation.
- `routes.dart` : la garde « email non confirmé » se tait pour une session anonyme (et, après
  conversion, le temps que l'écran de conclusion enregistre le profil) ; `/login` reste accessible
  via « J'ai déjà un compte ». Gardes 2b (splash / FLUTTER-2), 5 et 6 intactes.
- `finalize_question.dart` : création de compte (email + mot de passe) ou lien vers `/login`.
- **Instrumentation** : `onboarding_started` / `step_viewed` / `step_completed` / `completed` sur les
  13 étapes (une seule en émettait un jusqu'ici). `$identify` n'est plus émis pour une session
  anonyme — un event `account_created` porte désormais la mesure d'activation.

**Backend**
- `dependencies.py` : accepte le claim `is_anonymous` (et le lit en fallback DB). La garde 403
  historique est inchangée pour un compte réel non confirmé.
- `jobs/purge_anonymous_users.py` (+ scheduler, 4h15 Paris) : supprime les anonymes dont l'onboarding
  n'a pas abouti et inactifs > 30 j, sinon `auth.users` enfle d'une ligne par install.

**Aucune migration Alembic.**

## Points d'attention pour la review

- **Le critère de purge n'est pas « aucun profil »** : les endpoints d'onboarding appellent déjà
  `get_or_create_profile` (c'est ce qui satisfait les FK de `user_subtopics` / `user_interests`), donc
  un profil existe souvent bien avant la fin du parcours. Seul `onboarding_completed = false`
  distingue un abandon.
- **Garde anti-régression** : `_noteRealAccount()` coupe l'auto-signin anonyme dès qu'un vrai compte
  est observé (boot + listener Supabase), pas seulement aux chemins explicites — sinon un login OAuth
  ou une session expirée renverrait un utilisateur historique dans un onboarding vierge.
- `is_anonymous` reste `true` entre la conversion et la confirmation de l'adresse : c'est
  `pendingEmailConfirmation`, persisté, qui marque « le compte existe ».

## À faire côté PO avant merge (dashboard Supabase, hors repo)

1. Activer les **anonymous sign-ins** (Authentication → Providers → Anonymous). Sans ça, le boot
   retombe proprement sur `/login` (comportement actuel), mais la PR n'a aucun effet.
2. Vérifier qu'aucune policy RLS n'expose de données à une session anonyme au-delà de son `auth.uid()`.

## Vérification

- `pytest` (backend) et `flutter test` / `flutter analyze` (mobile) au vert ; baseline mobile connue
  de ~27 échecs préexistants inchangée.
- Nouveaux tests : `tests/test_auth_anonymous_sessions.py`, `tests/test_purge_anonymous_users.py`,
  `test/features/onboarding/onboarding_sans_compte_test.dart`.
- Parcours web complet (premier lancement sans compte → 13 étapes → création du compte → thèmes,
  sous-sujets et sources bien présents après) : à repasser sur staging une fois les anonymous
  sign-ins activés.

**Mesure de succès (6 semaines)** : install → `account_created` de 37 % à 60 %, et apparition d'un
funnel d'étapes exploitable dans PostHog.
# fix(essentiel): sources favorites toujours rendues + attente lisible (PR 1)

## Résumé

PR 1 du plan « Accélérer et fiabiliser l'écran Essentiel » : fiabilise la section
**Sources favorites** (elle disparaissait régulièrement de la Tournée) et rend
l'attente des sections **lisible** (shimmer + libellé unique). 100 % mobile,
**aucune migration**, aucun changement backend.

Doc : `docs/bugs/bug-sources-favorites-absentes.md`

## Le bug (2 races au bootstrap de `FluxContinuNotifier`)

La garde `sourceIsEssentiel` (modèle exclusif Story 10.2) est correcte — le bug
vit ailleurs :

1. **Hydratation avalée** : `reconcileEssentielPlacement` (DB → prefs, ce qui
   *restaure* le placement Essentiel après réinstall / nouveau device) se résout
   presque toujours **pendant** le fan-out, fenêtre où `_bootstrapping` rend les
   listeners de prefs muets ⇒ la section n'apparaissait qu'au **cold boot
   suivant**.
2. **Catalogue lazy** : `userSourcesProvider` non résolu ⇒ `if (src == null)
   continue` dans le seed des coquilles **et** dans le fan-out ⇒ drop silencieux
   du favori pour tout le cycle, sans listener pour le rattraper.

## Changements

- `flux_continu_provider.dart`
  - `_reconcilePlacementThenSync()` : chaîne explicitement le résultat de la
    réconciliation (diff avant/après des sources Essentiel + des clés thème
    Flâner) → `_refetchSourcesOnly` / recompose, sans dépendre des listeners.
    La réconciliation reste non-awaitée avant `_fetchAll` (pas de +2 RTT au cold
    boot) ; idempotent si le listener a déjà agi.
  - `_ensureSourceCatalog()` : résolution best-effort du catalogue (borné 2 s,
    erreur avalée) + re-seed des coquilles, **après** l'émission Phase 1 pour ne
    pas retarder le haut de page. Également appelé en tête de
    `_refetchSourcesOnly`. No-op dans le cas nominal.
  - `_disposed` (via `ref.onDispose`) : garde les continuations async lancées
    depuis `build` (Riverpod 2 n'expose pas `ref.mounted`).
- `section_block.dart` : `SectionSkeletonCard` **shimmer** (mêmes teintes que
  `_MetaShimmer`) + libellé unique « Ta tournée se prépare… » rendu **dans** la
  1ʳᵉ carte squelette (hors ShaderMask, zéro hauteur propre ⇒ géométrie stable
  préservée).
- `flux_continu_screen.dart` : câble `showPreparingLabel` sur la 1ʳᵉ coquille non
  résolue (liste live) et sur la 1ʳᵉ section du cold-skeleton.
- `assets/changelog.json` : entrée « Ma Tournée » (unreleased).

## Tests

- Nouveau `flux_continu_sources_races_test.dart` : une race par test, **les deux
  échouent sans les correctifs** (vérifié en revertant chaque fix).
- `section_block_test.dart` : coquille → N cartes shimmer, libellé seulement si
  `showPreparingLabel`.
- `flutter test` complet + `flutter analyze`.

## Hors périmètre

PR 2 (invalidation ciblée + TTL `feed_cache.py`) et PR 3 (SWR client par section)
du même plan.
# fix(widget): refonte fiabilité du widget d'accueil — 6 causes racines

## Résumé

Les 5 symptômes remontés sur le widget Android ne sont pas 5 bugs indépendants.
Ce sont **6 causes racines**, dont une seule (`applicationId ≠ namespace`)
explique déjà la moitié des plaintes.

Base `main`. **Aucune migration.** Aucun impact backend. Android uniquement
(il n'y a pas de widget iOS : ni extension, ni app group).

Doc complète : `docs/bugs/bug-widget-fiabilite.md`.

## Causes racines et correctifs

### C1 — `home_widget` n'a **jamais** pu atteindre les receivers

`HomeWidgetPlugin.kt` résout un `androidName` nu en
`"${context.packageName}.$className"`, où `context.packageName` est
l'**applicationId** (`com.example.facteur.staging` / `facteur.app`). Les
receivers vivent dans le **namespace** `com.example.facteur`.

⇒ `ClassNotFoundException` sur les deux flavors, à chaque appel, avalé par un
`catch`. Donc : « Ajouter un Widget » mort, et **zéro `ACTION_APPWIDGET_UPDATE`
jamais envoyé** — le widget ne repeignait que sur l'alarme système de 30 min.

Cohérent avec Sentry : **zéro** `PlatformException` remontée (tout est catché).

**Fix** : `qualifiedAndroidName:` sur tous les appels, dérivé du namespace.
Garde anti-régression : un test lit le `namespace` directement dans
`build.gradle.kts` et vérifie qu'il diffère bien des applicationId des flavors.

### C2 — Crash **fatal** sur le chemin de fraîcheur (Sentry FLUTTER-1E, 23 events / 11 users)

`app.dart` faisait `unawaited(ensureWidgetFresh())`, qui `await refresh()` sans
try/catch → l'erreur async n'avait aucun handler → crash *unhandled* via
`PlatformDispatcher.onError`.

**Fix** : try/catch (log Sentry `warning`, pas de rethrow) + `.catchError` sur le
`unawaited`. Feeder amont FLUTTER-6 traité aussi : le timeout de
`SessionRefresher` devient adaptatif (8 s `resumed`, 20 s au cold boot / réveil
par tap widget), les 5 s fixes expiraient systématiquement.

### C3 — Le deep-link widget **déconnectait** l'utilisateur

C'est le vrai « j'ouvre le widget avant ma tournée et ensuite plus rien ne
charge » : ce n'est pas une panne de requêtes, c'est un **`signOut()`**.

La branche deep-link de `routes.dart` retournait sa route **avant** le gate
`authState.isLoading`. Cold-open depuis le widget → le reader se montait alors
que `Supabase.currentSession` était encore `null` → `ApiClient` attendait
**100 ms** puis partait en anonyme → 401 → refresh 5 s en échec au cold boot →
`onAuthError(401)` → `handleSessionExpired` → `signOut()` → `WidgetService.clear()`.

**Fix, en trois points de coupure** :
- `routes.dart` : la branche **seed** le pending et retourne `/splash`. Le bloc 3
  existant le consomme une fois l'auth résolue — le chemin déjà prévu par le
  design. Les auth callbacks restent traités avant les gates (ils portent la
  session que les gates attendent).
- `api_client.dart` : attente de session portée de 100 ms à un budget borné de
  2 s. **Écart assumé au plan** : la requête part quand même en anonyme si le
  budget est épuisé (certains endpoints sont publics ; échouer localement aurait
  été une régression à large rayon). Elle est en revanche **marquée**, et un 401
  sur une requête partie sans header ne déclenche **jamais**
  `handleSessionExpired`.
- `feed_repository.dart` : le cache statique `_defaultViewLastResult` (fenêtre
  5 s) ne mémorise plus une réponse obtenue sans session — il propageait un feed
  dégradé à tous les appelants, widget compris.

Corrige aussi **FLUTTER-Y** (`type 'Null' is not a subtype of type
'Perspective'`, 20 events) : les 9 `state.extra as X?` passent par un helper
unique `extraAs<T>(state)`.

### C4 — Bouton refresh : no-op à froid, effets de bord violents à chaud

- **Cold start** : le flag `refresh=1` était **jeté**. `pendingRoute()` ne
  renvoyait que la route → `_onRefreshRequested` jamais appelé → no-op littéral.
- **À chaud** : `ref.read(digestProvider.notifier)` **construit** le provider,
  dont le `build()` lance `_loadBothDigests` (45 s × 5 retries, ~80 s de chaîne
  réseau pour un tap) et appelle `sereinToggleProvider.initFromApi()` → pouvait
  **basculer le toggle Serein** sous l'utilisateur. Et `refreshForWidget()`
  faisait `state = AsyncData(...)` juste après `router.go('/flaner')` → l'état
  visible était remplacé pendant que `FlanerScreen` se montait. C'est le
  « plante Flâner ».

**Fix** : `pendingAction()` expose l'action complète et `replayRefreshIfRequested()`
rejoue le side-effect (le bouton marche donc au cold start) ;
`container.exists(digestProvider)` avant tout `ref.read(...notifier)` ;
`syncWidgetFromRefresh()` devient **mémoire seule** ; `refreshForWidget()`
**n'écrit plus dans `state`**.

### C5 — « le widget n'affiche que 9 articles »

Les caps sont à 80 partout et le parsing Kotlin est non destructif : **rien ne
tronque à 9**. Le payload contenait réellement ~9 lignes, parce que les pushes
poussaient `state.items` — la liste **visible** de Flâner, qui *rétrécit* au fil
de la lecture (overlay `_consumedContentIds`) — et que rien ne reconstituait la
profondeur.

**Fix** : buffer widget dédié (cap 80), alimenté en **union** dédupliquée et
**découplé** de l'overlay ; lire un article dans l'app ne vide plus le widget.
Le garde de signature passe de `len|first|last` (aveugle à un réordonnancement
du milieu) à **tous** les ids, avec péremption 6 h.

### C6 — Rien ne rafraîchissait le widget app fermée

L'alarme 30 min ne fait que **repeindre les mêmes octets** (`onUpdate` relit
SharedPreferences, aucun réseau). `initWidgetIfNeeded()` était **du code mort**
— zéro appelant → un widget fraîchement épinglé restait vide.

**Fix** : `workmanager` (~1 h, `NetworkType.connected`, `requiresBatteryNotLow`).
Contraintes de conception, toutes tirées des autres causes :
- **Dio nu**, sans les interceptors `onAuthError` : un 401 en tâche de fond ne
  peut pas délogger (leçon de C3) ;
- pas de session restaurable → **abandon silencieux**, jamais de `signOut` ;
- `updateWidgetMergingFlux()` **fusionne** au lieu de remplacer (une page = 20
  articles ; remplacer ferait retomber le payload de 80 à 20, soit exactement
  le symptôme C5) ;
- annulé au logout, à côté de `WidgetService.clear()`.

### CTA « Ajouter le widget »

L'entrée était enterrée dans Compte **et** ne faisait rien. Nouveau bandeau en
tête de Flâner, bâti sur les tokens existants, affiché seulement si aucun widget
n'est épinglé (en cas d'incertitude → masqué). Throttle 7 j via le **registre
unifié des nudges**. `WidgetPinPrompt` rend toujours compte du résultat
(`unsupported` → explication, `failed` → erreur), au lieu du silence d'avant.

## Comment ça a été vérifié

- `flutter analyze` : **0 erreur**. 532 issues, toutes pré-existantes (aucune
  nouvelle sur les fichiers touchés).
- `flutter test` : **1859 passés / 27 échecs**.
  Les 27 échecs sont **exactement la baseline** : vérifié en montant un worktree
  sur `origin/main` et en rejouant les fichiers à risque
  (`router_redirection_test` ×2, `feed_sources_test` ×5, `widget_test` ×1) —
  ils échouent à l'identique sans ce diff.
- Tests ajoutés : garde namespace (lit `build.gradle.kts`), `pendingAction` +
  `refresh=1` au cold start, buffer qui ne rétrécit pas, `refreshForWidget` qui
  ne mute plus `state`, réponse sans session jamais mémorisée.

### Non vérifié — vérification device (la seule qui prouve C1)

Conductor n'a pas de JDK, donc **aucun APK n'a été construit**. C1, C6 et le
CTA d'épinglage ne sont prouvés que par lecture du plugin et des tests de garde.
Le protocole device est écrit dans la doc du bug (§ Vérification) : épingler
depuis le bandeau, `adb logcat -s FacteurWidget:D`, vérifier `count=` > 9 et
croissant, tap refresh app tuée, et le scénario clé « widget avant la tournée →
rester connecté ».

## Zones à risque

- **Auth / Router** (`api_client.dart`, `routes.dart`, `session_refresher.dart`,
  `auth_state.dart`) — cf. Safety Guardrails. Le changement le plus sensible est
  le passage du deep-link widget par `/splash` : à relire en priorité.
- `feed_provider.dart` : `refreshForWidget()` n'écrit plus dans `state` (un test
  existant a été inversé en conséquence, volontairement).
- `_prefetchForWidget` : le bail `!_hasNext` est levé, borné par un **cooldown
  30 min** — sans lui, un compte qui n'a pas 80 articles disponibles relancerait
  4 appels `/api/feed/` à chaque build de feed et chaque retour de premier plan.

## Hors scope (à signaler au PO)

- Crashes **Flux Continu** (FLUTTER-1R/1M/1S/1T/1K/1N, ~30 events fatals sur 5 j)
  et **FLUTTER-1X** (guided tour, marqué *escalating*) : famille distincte,
  workspace dédié.
- **FLUTTER-1D** (trampoline Glance, 3 users, fatal) : la dépendance
  `androidx.glance:glance-appwidget` est confirmée, mais le manifest mergé n'est
  pas inspectable sans JDK. On ne retire pas une activité tierce exportée sans
  preuve. Reste en suivi.

## Après merge sur `main` (staging)

- Sentry `flutter` : **FLUTTER-1E** et **FLUTTER-Y** doivent tomber à zéro ;
  surveiller FLUTTER-6 et FLUTTER-1D.
- Vérifier `widget_last_push_count` (médiane attendue nettement > 9).
