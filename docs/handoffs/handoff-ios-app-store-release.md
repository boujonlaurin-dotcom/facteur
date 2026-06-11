# Handoff: Facteur iOS / App Store Release

**Status date:** June 8, 2026

**Canonical repository:** `/Users/laurinboujon/facteur`

**Flutter application:** `apps/mobile`

**Release status:** signing + TestFlight publishing **configured** (2026-06-08). Unsigned build validated; Bundle ID `app.facteur` set; App Store Connect API key + distribution cert in Codemagic. Next gate = create App Store Connect app record, then run first SIGNED build.

This document preserves the useful context from the May 27, 2026 Codex
sessions and replaces their stale worktree-specific instructions. It is the
starting point for any agent working on iOS release, Codemagic, TestFlight,
App Store Connect, bundle identifiers, signing, or provisioning.

For a new agent running in another environment, use the
[remote-agent recovery prompt](prompt-new-agent-ios-release.md). It starts by
fetching this handoff from GitHub and does not rely on local filesystem paths
or prior chat history.

## Executive Summary

The repository has an initial `codemagic.yaml`, but the release pipeline has
not been proven. Do not ask the product owner to configure certificates or
publish anything yet.

The immediate sequence is:

1. An agent repairs and validates the unsigned Codemagic workflow.
2. The product owner confirms the real Apple bundle ID.
3. An agent applies that confirmed bundle ID and prepares signed-build YAML.
4. The product owner connects Apple credentials in Codemagic.
5. An agent runs and diagnoses the first signed build.
6. The product owner validates the build in TestFlight and completes App Store
   metadata, privacy answers, review information, and submission.

## Verified Current State

These facts were checked in the canonical checkout on June 8, 2026:

> **Re-verification 2026-06-08 (remote agent, from `origin/main` @ `11eaa35a`):** Two facts from the original audit have changed and are corrected in the table below.
> 1. `codemagic.yaml` is **absent** from `origin/main` (never pushed; lived only in the hand-off branch's local commits `3f4db01a`, `26938b1f`).
> 2. `apps/mobile/ios/Podfile` **and** `Podfile.lock` are now **tracked** on `origin/main` — the CocoaPods blocker is resolved. The standalone `pod install` CI step has therefore been dropped from the transplanted `codemagic.yaml` (redundant: `flutter build ipa` runs `pod install` after generating `Generated.xcconfig`).
> Note: the hand-off branch has diverged heavily from `main` (it is missing many docs that exist on `main`); only the iOS context files were cherry-picked, never merged. Bundle ID remains placeholder `com.example.facteur` (RunnerTests: `com.example.facteur.RunnerTests`); iOS deployment target `13.0`; app version `1.0.0+1`.

| Item | Current state | Consequence |
|---|---|---|
| Flutter project | `apps/mobile` | All Flutter commands must run there. |
| App version | `1.0.0+1` | Confirm release version/build number before upload. |
| iOS display name | `Facteur` | No known blocker. |
| Bundle ID | `com.example.facteur` | Placeholder; cannot be used for the real release unless Apple was intentionally configured with it. |
| iOS deployment target | `13.0` | Revalidate against current dependencies during CI build. |
| Signing style | Automatic | No development team is committed in the Xcode project. |
| App icon | 1024x1024 RGB PNG, no alpha | The App Store icon asset is present. |
| Sensitive `Info.plist` usage descriptions | None currently declared | Re-check against actual native features before submission. |
| Flutter toolchain | Local Flutter `3.41.6`, Dart `3.11.4` | Codemagic is pinned to Flutter `3.41.6`. |
| Local Xcode | Full Xcode is not installed/selected | `xcodebuild` and local iOS archive remain unavailable on this Mac. |
| Codemagic config | `codemagic.yaml` is ABSENT from `origin/main` (re-verified 2026-06-08). It only existed in the hand-off branch. | A clean copy is transplanted onto branch `release/ios-app-store-2026-06-08` and must be pushed for Codemagic to consume it. |
| CocoaPods files | `apps/mobile/ios/Podfile` AND `Podfile.lock` ARE tracked on `origin/main` (re-verified 2026-06-08) | Standard Flutter-generated Podfile (46 pods). The standalone `pod install` CI step is now removable; `flutter build ipa` manages pods. |

The working tree also contains unrelated product-owner work in
`apps/mobile/lib/features/feed/widgets/feed_card.dart` and an untracked
`.envrc`. Do not overwrite, stage, commit, or discard those changes as part of
the release work.

## Recovered May 27 Context

The original local iOS attempt established:

- Flutter commands had initially been run outside `apps/mobile`, causing
  `No pubspec.yaml file found`.
- `flutter clean` and `flutter pub get` succeeded from the correct directory.
- The Mac only had Xcode Command Line Tools. Full Xcode was absent, so a local
  iOS release/archive could not be completed.
- The App Store icon was checked as 1024x1024 RGB without alpha.
- The project used the placeholder bundle ID `com.example.facteur`.
- No bundle ID, team, certificate, profile, or App Store setting was to be
  changed without product-owner confirmation.

The later Codemagic attempt established:

- `codemagic.yaml` belongs at the repository root.
- The intended YAML workflow is `ios-release`, with `APP_DIR=apps/mobile`.
- Codemagic had run an auto-detected Android build (`bundleDebug`) instead of
  the YAML iOS workflow.
- Flutter stable then exposed an incompatibility between newer Flutter and
  `phosphor_flutter 2.1.0`, so the workflow was pinned to Flutter `3.41.6`.

Local commits containing that work:

- `3f4db01a` - add initial Codemagic iOS workflow
- `26938b1f` - pin Flutter to `3.41.6`

The current branch has diverged from `main`. A future agent must transplant or
rebuild the release changes on a fresh branch from current `main`; do not
blindly merge the old branch.

## Agent-Owned Work: Do This Before PO Setup

The next agent owns all of the following. Do not hand these technical steps to
the product owner.

### 1. Preserve unrelated local work

Inspect `git status` and isolate release work without losing the existing
`feed_card.dart` and `.envrc` changes. Use a separate worktree or another
non-destructive approach if needed.

### 2. Start from current `main`

Create a fresh release branch from current `main`. Bring over only the intended
Codemagic and documentation changes. Do not merge the old analytics branch as
a whole.

### 3. Repair the unsigned workflow

Resolve the missing CocoaPods project files deliberately. Determine whether to:

- restore a valid Flutter-generated `ios/Podfile` and track it; or
- remove the standalone `pod install` step and let the verified Flutter build
  command manage pods.

Do not guess. Compare with a newly generated Flutter iOS project for the pinned
Flutter version and inspect this project's plugins and Xcode configuration.

Then validate:

```bash
ruby -e 'require "yaml"; YAML.load_file("codemagic.yaml"); puts "YAML OK"'
git diff --check
```

Push the release branch, then in Codemagic manually start:

```text
Branch: the new release branch
Workflow: ios-release
Configuration: codemagic.yaml
```

The first gate is a successful unsigned iOS archive/IPA. Capture the Codemagic
build URL and final artifact names in this document.

### 4. Resolve the Flutter pin debt

For the first build, retain Flutter `3.41.6` unless testing proves another
version works. Separately assess upgrading/replacing `phosphor_flutter 2.1.0`.
Do not combine a broad icon migration with the first CI recovery unless the pin
itself is no longer supported by Codemagic.

### 5. Ask for exactly one Apple decision

After the unsigned build passes, ask the product owner for the exact explicit
bundle ID shown in Apple Developer and App Store Connect. Never infer it from
the app name and never ship `com.example.facteur` by accident.

### 6. Prepare signed build configuration

After the bundle ID is confirmed:

- update the Runner and RunnerTests bundle identifiers consistently;
- preserve the Supabase URL scheme unless an auth-flow change is intended;
- add Codemagic `ios_signing` with `distribution_type: app_store`;
- use the confirmed bundle ID;
- add `xcode-project use-profiles` if required by the selected Codemagic
  signing approach;
- build a signed IPA;
- configure App Store Connect publishing only after credentials exist.

Keep all `.p8`, `.p12`, `.mobileprovision`, passwords, private keys, and tokens
out of Git.

### 7. Verify before TestFlight handoff

Record evidence for:

- exact commit and branch;
- successful unsigned build;
- successful signed build;
- resolved bundle ID and version/build number;
- produced `.ipa`;
- upload result and App Store Connect processing status;
- test account requirements and tested login flow;
- remaining warnings that could affect App Review.

## Product Owner Manual Checklist

Only the product owner should complete account decisions, legal declarations,
2FA, and final submission. Use this checklist in order.

### Gate A: Confirm Apple Account State

- [ ] Open Apple Developer and confirm the membership is active.
- [ ] In App Store Connect, open **Business** and accept any pending agreements.
- [ ] Confirm you have Account Holder or Admin access for identifiers/API keys,
      and App Manager access for the app record.
- [ ] Do not create certificates or profiles yet if the unsigned CI build has
      not passed.

### Gate B: Confirm the Real Bundle ID

In Apple Developer:

1. Open **Certificates, Identifiers & Profiles**.
2. Open **Identifiers**.
3. Find the explicit App ID intended for Facteur.
4. Copy the bundle ID exactly.
5. Confirm whether **Sign in with Apple** and **Push Notifications** are
   enabled for that App ID.

In App Store Connect:

1. Open **Apps** and select Facteur, or create **New App** if it does not exist.
2. Confirm the selected bundle ID is the same exact value.
3. Record the SKU if creating the app; it is internal and cannot be changed
   later.

Send the agent only:

```text
Confirmed Facteur bundle ID: <exact value>
App Store Connect app record exists: yes/no
Sign in with Apple enabled: yes/no
Push Notifications enabled: yes/no
```

Do not send account passwords, private keys, recovery codes, or 2FA codes.

### Gate C: Connect Apple to Codemagic

Do this only after the agent reports a successful unsigned `ios-release`
build.

1. In App Store Connect, open **Users and Access > Integrations**.
2. If API access is not enabled, the Account Holder must request/enable it.
3. Create a team API key with the minimum role needed for upload.
4. Download the `.p8` key immediately and store it in a password manager or
   secure vault; Apple does not offer repeated downloads.
5. In Codemagic, open the team settings/integrations area and add the App Store
   Connect API key using its name, issuer ID, key ID, and private key.
6. Use Codemagic's signing-certificate/provisioning-profile management or
   automatic signing flow for the confirmed bundle ID.
7. Never paste credentials into `codemagic.yaml`, GitHub, an issue, or chat.

Tell the agent:

```text
Codemagic Apple integration name: <name only, no secret>
Signing assets available for bundle ID: yes/no
```

### Gate D: Start the Correct Codemagic Build

In Codemagic:

1. Click **Start new build**.
2. Select the release branch supplied by the agent.
3. Select the YAML workflow **iOS Release** / `ios-release`.
4. Verify the screen says it is using `codemagic.yaml`.
5. Start the build.

Stop immediately if the log shows Android tasks such as `bundleDebug`,
`assembleDebug`, or `Failed to build for Android`. That means the wrong
workflow was selected.

Send the agent the build URL and the first failing step, or confirmation that
the build succeeded. Do not manually edit random build settings to chase an
error; the YAML should remain the source of truth.

### Gate E: TestFlight Validation

After upload:

- [ ] Wait for Apple processing; the build will not appear immediately.
- [ ] Open **App Store Connect > Facteur > TestFlight**.
- [ ] Resolve export compliance prompts.
- [ ] Add internal testers first.
- [ ] Install on a real iPhone.
- [ ] Test account creation, email confirmation, login/logout, Apple/Google
      login if offered, onboarding, feed, article opening, saves, notes,
      notifications, purchases/paywall, account deletion, and privacy links.
- [ ] Record crashes, broken links, placeholder content, and permission prompts.
- [ ] Increment the build number before every replacement upload.

### Gate F: App Store Submission Content

Complete and review:

- [ ] App name, subtitle, description, promotional text, and keywords.
- [ ] Primary/secondary categories.
- [ ] Support URL, marketing URL if used, and a public privacy-policy URL.
- [ ] Required iPhone/iPad screenshots matching supported devices.
- [ ] Age rating questionnaire.
- [ ] App Privacy/data collection answers based on actual Supabase, PostHog,
      Sentry, RevenueCat, authentication, and notification behavior.
- [ ] Encryption/export-compliance answers.
- [ ] Content-rights declaration for aggregated news/content.
- [ ] Review notes explaining the product and any non-obvious flows.
- [ ] A working review account if login is required, with credentials that do
      not expire during review.
- [ ] Account-deletion instructions if users can create accounts.
- [ ] In-app purchase/subscription products and RevenueCat configuration, if
      monetization is enabled in the submitted build.
- [ ] Correct build selected for version `1.0.0` or the final chosen version.

Only the product owner should click **Submit for Review** after the TestFlight
checklist passes and all declarations have been reviewed.

## Stop Conditions

An agent must stop and ask the product owner before:

- choosing or changing the production bundle ID;
- enabling/disabling Apple capabilities;
- creating/revoking API keys, certificates, or profiles;
- changing the Apple development team;
- accepting legal agreements;
- answering App Privacy, export, content-rights, or age-rating declarations;
- inviting external testers;
- submitting the app for review or releasing it.

## Useful Official References

- Codemagic YAML setup:
  https://docs.codemagic.io/yaml-basic-configuration/yaml-getting-started/
- Codemagic iOS signing:
  https://docs.codemagic.io/yaml-code-signing/signing-ios/
- Codemagic App Store Connect publishing:
  https://docs.codemagic.io/yaml-publishing/app-store-connect/
- Apple: register an App ID:
  https://developer.apple.com/help/account/identifiers/register-an-app-id/
- Apple: add an App Store Connect app:
  https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/
- Apple: upload builds:
  https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds

## Progress Log

Update this section after each gate so the next agent never has to reconstruct
the release from chat history again.

| Date | Gate | Evidence/result | Owner |
|---|---|---|---|
| 2026-06-08 | Context recovery | Historical sessions recovered; current checkout re-audited; unsigned pipeline still blocked | Agent |
| 2026-06-08 | Re-verification & repair | Re-audited `origin/main` @ `11eaa35a`: `codemagic.yaml` absent from main, `Podfile`+`Podfile.lock` now tracked. Created `release/ios-app-store-2026-06-08` from `origin/main`; cherry-picked iOS context docs + transplanted `codemagic.yaml` (ios-release) **without** the redundant standalone `pod install` step; `YAML OK`, `git diff --check` clean. **Next blocker:** branch must be pushed (agent env lacks GitHub write auth) then PR to `main`, then PO starts Codemagic `ios-release` build. | Agent |
| 2026-06-08 | Unsigned build GREEN | Codemagic `ios-release` ran from branch `release/ios-app-store-2026-06-08` @ `7cd3c24` and **succeeded**. Root cause of earlier failures: the Codemagic app was in **Workflow Editor** mode and ignored `codemagic.yaml` (kept running Android `bundleDebug`); switching the app to the `codemagic.yaml` configuration fixed it. Artifact produced: **`Runner.xcarchive`** (no `.ipa` yet — expected with `--no-codesign`). Build URL: https://codemagic.io/app/6a172956214718f6bc6c35dd/build/6a26d0b52c6644c9dbd30c25 . **Next blocker:** production Bundle ID still `com.example.facteur` (placeholder) — needs PO confirmation before signing. **Next agent action:** open PR to `main`; after Bundle ID confirmed, update Runner/RunnerTests IDs + add `ios_signing` (app_store). **Next PO action:** Gate B — confirm exact Bundle ID + Sign in with Apple / Push status. | Agent + PO |
| 2026-06-08 | Bundle ID set | App ID `app.facteur` registered in Apple Developer (Sign in with Apple ON; Push intentionally OFF — app uses local notifications only, no FCM/APNs). Project bundle ids updated: Runner `app.facteur`, RunnerTests `app.facteur.RunnerTests` (commit `4e63c847`). Android applicationId left unchanged (out of scope). | Agent + PO |
| 2026-06-08 | Signing configured | App Store Connect API key `facteur_asc` (App Manager) + Apple Distribution cert `facteur_distribution` created in Codemagic by PO. `codemagic.yaml` updated (commit `2f4a5d1d`): `integrations.app_store_connect: facteur_asc`, `ios_signing` (app_store / app.facteur), `xcode-project use-profiles`, signed `flutter build ipa`, `publishing.app_store_connect.submit_to_testflight: true`. YAML OK. | Agent + PO |
| 2026-06-09 | Catch-22 signature identifié | Avec `ios_signing` → `No matching profiles found` (le préambule Codemagic cherche le profil AVANT les scripts et s'arrête) ; sans → `Cannot save ... private key`. Racine commune : **aucun provisioning profile App Store n'existe pour app.facteur**, et ni la CLI ni l'UI Codemagic ne le créent dans cette config. Décision : **créer le profil une fois côté Apple Developer Portal** (PO), puis le **Fetch** dans Codemagic ; ios_signing le trouvera ensuite. YAML remis au propre : `ios_signing(distribution_type=app_store/app.facteur)` + script `xcode-project use-profiles` seul (CLI `--create` retirée). **Next PO :** (1) Apple Portal > Profiles > + > App Store > app.facteur > certif distribution > Generate ; (2) Codemagic > Code signing identities > iOS provisioning profiles > Fetch from Developer Portal > sélectionner le profil + reference name ; (3) relancer le build. | Agent |
| 2026-06-09 | Fix clé privée cert | Intégration `facteur.app` OK, mais build échoue à l'étape signature : `Cannot save Signing Certificates without certificate private key`. Cause : en mode 100% CLI, `fetch-signing-files` récupère le certif côté Apple (partie publique) sans clé privée. Fix : **réintroduction du bloc `ios_signing: distribution_type=app_store / bundle_identifier=app.facteur`** (importe le cert uploadé `facteur_distribution` + sa clé privée dans le trousseau), et l'étape ne fait plus que créer le **profil** manquant via `fetch-signing-files --create` (sans `keychain initialize` qui réinitialisait le trousseau). YAML OK. **Si échec persistant :** fallback = fournir `CERTIFICATE_PRIVATE_KEY` en var chiffrée Codemagic, ou laisser la CLI créer un cert neuf. **Next PO :** relancer le build (commit à venir). | Agent |
| 2026-06-08 | Fix nom intégration ASC | Build a échoué runtime : `App Store Connect integration "facteur_asc" does not exist`. Le nom réel de l'intégration Developer Portal dans Codemagic est **`facteur.app`** (Key ID `TCKZST98Q4`), pas `facteur_asc`. Fix : `integrations.app_store_connect` passe à `facteur.app` (la publication TestFlight `auth: integration` réutilise la même). YAML OK. **Next PO :** relancer le build. | Agent + PO |
| 2026-06-08 | Signing fix v2 (YAML valide) | Le 1er essai de fix a été rejeté au pré-build : `ios_signing -> Either distribution profile and bundle identifier or provisioning profiles (and optionally certificates) must be provided` (le bloc `ios_signing` n'accepte pas `certificates` seul, et ne CRÉE jamais — il ne fait que récupérer des fichiers existants). Doc confirmée : la création auto cert+profil en YAML passe **uniquement** par la CLI. Fix v2 : **suppression du bloc `ios_signing`** ; signature 100% CLI via `keychain initialize` + `app-store-connect fetch-signing-files "app.facteur" --type IOS_APP_STORE --create` + `keychain add-certificates` + `xcode-project use-profiles`. L'intégration `facteur_asc` fournit l'auth API. YAML OK. **Note dette technique :** `--create` peut générer un certificat de distribution géré par Codemagic (Apple en autorise 3) ; à consolider plus tard (uploader le cert managé + repasser en mode référence) si on multiplie les builds. **Next PO :** relancer le build `ios-release`. | Agent |
| 2026-06-08 | Signing fix (profile) | 1er build signé a échoué : `No matching profiles found for bundle identifier "app.facteur" and distribution type "app_store"`. Cause : aucun provisioning profile App Store n'existait pour `app.facteur` ; le mode `ios_signing: distribution_type+bundle_identifier` ne récupère que des profils **existants** et n'en crée pas. Fix (commit à venir) : `codemagic.yaml` — `ios_signing` référence désormais le cert `facteur_distribution`, et l'étape de signature appelle `keychain initialize` + `keychain add-certificates` + `app-store-connect fetch-signing-files "app.facteur" --type IOS_APP_STORE --create` + `xcode-project use-profiles`. `--create` crée le profil App Store manquant via l'intégration `facteur_asc`. YAML OK, `git diff --check` clean. **Next PO action :** relancer le build `ios-release` sur `release/ios-app-store-2026-06-08`. | Agent + PO |
| 2026-06-08 | NEXT | **PO:** create App Store Connect app record for `app.facteur` (name, FR, SKU) — required before TestFlight upload. **Then:** start Codemagic `ios-release` on `release/ios-app-store-2026-06-08` → first signed build + TestFlight upload. **Agent:** diagnose build, then guide TestFlight validation + App Privacy + metadata. See `prompt-finish-ios-release.md`. | PO + Agent |
| 2026-06-09 | Cause racine signature : 0 certificat | Découverte : **aucun certificat de distribution n'existait réellement** sur le portail Apple (le `facteur_distribution` historique n'avait jamais abouti) — d'où tous les échecs précédents. Résolution : cert de distribution **généré par Codemagic** (Team settings > Code signing identities > Generate, type *Apple Distribution*, ref `facteur_distribution`, cert id **`YSV9476793`**, clé privée détenue par Codemagic). | PO |
| 2026-06-09 | Profil App Store créé + fetché | Profil **« Facteur App Store »** créé côté Apple (app `app.facteur`, lié au cert distrib) puis **fetché dans Codemagic** (onglet iOS provisioning profiles, reference name `facteur_app_store`, coche verte Certificate). Le YAML `febc247` (`ios_signing distribution_type` + `use-profiles`) dispose enfin de cert + profil. | PO |
| 2026-06-09 | Build signé GREEN + upload ASC | Build Codemagic `ios-release` @ `febc247` **vert** : IPA compilée, signée, **uploadée vers App Store Connect** (`submit_to_testflight: true`). App Apple ID **6778094299**. Fin de la saga signature. | Agent + PO |
| 2026-06-09 | Rejet traitement Apple ITMS-90683 | Le build (1.0.0 build 1) a été uploadé mais **rejeté au traitement** Apple → absent de TestFlight. Mail Apple : `ITMS-90683` **bloquant** = `NSMicrophoneUsageDescription` manquant dans `Info.plist` (référencé par `just_audio`, lecteur de podcasts — l'app n'enregistre pas de son) ; warning non-bloquant = `NSLocationAlwaysAndWhenInUseUsageDescription`. | Agent + PO |
| 2026-06-09 | Fix Info.plist + bump build | **Agent :** ajout de `NSMicrophoneUsageDescription` (purpose string honnête : pas d'enregistrement, requis par le lecteur audio) dans `apps/mobile/ios/Runner/Info.plist`. Clé Location *Always* volontairement **non** ajoutée (warning non-bloquant, on garde la surface de permission minimale). Build number bumpé `1.0.0+1` → **`1.0.0+2`** (pubspec) pour éviter un rejet *redundant binary*. plist parse OK. **Next PO :** relancer le build `ios-release` sur la branche (commit à venir), surveiller le traitement Apple → apparition dans TestFlight. | Agent |
| 2026-06-09 | Build (2) PASSE le traitement Apple | Rebuild `ios-release` avec le fix : build **1.0.0 (2)** (id `88ac4768-7c51-46a8-8daf-e1daabe8329e`) **uploadé ET traité avec succès** par App Store Connect (plus de rejet ITMS). La saga signature + processing est close. Seule l'étape Codemagic *submit to TestFlight beta review* a échoué — mais c'est la voie **externe** (review Apple) qui exige Beta App Information (feedback email) + Beta App Review Information (nom, tel, email). Non bloquant pour le **test interne**. | Agent + PO |
| 2026-06-09 | Export compliance tranchée | Audit code : **aucune dépendance crypto** (pas de encrypt/pointycastle/cryptography/libsodium), seulement HTTPS/TLS standard → **exempté**. Ajout de `ITSAppUsesNonExemptEncryption = false` dans `apps/mobile/ios/Runner/Info.plist` (commit à venir) pour ne plus jamais être prompté + ne plus bloquer sur *Missing Compliance*. ⚠️ Le build (2) déjà uploadé n'a pas ce flag → répondre **une fois** à la question compliance dans ASC pour le débloquer. ⚠️ Le **prochain rebuild devra bumper en `1.0.0+3`** (le +2 est déjà uploadé). **Next PO :** répondre compliance sur build (2) + s'ajouter en testeur interne + installer TestFlight. | Agent + PO |
| 2026-06-10 | Crash lancement iPhone (flutter_downloader) | Build (2) traité par Apple mais **crash au lancement sur iPhone réel**. Cause racine : `main.dart` appelait `_initDownloaderSafe()` → `FlutterDownloader.initialize()` **sans garde plateforme**, sur iOS aussi. Or `flutter_downloader` exige `setPluginRegistrantCallback` dans `AppDelegate.swift` (absent) → **fatalError natif Swift au lancement**, non rattrapable par le `try/catch` Dart. La feature `app_update` (MAJ par APK) est déjà gardée `!Platform.isAndroid` partout ailleurs (modal, button, provider) — seul l'init manquait. **Fix (agent) :** early-return `if (kIsWeb || !Platform.isAndroid) return;` dans `_initDownloaderSafe()` → aucune init downloader sur iOS, aucun changement natif requis. Build number bumpé **`1.0.0+2` → `1.0.0+3`** (le +2 est déjà uploadé). `git diff --check` clean. **Next PO :** pousser la branche (device flow), relancer le build `ios-release`, réinstaller via TestFlight, confirmer que l'app s'ouvre. | Agent |
| 2026-06-11 | Rebuild release sur main courant (app à jour) | Constat structurel : `release/ios-app-store-2026-06-08` était un **snapshot du 8 juin** (cut ~`11eaa35a`) ; `main` avait **1258 commits d'avance** (dont l'onboarding mergé en #826, HEAD `8ea627d4`). Les builds 1-3 livraient donc une app **périmée**. `main` n'avait **aucune** config iOS (codemagic.yaml absent, bundle id `com.example.facteur`, pas de clés Info.plist micro/compliance, pas le guard flutter_downloader, version `1.0.0+1`). **Fix (agent, feu vert PO) :** branche release **recréée = `main` courant + delta iOS** (codemagic.yaml verbatim, bundle id `app.facteur`/`app.facteur.RunnerTests`, `NSMicrophoneUsageDescription` + `ITSAppUsesNonExemptEncryption=false`, guard `if (kIsWeb || !Platform.isAndroid) return;`), **bump `1.0.0+4`** (le +3 est uploadé). Permissions natives de main scannées : seulement `just_audio` (micro, géré) + `geolocator` (location déjà déclarée) → pas de nouveau motif ITMS. Même **nom de branche** conservé (force-update) → config Codemagic inchangée. `git diff --check` clean, YAML OK. **Next PO :** relancer le build `ios-release` → build (4) = app actuelle + onboarding ; internes l'ont auto. Pour externes : Beta App Review + Beta App Information à remplir. **Sujet ouvert séparé :** mail de confirmation d'inscription (signUp Supabase) non reçu par un testeur externe → à diagnostiquer (deliverability/SMTP Supabase). | Agent + PO |
