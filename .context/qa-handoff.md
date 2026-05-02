# QA Handoff — Story 18.3 « Ma veille » end-to-end

> Rempli par l'agent dev en fin de développement, après validation du PO.
> Sert d'input à `/validate-feature`.

## Feature développée

Câblage end-to-end du flow « Ma veille » sur l'app mobile :
- Wiring du submit étape 4 → POST `/api/veille/config` (suppression du no-op).
- Suggestions topics/sources réelles (POST `/api/veille/suggestions/{topics,sources}`) à l'entrée des étapes 2 et 3 (au lieu du mock).
- Nouvel écran « Ma veille déjà configurée » (dashboard) — affiché si `GET /api/veille/config` = 200 ; redirige automatiquement depuis `/veille/config` au lieu de relancer le flow 4-steps.
- Nouvel écran historique livraisons (`/veille/deliveries`) — liste 20 dernières.
- Nouvel écran détail livraison (`/veille/deliveries/:id`) — clusters + `why_it_matters` + articles cliquables (InAppWebView).
- Notif locale planifiée côté front au submit (`flutter_local_notifications`, NotifId=3, à `next_scheduled_at + 30 min`), deeplink `io.supabase.facteur://veille/dashboard`.

Aucune modif backend (pipeline déjà livrée en 18.1/18.2).

## PR associée

À créer via `/go` (PR vers `main`).

## Écrans impactés

| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Flow Veille — Étape 1 (thème) | `/veille/config` | Modifié — redirect dashboard si config existe |
| Flow Veille — Étape 2 (suggestions topics) | `/veille/config` | Modifié — POST `/suggestions/topics` au mount |
| Flow Veille — Étape 3 (sources) | `/veille/config` | Modifié — POST `/suggestions/sources` au mount |
| Flow Veille — Étape 4 (fréquence + submit) | `/veille/config` | Modifié — POST `/config` réel + planif notif locale |
| Dashboard « Ma veille déjà configurée » | `/veille/dashboard` | **Nouveau** |
| Historique livraisons | `/veille/deliveries` | **Nouveau** |
| Détail livraison | `/veille/deliveries/:id` | **Nouveau** |

## Scénarios de test

### Scénario 1 : Happy path — première config & livraison

**Parcours** :
1. Auth dans l'app. Aucune veille configurée.
2. Naviguer vers `/veille/config` (depuis settings ou route directe).
3. Étape 1 : choisir thème « IA & éducation ».
4. Étape 2 : observer le spinner pendant 1-3s, puis suggestions LLM affichées (différentes du mock figé). Sélectionner 3 topics.
5. Étape 3 : spinner puis sources `followed` + `niche` réelles. Sélectionner 4 sources.
6. Étape 4 : fréquence weekly · lundi · 7h. Tap « Configurer ma veille ».
7. Vérifier : POST `/api/veille/config` → 200 dans logs uvicorn.
8. Vérifier : redirection vers `/veille/dashboard` (pas le SnackBar mock).
9. Vérifier (Android Studio Logcat ou debug print) : `PushNotificationService: scheduled veilleDelivery for <next_scheduled_at + 30min>`.
10. (debug local) `POST /api/veille/deliveries/generate` → 200 succeeded.
11. Re-ouvrir l'app → dashboard → bouton « Historique » → liste 1 livraison.
12. Tap livraison → détail → 1+ cluster avec titre + `why_it_matters` + articles.
13. Tap article → InAppWebView s'ouvre.

**Résultat attendu** :
- Aucune erreur réseau ni 4xx visible dans les logs.
- La notif locale est bien planifiée (vérifiable via Logcat ou `flutter logs`).
- Le dashboard affiche le thème, topics, sources, fréquence et un countdown vers `next_scheduled_at`.
- Le détail livraison montre des clusters réels (ou fallback déterministe si `MISTRAL_API_KEY` absent localement, sans badge visible).

### Scénario 2 : Veille déjà configurée — redirect dashboard

**Parcours** :
1. Avoir une veille active (cf. Scénario 1).
2. Tap depuis settings le bouton « Configurer ma veille » (ou navigate manuel `/veille/config`).
3. Observer.

**Résultat attendu** :
- L'utilisateur voit le dashboard `/veille/dashboard`, pas le flow 4-steps (Step1).
- Si l'utilisateur tap « Modifier ma veille » sur le dashboard → flow 4-steps relancé avec le state preset (thème, topics, sources cochés).

### Scénario 3 : Pause & Reprendre

**Parcours** :
1. Dashboard avec veille active.
2. Tap « Mettre en pause ».
3. Observer.

**Résultat attendu** :
- PATCH `/api/veille/config` → 200, `status="paused"`.
- Le bouton devient « Reprendre ».
- Le countdown disparaît (ou affiche « En pause »).
- La notif locale précédemment planifiée est cancelled (vérifiable via debug print).
- Tap « Reprendre » → PATCH status="active" + reschedule notif.

### Scénario 4 : Suppression

**Parcours** :
1. Dashboard avec veille active.
2. Tap « Supprimer ma veille » → confirm dialog → confirmer.
3. Observer.

**Résultat attendu** :
- DELETE `/api/veille/config` → 204.
- L'utilisateur est redirigé vers `/feed` (ou la route de fallback).
- Re-ouvrir `/veille/config` → flow 4-steps de nouveau (état GET /config = 404).
- Notif locale cancelled.

### Scénario 5 : Détail livraison failed

**Parcours** :
1. Forcer une livraison `failed` (peut nécessiter un seed DB côté QA — alternative : mocker côté UI test).
2. Ouvrir l'historique → tap la livraison.

**Résultat attendu** :
- Le détail affiche un état d'erreur sympa (« La livraison a échoué — le scanner réessaiera bientôt »).
- Pas de crash, pas d'erreur dans les logs front.

### Scénario 6 : Erreur réseau pendant suggestions

**Parcours** :
1. Étape 2 (suggestions topics) : couper le wifi.
2. Re-tenter le mount (back puis re-forward).

**Résultat attendu** :
- Toast `« Suggestions indisponibles, conserve ta sélection »`.
- La grille reste fonctionnelle avec mock data (pas de crash).
- Bouton « Réessayer » disponible.

### Scénario 7 : Tap notification locale

**Parcours** :
1. Avoir une veille active avec notif schedulée.
2. (Debug Android) déclencher la notif manuellement OU avancer la date système.
3. Tap la notif depuis l'écran de verrouillage.

**Résultat attendu** :
- L'app s'ouvre sur `/veille/dashboard` (deeplink `io.supabase.facteur://veille/dashboard`).
- Si `target_date` du jour a une livraison `succeeded`, le bouton « Historique » l'affiche en haut.

## Critères d'acceptation

- [ ] Submit étape 4 fait un vrai POST `/api/veille/config` (plus de SnackBar mock).
- [ ] Étapes 2 et 3 appellent les endpoints suggestions avec spinner bloquant.
- [ ] Toute config existante (GET 200) déclenche un redirect vers `/veille/dashboard` au lieu du flow.
- [ ] Dashboard rend thème, topics, sources, fréquence, countdown.
- [ ] Boutons dashboard (Modifier/Pause/Supprimer/Voir historique) tous fonctionnels.
- [ ] Historique liste 20 livraisons max, empty state si 0.
- [ ] Détail livraison rend les clusters avec `why_it_matters` + articles.
- [ ] Tap article ouvre InAppWebView (pas le navigateur externe).
- [ ] Notif locale planifiée au submit, cancellée au pause/delete, re-schedulée au PATCH frequency.
- [ ] Deeplink `io.supabase.facteur://veille/dashboard` mappé.
- [ ] `flutter test` vert sur les fichiers touchés/créés.
- [ ] `flutter analyze` ne crée pas de NOUVEAU error/warning.

## Zones de risque

1. **UUIDs vs slugs mock** — le mock `veille_mock_data.dart` utilise des slugs (`s-lm`, `t-eval`) qui n'existent pas en DB. Le wiring API n'envoie QUE les UUIDs renvoyés par les endpoints suggestions. Vérifier qu'AUCUNE source mock-only (sans `apiSourceId`) ne fuit dans le POST /config (sinon 400 ou faux source ingéré).
2. **Notif locale & timezone** — utiliser `tz.TZDateTime.from(when, tz.local)` (pattern `scheduleDailyDigestNotification`). Sinon DST Paris peut décaler la notif d'1h.
3. **Retries cascadés** — la règle « max 1 sur 5xx, 0 sur 4xx » est CRITIQUE. Pas de retry cascadé type `digest_provider._loadBothDigests` (mémoire `bug-infinite-load-requests` : pool DB déjà saturé en prod).
4. **Mistral KO côté backend** — `why_it_matters` reçoit alors un fallback déterministe (« 4 articles de 2 sources couvrent ce sujet »). À considérer comme valide, pas un état d'erreur. Pas de badge.
5. **Multi-device** — la notif est purement locale. Si l'utilisateur configure depuis device A, device B ne recevra pas la notif. Documenté hors scope V1.
6. **`generation_state == "running"`** — au moment où la notif tombe, le scanner peut encore tourner. Le détail doit gérer ce cas (afficher un loader « génération en cours, refresh dans X s »).
7. **InAppWebView** — vérifier qu'on réutilise le même helper que le digest (`Grep "InAppWebView"` côté `features/digest/` ou `features/feed/`). Sinon implémenter un fallback `url_launcher` propre.

## Dépendances

- Endpoints API (déjà livrés en 18.1/18.2) :
  - `GET /api/veille/config`
  - `POST /api/veille/config`
  - `PATCH /api/veille/config`
  - `DELETE /api/veille/config`
  - `POST /api/veille/suggestions/topics`
  - `POST /api/veille/suggestions/sources`
  - `GET /api/veille/deliveries?limit=20`
  - `GET /api/veille/deliveries/{id}`
  - `POST /api/veille/deliveries/generate` (debug, dev only)
- Pas de migration backend.
- Pas de FCM/APNS (push 100% local via `flutter_local_notifications`).
- Scanner backend `*/30 min` (déjà schedulé via APScheduler).
