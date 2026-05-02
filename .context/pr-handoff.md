# PR — Story 18.3 « Ma veille » end-to-end (front wiring + historique + push notifs)

## Why

Phase E2E de la feature « Ma veille ». Le backend pipeline (18.1 + 18.2,
PR #524 + #535) produit des `items[]` réels avec clusters + `why_it_matters`
LLM. Côté front Flutter, le flow 4-steps était encore 100 % mock :

- `submit()` no-op à `apps/mobile/lib/features/veille/providers/veille_config_provider.dart:142` ;
- aucun écran historique livraisons ni détail livraison ;
- aucune notif planifiée à la livraison.

Cette PR ferme la boucle « configuration → livraison → consommation » sur
l'app et planifie une notif locale (pas de FCM côté projet) pour rappeler
au user que sa veille est tombée.

## What

### Front wiring

- `submit()` étape 4 → POST `/api/veille/config` (real `VeilleRepository`).
- Suggestions topics/sources réelles à l'entrée des étapes 2 et 3 (POST
  `/api/veille/suggestions/{topics,sources}` avec spinner bloquant +
  fallback mock UX si erreur réseau).
- Redirect automatique `/veille/config` → `/veille/dashboard` quand
  `GET /api/veille/config` retourne 200 (au lieu de relancer le flow).
- Filtrage des sources mock-only au submit (sans `apiSourceId` UUID API,
  elles ne peuvent pas être ingérées par le backend).

### Nouveaux écrans

- **Dashboard** `/veille/dashboard` : thème, topics, sources, schedule,
  countdown next_scheduled_at, boutons Modifier / Pause / Supprimer / Historique.
- **Historique** `/veille/deliveries` : liste 20 dernières livraisons,
  pull-to-refresh, empty state.
- **Détail livraison** `/veille/deliveries/:id` : clusters + `why_it_matters` +
  articles → tap ouvre InAppWebView (`launchUrl` mode `inAppBrowserView`).
  Gère les états `running`/`pending` (loader) et `failed` (state d'erreur sympa).

### Push notif locale + deeplink

- `PushNotificationService.scheduleVeilleNotification(scheduledAt)` (NotifId=3,
  channel `veille_channel`). Planifié à `next_scheduled_at + 30 min` pour
  laisser le scanner */30 min générer la livraison avant que la notif tombe.
- Cancel automatique sur PATCH status=paused / DELETE.
- Mapping deeplink `io.supabase.facteur://veille/dashboard` ajouté à
  `DeepLinkService.parse` (`WidgetDeepLinkTarget.veille`).

### Architecture

- Pas de modif backend (la pipeline fait déjà tout).
- Patterns réutilisés : `digest_repository.dart` (Dio + exceptions typées),
  `digest_provider.dart` (AsyncNotifier — simplifié load-on-enter),
  `scheduleDailyDigestNotification` (zonedSchedule local).
- Retries bornés (interceptor existant : 2 retries sur 5xx ≠503, 0 sur 4xx) —
  pas de retries cascadés type stale-fallback du digest (anti-cascade pool DB).
- Story doc : `docs/stories/core/18.3.veille-e2e.md`.

## Test plan

- [x] `flutter analyze lib/features/veille` → 1 info-level lint, 0 erreur.
- [x] `flutter test test/features/veille/models/veille_models_test.dart` →
  15 tests verts (parsing fromJson + sérialisation toJson).
- [x] `flutter test test/core/services/{deep_link_service,push_notification_service_copy}_test.dart`
  → 14 tests verts (anti-régression, +2 tests pour le mapping veille deep link).
- [x] `pytest -q` backend (anti-régression) : 838 passed, 85 errors —
  TOUTES les errors sont `psycopg.OperationalError` (DB locale Supabase non
  démarrée, infra), aucune cassée par cette PR.
- [ ] `/validate-feature` (Chrome MCP, viewport 390x844) — scénarios :
  happy path, redirect dashboard, pause/reprendre, suppression, livraison
  failed, erreur réseau suggestions, tap notif. Cf. `.context/qa-handoff.md`.
- [ ] Smoke API local : `uvicorn app.main:app --port 8080`, configure une
  veille, vérifier POST /config + log `PushNotificationService: veille scheduled @ ...`,
  POST /deliveries/generate (debug), refresh historique.

## Out of scope

- Multi-veilles par user (V2/V3).
- Carte « Ma veille » sur le feed (entry point — tranché en brainstorming PO).
- Push serveur (FCM/APNS) — pas de stockage push_token côté backend, hors V1.
- Cache disque persistant pour livraisons (load-on-enter mémoire suffit).
- Pagination historique > 20.
