# Maintenance — Mises à jour par flavor (Play In-App Updates + APK maison)

> Mission A-Android. Branche le comportement d'update **par flavor** côté Dart et intègre
> les **Google Play In-App Updates** sur le flavor `playstore`.

## Routage par flavor

Le routage est piloté par le flavor (`AppUpdateConstants.isPlayStoreBuild`, injecté via
`--dart-define=PLAYSTORE_BUILD=true` par le build AAB), **pas** par une condition runtime
fragile.

| Flavor       | applicationId                   | Mécanisme d'update                                            |
|--------------|---------------------------------|--------------------------------------------------------------|
| `beta`       | `com.example.facteur.staging`   | Updater **APK maison** (`flutter_downloader` + `open_filex`), permission `REQUEST_INSTALL_PACKAGES` (`src/beta/AndroidManifest.xml`). Inchangé. |
| `playstore`  | `facteur.app`                   | **Google Play In-App Updates** (`in_app_update`) — invite native. Aucun chemin APK atteint. |

### Chemin `playstore`
- `PlayStoreUpdateService.checkAndStart()`
  (`lib/features/app_update/services/playstore_update_service.dart`) est le **point de
  décision unique**. Appelé depuis `lib/app.dart` :
  - au **cold-start** (post-frame callback de `initState`) ;
  - au **retour foreground** (`didChangeAppLifecycleState` → `resumed`).
- Garde stricte en tête : no-op si `kIsWeb`, non-Android, ou non-`isPlayStoreBuild`. Garde
  anti-ré-entrance (`_inFlight`) car le check est déclenché deux fois.
- `InAppUpdate.checkForUpdate()` → si MàJ dispo :
  - `updatePriority >= 4` **et** `immediateUpdateAllowed` → `performImmediateUpdate()`
    (flux **bloquant** plein écran géré par le Store) ;
  - sinon `flexibleUpdateAllowed` → `startFlexibleUpdate()` puis `completeFlexibleUpdate()`
    (téléchargement **en fond**, install à la complétion).
- Fail silently : un check d'update ne doit jamais bloquer/casser l'app (ex. user qui
  refuse l'immediate update).

### Chemin `beta`
Strictement inchangé. Le provider `appUpdateProvider`
(`lib/features/app_update/providers/app_update_provider.dart`) gate déjà les builds
playstore (`if (AppUpdateConstants.isPlayStoreBuild) return null;`) → le bouton maison ne
s'affiche que sur beta. `PlayStoreUpdateService` est un no-op hors playstore.

## Play Console — fixer immediate vs flexible

Pas de source de vérité backend/Supabase (`app_config` ne porte que `nudges_enabled`).
La distinction immediate/flexible est pilotée par **`updatePriority`** (0-5), fixée
**par release dans la Play Console** :
- `>= 4` → MàJ **bloquante** (immediate) — réservé aux correctifs critiques ;
- `< 4` → MàJ **flexible** (par défaut), non bloquante.

Le seuil est la constante `PlayStoreUpdateService.kImmediateUpdatePriority` (= 4).

## Lien Mission B — permissions / dépendances

Sur `playstore`, le chemin APK (`flutter_downloader` / `open_filex`) n'est **plus atteint**
(gaté par `isPlayStoreBuild` dans `appUpdateProvider` + `PlayStoreUpdateService` no-op).

**Aucun retrait de dépendance nécessaire ni souhaité** :
- `flutter_downloader` et `open_filex` restent au `pubspec.yaml` car **partagés avec le
  flavor beta** (side-load APK, seul moyen hors store).
- Les permissions `READ_MEDIA_*` qu'`open_filex` injecte sont déjà **neutralisées app-wide**
  dans `src/main/AndroidManifest.xml` (`tools:node="remove"`, cf. #892 / Mission B). Elles
  ne réapparaissent donc pas sur le build playstore.
- `in_app_update` n'exige **aucune** permission ni `REQUEST_INSTALL_PACKAGES` (l'install
  passe par le Play Store) → rien à ajouter dans `src/playstore/AndroidManifest.xml`.

## Vérification

- **playstore** (track de test Play) : publier une version supérieure → invite native
  apparaît. `updatePriority >= 4` → flux immediate bloquant ; sinon flexible (download fond
  + invite d'install). Décompiler → aucun chemin d'install APK atteignable.
- **beta** (side-load) : flux APK maison identique à avant.
