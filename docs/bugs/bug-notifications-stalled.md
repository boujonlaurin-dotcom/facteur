# Bug — Notifs Android qui ne s'envoient plus

**Statut** : investigation en cours.
**Plateforme** : Android.
**Date du signal** : 2026-05-05.

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
