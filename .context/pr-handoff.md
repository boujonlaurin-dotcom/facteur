## feat(android): In-App Updates Play Store (flavor playstore) + gate par flavor

### Pourquoi
Sur le flavor `playstore` (`facteur.app`), Google interdit l'auto-update par APK : la
permission `REQUEST_INSTALL_PACKAGES` a été retirée (#892) et l'updater maison est inopérant.
Un user Play Store n'avait donc **aucun** signal natif « mise à jour disponible ». Cette PR
ajoute les **Google Play In-App Updates** sur le chemin playstore, en laissant le chemin
`beta` (side-load APK) strictement inchangé.

### Ce que fait la PR
- **Dépendance** : ajoute `in_app_update: ^4.2.3` (résolu 4.2.5 ; Android-only).
- **Point de décision unique** : `PlayStoreUpdateService.checkAndStart()`
  (`lib/features/app_update/services/playstore_update_service.dart`). Routage piloté par le
  flavor via `AppUpdateConstants.isPlayStoreBuild` (no-op total sur beta/dev). Garde
  `kIsWeb`/`Platform.isAndroid`, anti-ré-entrance `_inFlight`, fail-silently.
  - `updatePriority >= 4` + `immediateUpdateAllowed` → `performImmediateUpdate()` (bloquant).
  - sinon `flexibleUpdateAllowed` → `startFlexibleUpdate()` + `completeFlexibleUpdate()`.
- **Lifecycle** (`lib/app.dart`) : appel au **cold-start** (post-frame de `initState`) et au
  **retour foreground** (`didChangeAppLifecycleState` → `resumed`). Réutilise l'observer
  existant, aucun nouvel observer.
- **Doc** : `docs/maintenance/maintenance-playstore-in-app-updates.md` (routage par flavor +
  procédure Play Console `updatePriority` + constat Mission B).
- **Changelog** : entrée `unreleased` « Mise à jour ».

### Décisions
- immediate vs flexible piloté par **Play Console `updatePriority`** (reco Google, 0 backend).
  `app_config` (Supabase) ne porte pas de min-version Android → aucun champ ajouté.
- `flutter_downloader`/`open_filex` **conservés** (partagés avec beta). Sur playstore leur
  chemin n'est plus atteint ; `READ_MEDIA_*` déjà strippé app-wide dans `src/main` (Mission B).

### Vérifs locales
- `flutter pub get` OK ; `flutter analyze` (fichiers touchés) : 0 issue.
- `flutter test test/features/app_update` : 8/8 ✅.
- Plugin natif enregistré (GeneratedPluginRegistrant régénéré).
- Manifests playstore (retrait `REQUEST_INSTALL_PACKAGES`) / beta (ajout) inchangés.

### À faire côté PO (device réel)
- Track de test Play : publier une version supérieure → vérifier l'invite native (immediate
  si `updatePriority >= 4`, sinon flexible). Décompiler le build playstore → aucun chemin
  d'install APK atteignable.
- Build `beta` side-load → flux APK identique à avant.

### Hors scope
iOS (gate iOS séparé existant), champ min-version backend, retrait de dépendances.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
