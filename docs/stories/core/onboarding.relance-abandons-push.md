# Story — Relance des abandons d'onboarding par push (amorce précoce + J+0/J+1)

**Type** : Feature
**Statut** : CODE terminé, VERIFY en cours
**Branche** : `boujonlaurin-dotcom/san-salvador`

## Problème / objectif

Beaucoup d'utilisateurs démarrent l'onboarding puis l'abandonnent. On veut les
relancer par une notification push. Cela suppose de **capter la permission de
notification tôt** (dès l'étape 3/4) et d'**enregistrer le device** pendant que
l'utilisateur est encore anonyme (le compte email n'est créé qu'à la dernière
étape → la vraie population d'abandon est anonyme).

### Contrainte de plateforme centrale
La pop-up système de permission ne s'affiche **qu'une fois** (iOS + Android 13+).
Exigence PO : un refus de l'ask précoce ne doit **pas** brûler la pop-up de la
notif quotidienne. → **écran d'amorce interne** : seul un OUI déclenche la vraie
pop-up ; un refus ne consomme rien. Flag one-shot dédié
`notif_early_priming_seen`, **distinct** du gate `notif_modal_seen` de la modale
quotidienne.

### Décisions PO
1. Écran d'amorce interne (pas la vraie pop-up directe).
2. Cible = tous les abandons d'onboarding, anonymes inclus.
3. Relances J+0 (~1h) puis J+1 (~24h).

## Implémentation

### Mobile
- `core/services/push_notification_service.dart` — iOS ne demande plus la
  permission au boot (`DarwinInitializationSettings(request*: false)`) ; branche
  iOS explicite ajoutée à `requestPermission()`.
- `features/onboarding/services/onboarding_push_priming.dart` (NOUVEAU) — seam
  testable : `hasSeenPriming` / `acceptAndRegister` (→ `initAndRegister`, unique
  pop-up OS + enregistrement anonyme) / `refuse` (aucun appel OS). Provider
  `onboardingPushPrimingProvider`.
- `features/onboarding/widgets/onboarding_notif_priming.dart` (NOUVEAU) — écran
  léger « Activer les rappels ? », gardé par `kSupportsPushNotifications`.
- `features/onboarding/screens/onboarding_screen.dart` — `_maybeSchedulePriming`
  arme un `Timer(4s)` une fois, à `globalQuestionIndex >= 3`, session anonyme,
  amorce non vue ; annulé au dispose et non tiré pendant `isReadyToFinalize`.
- `core/services/analytics_service.dart` — 3 events :
  `onboarding_notif_priming_shown|accepted|refused`.

### Backend
- `app/services/onboarding_reengagement_dispatcher.py` (NOUVEAU) — sélectionne
  les `push_devices` non révoqués dont `user_profiles.onboarding_completed =
  False`, ancre = `device.created_at`, envoie D0 (≥1h) puis D1 (≥24h), heures
  calmes locales respectées (report au prochain 08:00), idempotent via
  `push_deliveries` kinds `onboarding_reengagement_d0`/`_d1`. Budget gouverneur
  bypassé (2 envois à vie / device). Deep link `/onboarding`.
- `app/workers/scheduler.py` — job `IntervalTrigger(minutes=5)`.
- **Aucune migration** (kinds = chaînes dans la colonne `String(32)` existante ;
  head Alembic `mg06_merge_cq01_st02` inchangé).

## Tests
- Backend : `tests/services/test_onboarding_reengagement_dispatcher.py` (9 cas :
  D0/D1 timing, idempotence, stop-on-complete, quiet hours, token invalide,
  stale). ✅ 9/9.
- Mobile : `test/features/onboarding/widgets/onboarding_notif_priming_test.dart`
  (titre + CTA ; accept → register + event ; refus n'écrit PAS `notif_modal_seen`).

## Copy — `// TODO(PO): valider`
- Amorce : « Activer les rappels ? » / « Reçois un rappel pour reprendre ta
  configuration et la terminer en une minute. » / « Activer les rappels » /
  « Plus tard ».
- J+0 : « Tu y étais presque » / « Ta configuration n'est pas terminée. Reprends
  en une minute. »
- J+1 : « On termine ta configuration ? » / « Quelques réponses suffisent pour
  recevoir ton premier récap. »
