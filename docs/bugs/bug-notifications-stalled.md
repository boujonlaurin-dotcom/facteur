# Bug — Notifs Android qui ne s'envoient plus

**Statut** : root cause PROUVÉ (2026-07) — fix repo livré, runbook ops à exécuter.
**Plateforme** : Android.
**Date du signal** : 2026-05-05.

---

## ✅ Root cause PROUVÉ (2026-07) — Firebase Android jamais configuré

Le chemin push n'a **jamais** transporté un seul message : la « notif du jour » est
cassée **depuis le premier jour sur les stores**. Les PRs #768, #848, #919, #935 ont
toutes poli soit la **notif locale de repli**, soit l'**instrumentation** — jamais la
cause réelle.

### Preuve (pas une hypothèse)

- **PostHog `push_register` (60 j)** : 376 événements, **100 % `outcome = exception`,
  `reason = PlatformException`** (`platform = android`, 9 users). Zéro `token_null`,
  zéro `endpoint_error` (503), zéro `registered`.
- **DB prod (Supabase)** : `push_devices = 0`, `push_deliveries = 0`, depuis toujours.
- **Cause** : `ServerPushService.initAndRegister()` appelle `Firebase.initializeApp()`
  (`apps/mobile/lib/core/services/server_push_service.dart:91`) qui **lève une
  `PlatformException` sur chaque appareil** → tout le flux meurt dans le `catch` →
  100 % des users retombent sur la notif locale.
  Pourquoi ça throw : `apps/mobile/android/app/build.gradle.kts` n'appliquait le
  plugin `com.google.gms.google-services` que si un `google-services.json` existait
  dans `src/prod/` ou `src/staging/`. Or **les vrais flavors sont `beta` et
  `playstore`** (chemins qui ne matchent pas), **et aucun `google-services.json`
  n'existait nulle part** → plugin silencieusement sauté → aucune ressource
  `google_app_id` dans l'APK → Firebase natif sans options par défaut → `PlatformException`.

### « Limite du Play Console ? » → Non

FCM ne dépend d'aucun réglage Play Console et **ne requiert pas** d'empreinte
SHA-1/SHA-256 (celles-ci ne servent qu'à Firebase Auth / Dynamic Links). Deux vraies
lacunes de config, jamais satisfaites :
1. **Firebase Console + build Android (bloqueur ACTIF)** : `facteur.app` et
   `com.example.facteur.staging` jamais enregistrés dans un projet Firebase → aucun
   `google-services.json` embarqué → `PlatformException`.
2. **Railway backend (bloqueur LATENT)** : `FIREBASE_SERVICE_ACCOUNT_*` non défini →
   `PUT /api/devices` renvoie 503 (`packages/api/app/routers/push_devices.py:43-50`)
   et le dispatcher reste désactivé. Pas encore atteint car le client meurt avant.

### Fix repo livré (PR de durcissement)

- **Garde-fou Gradle corrigé + durci** (`build.gradle.kts`) : détecte les vrais
  chemins `src/beta/` + `src/playstore/` (+ fallback `app/`), applique le plugin
  s'ils existent, et **`throw GradleException`** sur un build release/bundle si aucun
  `google-services.json` n'est présent → impossible de re-livrer en silence une app
  « push morte ». Debug/dev restent tolérants.
- **`google-services.json` commités par flavor** (`src/beta/`, `src/playstore/`) — non
  secret pour Android. Fournis via le runbook ci-dessous.
- **Télémétrie d'exception enrichie** (`server_push_service.dart`) : le `catch`
  capture désormais `error: e.toString()` (tronqué ~300 car.) → le message natif exact
  (ex. « no default options ») devient visible dans PostHog.
- **Filet CI** dans `build-aab.yml` / `build-apk.yml` / `weekly-release.yml` : vérifie
  la présence du `google-services.json` du flavor avant le build (échec tôt et lisible).

### Runbook ops (à exécuter, hors code)

**A. Firebase Console (déblocage n°1)**
1. Ouvrir/créer le projet Firebase de Facteur.
2. Add app → Android pour `facteur.app` → télécharger `google-services.json` →
   `apps/mobile/android/app/src/playstore/` (commit dans la PR de durcissement).
3. Add app → Android pour `com.example.facteur.staging` → `google-services.json` →
   `apps/mobile/android/app/src/beta/`.
4. FCM v1 est activé par défaut ; **aucune** empreinte SHA nécessaire pour le push.

**B. Railway (déblocage n°2)**
1. Firebase Console → Project settings → Service accounts → Generate new private key.
2. `base64 -i service-account.json` → coller dans **`FIREBASE_SERVICE_ACCOUNT_BASE64`**
   sur les 2 services : `api-staging-40d3` **et** `facteur-production` (même service
   account couvre les 2 packages du même projet Firebase).
3. Redéployer les 2 services (le dispatcher lit `_firebase_configured()` au boot).

**C. Release** : merger la PR (avec les 2 JSON) → `build-aab.yml` (playstore) → Play
Console Internal testing ; beta part automatiquement au merge sur `main`.

### Vérification end-to-end

1. PostHog : `registered` apparaît, `exception` s'effondre.
2. Supabase : `select count(*) from push_devices where revoked_at is null` > 0.
3. `PUT /api/devices` renvoie 200 (logs Railway : plus de « Push serveur non configuré »).
4. Supabase : `push_deliveries` avec `status='sent'` > 0.
5. Réception device (fenêtre 07:30–12:00 locale) avec bullets (`BigTextStyle` data-only).
6. Anti-régression : renommer un `google-services.json` en local + build release → doit
   **échouer** avec le message du garde-fou.

### Gap iOS parallèle (hors périmètre immédiat)

Le même schéma existe côté iOS : `Firebase.initializeApp()` a besoin de
`GoogleService-Info.plist` + une clé APNs uploadée dans Firebase. La preuve prod est
**Android only** (`facteur.app`). À traiter en second temps si push iOS voulu ; ne
bloque pas la PR Android.

---

## Historique d'investigation (2026-05, avant preuve du root cause)

## Signal

Un beta-testeur Android constate qu'il ne reçoit plus la notification quotidienne « depuis quelques jours ».

PostHog (14 j) confirme un drop net :

| Date | DAU | digest_opened (count) | digest_opened (uniq users) |
|------|-----|------------------------|----------------------------|
| 2026-04-29 | 18 | 39 | 14 |
| 2026-04-30 | 14 | 45 | 11 |
| **2026-05-01** | **16** | **13** | **7** |
| 2026-05-02 | 9 | 7 | 3 |
| 2026-05-03 | 10 | 11 | 4 |
| 2026-05-04 | 15 | 8 | 4 |
| 2026-05-05 | 14 | 17 | 7 |

DAU stable (9–18/j), `digest_opened` divisé par ~3 → ce n'est pas un drop d'usage, c'est une régression du chemin notif → digest.

## Cadrage technique

Les notifs Facteur sont **100 % locales** (`flutter_local_notifications` + `AlarmManager`). Aucun envoi backend, aucun token device, aucun cron Railway. La planification est posée par le mobile et l'OS la rejoue chaque jour à la même heure (`matchDateTimeComponents: DateTimeComponents.time`).

Code clé :
- `apps/mobile/lib/core/services/push_notification_service.dart` — service
- `apps/mobile/lib/main.dart:106-152` — bootstrap (plante un placeholder si rien n'est schedulé)
- `apps/mobile/lib/features/digest/providers/digest_provider.dart:298-330` — re-schedule avec teasers personnalisés
- `apps/mobile/android/app/src/main/AndroidManifest.xml:103-111` — receivers boot + permissions exact-alarm

## Hypothèses

1. **H1 — Régression discoverability + body statique post-PR #512** (30/04, `d8b0da86`). L'onglet Digest a été supprimé. `_updateNotificationWithTopics()` ne tourne plus que si l'utilisateur ouvre l'écran Digest (`digestProvider` n'est lu que par `features/digest/*`), donc la notif retombe sur le placeholder « Ton récap du jour t'attend quand tu veux. ». Le payload a aussi oscillé `route:/digest` ↔ `route:/feed` entre #512 et #519.
2. **H3 — `SCHEDULE_EXACT_ALARM` révoquée** (Android 14+ ou OEM). Mesurable via `getDiagnostics().exactAlarmsGranted`.
3. **H2 — Crash boot WorkManager (1–2 mai)**. Bornée dans le temps, fix mergé dans #542. Validation Sentry impossible (projet `flutter` créé après l'incident).

## Actions

### PR 1 — Télémétrie `notif_diag` au boot
Capturer `getDiagnostics()` à chaque cold start, parc-wide. 24 h de données suffit pour quantifier H1 vs H3.

### PR 2 — Câbler le DSN Sentry mobile
Le projet Sentry `flutter` existe maintenant ; câbler `--dart-define=SENTRY_DSN=…` dans le pipeline de build pour capturer les futures crashs (notamment au boot).

**Statut** : câblé via `SENTRY_DSN_FLUTTER` (GitHub Secret) → workflows `build-apk.yml` / `build-ipa.yml`. Injecté comme `--dart-define=SENTRY_DSN=…`. Documenté dans `docs/infra/claude-access-setup.md` §1, §2.4.bis. Healthcheck ajouté (validation format). Actif à partir du prochain build.

### PR 3 (conditionnel)
Selon la donnée `notif_diag` :
- `digestScheduled=false` malgré `pushEnabled=true` → re-câbler une replanif systématique au bootstrap, indépendante de l'écran Digest.
- `exactAlarmsGranted=false` répandu → nudge dans `notifications_screen.dart`.
- Tout `true` mais drop persiste → c'est H1 pur → revoir copy par défaut + déplacer `_updateNotificationWithTopics()` vers un point d'entrée plus fréquent (par ex. `feed_provider`).
