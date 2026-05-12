# Story web.1 : Modal "Ajouter à l'écran d'accueil" pour iOS Safari

## Status: In Progress

## Story

**As a** utilisateur iOS qui accède à Facteur via Safari (et non l'app native),
**I want** être guidé clairement pour ajouter Facteur à mon écran d'accueil,
**so that** je retrouve l'app d'un geste, sans avoir à retaper l'URL ou chercher l'onglet — et je profite du chrome PWA (standalone, sans barre Safari).

## Context

### Problème produit

Les utilisateurs iOS arrivent souvent sur Facteur via le web (lien partagé, recherche, marque-page). Sur Safari iOS, le site n'est pas une "app" : à chaque retour, ils doivent retaper `facteur.app` ou fouiller dans leurs onglets — friction qui dégrade la rétention sur ce segment.

Le PWA est correctement configuré (`manifest.json` `display: standalone`, `apple-touch-icon`, `apple-mobile-web-app-capable`), mais aucun nudge n'incite à l'install. Or :

- **iOS Safari ne supporte PAS `beforeinstallprompt`** : impossible de déclencher programmatiquement le Share Sheet ni "Ajouter à l'écran d'accueil". Seule Android Chrome le permet.
- L'unique levier produit : une modal pédagogique claire (3 étapes visuelles) au bon moment.

### Solution

- À la prochaine ouverture web pour un utilisateur **iOS Safari non standalone** (= pas déjà installé en PWA), afficher une modal pédagogique immédiatement après auth, avant l'arrivée sur le feed.
- 3 étapes visuelles : 1) Toucher le bouton Partage de Safari, 2) Choisir "Sur l'écran d'accueil", 3) Confirmer.
- CTAs : « C'est fait » (marque seen permanent) / « Plus tard » (snooze 7 jours).
- Gating via `FirstImpressionSlot` (mécanisme déjà en place pour notif modal, re-nudge, well-informed) → au plus un overlay/session.
- Persistance via `NudgeStorage` (SharedPreferences) → snooze 7 jours.

### Out-of-scope

- Android Chrome / desktop / autres navigateurs : pas de modal (cible iOS Safari uniquement, choix explicite).
- App native iOS : pas de modal (`kIsWeb=false` short-circuit).
- iPadOS Safari (UA macOS depuis iOS 13) : pas de détection fiable, accepté.
- Automatisation de l'install : impossible techniquement sur iOS Safari.

## Acceptance Criteria

1. ✅ Un utilisateur iOS Safari non-standalone voit la modal au prochain load post-auth.
2. ✅ Un utilisateur Android, desktop, Chrome iOS (UA `CriOS`), Firefox iOS (`FxiOS`), Edge iOS (`EdgiOS`) ne voit pas la modal.
3. ✅ Un utilisateur déjà en PWA (`navigator.standalone === true`) ne voit pas la modal.
4. ✅ Un utilisateur sur l'app native (iOS ou Android) ne voit jamais la modal (`kIsWeb=false`).
5. ✅ Tap « C'est fait » → modal fermée, jamais réaffichée (seen permanent).
6. ✅ Tap « Plus tard » → modal fermée, réapparaît 7+ jours plus tard si non installé.
7. ✅ Au plus une modal premier-impact par session : si la modal s'affiche, les autres nudges (re-nudge banner, well-informed) sont skippés cette session.
8. ✅ Copy aligné design system : `FacteurTypography.displayMedium` pour le titre, `bodyMedium`/`labelLarge` pour le reste, `FacteurColors` pour les couleurs.
9. ✅ Tone aligné Facteur : 2e personne pluriel, clair, calme, sans urgence ("Gardez Facteur à portée de main", "Pour le retrouver d'un geste").
10. ✅ Analytics : événements `ios_add_to_home_shown`, `ios_add_to_home_confirmed`, `ios_add_to_home_dismissed`.
11. ✅ Tests verts : `flutter test`, `flutter analyze`.

## Plan technique

### Détecteur (apps/mobile/lib/core/web/ios_safari_install.dart)

- Index avec conditional import : stub mobile (`=> false`) / impl web (`ios_safari_install_web.dart`).
- Web : lit `window.navigator.userAgent` + `(navigator as JSAny).standalone` via `package:web` + `dart:js_interop`.
- Règles : `kIsWeb` ET (UA contient `iPhone|iPad|iPod`) ET (UA contient `Safari`) ET (UA NE contient PAS `CriOS|FxiOS|EdgiOS`) ET (`navigator.standalone !== true`).

### Nudge (apps/mobile/lib/core/nudges/)

- `nudge_ids.dart` : `static const iosAddToHome = 'ios_add_to_home';`
- `nudge_registry.dart` : Nudge avec `frequency: cooldown`, `cooldown: 7d`, `priority: normal`, `surface: global`, `placement: modal`.

### Provider (apps/mobile/lib/features/onboarding/providers/ios_add_to_home_provider.dart)

- `iosAddToHomeShouldShowProvider` : Provider<bool> combinant détecteur + `NudgeService.canShow(NudgeIds.iosAddToHome)` (qui gère lui-même seen + cooldown).
- `iosAddToHomeConsumedThisSessionProvider` : `StateProvider<bool>` pour bloquer une 2e ouverture en session.

### Orchestrateur (apps/mobile/lib/core/orchestration/first_impression_orchestrator.dart)

- Ajouter `iosAddToHome` à l'enum `FirstImpressionSlot`, **en première position** après `none` (priorité max : c'est la seule modal pertinente sur web, où `notifModal` est gaté off par `kSupportsPushNotifications=false`).
- Branche dans `firstImpressionSlotProvider` avant `notifModal`.

### Modal (apps/mobile/lib/features/onboarding/widgets/ios_add_to_home_sheet.dart)

- `showIosAddToHomeSheet(context, ref)` → `showDialog<void>` translucide, pattern emprunté à `notification_activation_modal.dart`.
- Contenu : titre + sous-titre + 3 étapes avec icônes (Phosphor `shareNetwork`, `plusSquare`, `checkCircle`) + boutons.
- Sur tap « C'est fait » : `nudgeService.markSeen(iosAddToHome)` + analytics confirmed.
- Sur tap « Plus tard » : `nudgeService.markShown(iosAddToHome)` (déclenche cooldown 7j) + analytics dismissed.

### Trigger (apps/mobile/lib/features/feed/screens/feed_screen.dart)

- Étendre `_maybeShowActivationModal(slot)` (l. 210) en switch sur le slot.
- `case iosAddToHome` → `showIosAddToHomeSheet` puis flip `iosAddToHomeConsumedThisSessionProvider = true`.

### Analytics (apps/mobile/lib/core/services/analytics_service.dart)

- 3 nouvelles méthodes : `trackIosAddToHomeShown`, `trackIosAddToHomeConfirmed`, `trackIosAddToHomeDismissed`.

## Files Modified

### Created

- `apps/mobile/lib/core/web/ios_safari_install.dart` (index)
- `apps/mobile/lib/core/web/ios_safari_install_stub.dart`
- `apps/mobile/lib/core/web/ios_safari_install_web.dart`
- `apps/mobile/lib/features/onboarding/providers/ios_add_to_home_provider.dart`
- `apps/mobile/lib/features/onboarding/widgets/ios_add_to_home_sheet.dart`
- `apps/mobile/test/features/onboarding/ios_add_to_home_sheet_test.dart`

### Modified

- `apps/mobile/lib/core/nudges/nudge_ids.dart`
- `apps/mobile/lib/core/nudges/nudge_registry.dart`
- `apps/mobile/lib/core/orchestration/first_impression_orchestrator.dart`
- `apps/mobile/lib/features/feed/screens/feed_screen.dart`
- `apps/mobile/lib/core/services/analytics_service.dart`

## Test Plan

- **Unit/widget tests** : `test/features/onboarding/ios_add_to_home_sheet_test.dart` — rendering, CTAs, persistance via mock NudgeStorage.
- **Manual web (Chrome devtools, UA iPhone Safari)** : afficher / dismiss / snooze 7j.
- **Manual native** : flutter run iOS device → la modal n'apparaît jamais.
- **Edge cases** : UA `CriOS`, `FxiOS`, Android, mode standalone — pas de modal.
