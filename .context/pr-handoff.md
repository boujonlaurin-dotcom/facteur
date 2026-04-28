# PR — Activation Notifications Push v1

## Why

Implémente le brief produit du 28/04/2026 — modal d'activation, présets de rythme (Minimaliste/Curieux), horaire paramétrable (Matin 07:30 / Soir 19:00), re-nudge post-refus, sync backend des préférences notif. Objectif : faire de la notif push le 1er vecteur de retour D7/D30 sans trahir le positionnement slow media (tutoiement, écriture inclusive avec point médian, personnification du Facteur à la 1ʳᵉ personne).

## Changements

**Backend (`packages/api`)**
- Nouvelle table `user_notification_preferences` (Alembic `np01`) — `preset` ∈ {minimaliste, curieux}, `time_slot` ∈ {morning, evening}, état refus/re-nudge, `modal_seen`, timezone.
- Router `GET/PATCH /api/notification-preferences` (auto-create row au GET, partial update au PATCH).
- Tests router (`tests/routers/test_notification_preferences.py`) — defaults, patch, validation invalide.

**Mobile (`apps/mobile`)**
- `NotificationsSettingsNotifier` étendu : enums `NotifPreset`/`NotifTimeSlot`, sync backend (boot + debounced PATCH + retry `pending_sync` au prochain boot), Hive cache offline.
- `PushNotificationService` réécrit : heure paramétrable via slot, `scheduleWeeklyCommunityPick` (vendredi 18:00 pour préset Curieux), variantes copy A/B/C avec tutoiement + personnification ("Facteur passé !"), payload routing pour deep-link article.
- `NotificationActivationModal` full-screen : préset RadioGroup, pills horaire, preview live, CTA OS prompt → snackbar si refus. Trigger A (post-onboarding, remplace l'ancien bottom sheet) et Trigger B (1ʳᵉ ouverture post-update si `modal_seen=false`).
- `NotificationRenudgeBanner` + provider : règle ≥7j depuis refus, espacement 14j, cap 3.
- Settings `Profil > Notifications` étendu : préset + heure éditables (composants partagés modal/settings).
- 11 events PostHog (`modal_notif_*`, `renudge_*`, `notif_scheduled`/`opened`, `notif_settings_changed`, `notif_disabled`).

## Décisions confirmées avec le PO (2026-04-28)
- Sync backend dès v1 (pas local-only).
- Trigger B au post-update via flag `modal_seen`.
- Variante B (sujet phare) auto = 1ᵉʳ topic du digest connu côté client.
- Assets icône (`ic_stat_facteur` Android, app icon iOS) et illustrations modal/re-nudge fournis par le PO ultérieurement (placeholders 🧑‍✈️ + `ic_launcher_foreground` en attendant).

## Hors-scope v1 (cf brief §9)

Variante C jour calme (override manuel éditorial), A/B test, alertes veille thématique, time picker libre, pause vacances.

## Test plan

- [x] `flutter analyze lib` → 0 errors (562 infos pré-existantes : withOpacity, etc.)
- [x] `flutter test test/features/notifications test/core/services/push_notification_service_copy_test.dart` → 12/12 pass
- [x] `ruff format --check` + `ruff check` backend → OK
- [x] Backend smoke import (`python -c "from app.main import app"`) → OK
- [x] `alembic heads` → 1 head unique (`np01`)
- [ ] **QA manuelle** : flow onboarding → modal s'affiche → sélection Curieux/Soir → confirm → notif planifiée à 19:00 + vendredi 18:00, settings reflète. Toggle off in-app → cancel les 2 schedules.
- [ ] **Device Android** : `adb shell dumpsys alarm | grep facteur` montre id=0 (digest) + id=1 (community).
- [ ] **Assets** : intégrer `ic_stat_facteur` monochrome blanc-sur-transparent dans `android/app/src/main/res/drawable-{mdpi..xxxhdpi}/` et illustrations modal/re-nudge dans `assets/notifications/` quand fournis.
- [ ] **PostHog** : events `modal_notif_*`, `renudge_*`, `notif_scheduled` visibles après run.

## Migration

Appliquer la migration `np01_create_user_notification_preferences` via **Supabase SQL Editor** (jamais sur Railway, cf CLAUDE.md). Idempotent côté users : `modal_seen=false` par défaut → Trigger B s'affichera à leur prochaine ouverture, comportement intentionnel.
