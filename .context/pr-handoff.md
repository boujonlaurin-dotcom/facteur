## Fix notif matin : avatar dupliqué + corps sans bullets (Part 1) + réanimation push serveur (Part 2)

Capture prod : la notif quotidienne affichait un **corps générique sans bullets**
+ un **avatar dupliqué** (logo + rond orange « T »). Diagnostic confirmé sur la
DB partagée : le **push serveur n'a jamais enregistré un seul device** en prod
(`push_devices`=0, `push_deliveries`=0, alors que 31 users `push_enabled`) → 100 %
retombent sur la notif **locale**, qui avait deux défauts. PO : Part 1 + Part 2 en
**une seule PR**.

### Part 1 — Notif locale (mobile, 100 % des users la reçoivent)
- **Avatar dupliqué** : `MessagingStyleInformation` → `BigTextStyleInformation`
  (digest, bonnes nouvelles, `showRemoteNotification`). Le `Person` sans icône
  générait le monogramme « T ». `senderName` supprimé.
- **Bullets restaurés** : on ne supprime plus les teasers Essentiel de Hive ;
  `syncDigestTeasers` les **persiste** (+ flag serène). Les 3 chemins de fallback
  (`_restoreGenericFallback`, `_reschedule`, cold-start `main.dart`) planifient
  **variantB + teasers** quand un digest existe, sinon variantA. `buildCopy(variantB)`
  existait déjà (testé). Tradeoff PO assumé : bullets = dernier fetch (J-1 possible).

### Part 2 — Réanimer le push serveur (cause « 0 device »)
Racine = **config/ops hors repo**, 2 suspects compounding : `FIREBASE_SERVICE_ACCOUNT_*`
non set sur Railway (→ `PUT /api/devices` 503 + dispatcher désactivé) et/ou
`google-services.json` par flavor (→ `getToken()` null). La `DioException` 503 était
**avalée**, d'où l'impossibilité de trancher. Code livré pour rendre le diag décidable
+ bullets hors-app :
- **Instrumentation** : event PostHog `push_register`
  {outcome: token_null | session_null | endpoint_error(+status_code) | registered |
  exception}. `PushDevicesApiService.upsert` surface désormais le `statusCode`.
- **FCM data-only Android** : `_send_fcm` retire le bloc `notification` top-level →
  Android réveille `firebaseMessagingBackgroundHandler` qui rend le BigText à bullets
  (réutilise `showRemoteNotification`). **iOS garde un alert APNS visible** (corps =
  1er titre, sans bullets — acceptable).

### ⚠️ Actions ops/PO restantes (non codables)
1. Poser `FIREBASE_SERVICE_ACCOUNT_JSON` (ou `_BASE64`) sur **les 2** services Railway
   (`api-staging-40d3` + `facteur-production`).
2. Vérifier Firebase console (applicationIds `facteur.app` / `com.example.facteur.staging`,
   sender ID = secrets CI) + injection `google-services.json` par flavor au build.

Après ça + une release : l'event `push_register` dira l'outcome dominant, `push_devices`
se peuple, et `dispatch_daily_essentiel_pushes` envoie (status `sent`).

### Bonus
`assets/changelog.json` était **déjà corrompu** par un merge (2 paires tag/summary
fusionnées → JSON invalide, cassait la modal « Quoi de neuf »). Corrigé + entrée
Notifications ajoutée.

### Tests
- `flutter test` : copy variantB (25/25) + notifications + flux_continu OK. Analyze : 0 nouvel issue.
- `pytest` : `test_send_fcm_is_data_only_with_teasers_preserved` (fake firebase_admin). Ruff clean.
  (Tests dispatcher/route DB-backed = Connection refused en local Conductor → tournent en CI.)
- Validation on-device Android (`--flavor staging`) restante : 1 seul avatar + bullets dépliés.

Doc : `docs/bugs/bug-notif-matin-avatar-double-sans-bullets.md`.
