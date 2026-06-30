# Bug — Notif matin : avatar dupliqué + corps générique sans bullets

**Type :** Bug
**Statut :** Part 1 + Part 2 (code) livrés dans une seule PR. Reste 2 actions **ops/PO** (cf. § Part 2 → Actions ops).

## Symptôme (capture prod)

La notification quotidienne « Ton facteur » affiche :
- un **corps générique** (« Ton récap du jour t'attend quand tu veux. ») **sans
  bullet points d'articles** ;
- un **avatar dupliqué** : le logo Facteur (icône launcher) + un rond orange « T ».

## Diagnostic

Le titre `Ton facteur` + le corps `Ton récap du jour t'attend quand tu veux.`
correspondent à la notif **LOCALE** `variantA`
(`PushNotificationService.buildCopy(variant: variantA)` → `defaultBody`). Ce
**n'est pas** le push serveur.

100 % des users prod reçoivent le push local parce que le **push serveur n'a
enregistré aucun device** en prod (`push_devices` = 0 ; `push_deliveries` 7j =
0 ; alors que `push_enabled = true` pour 31 users). Tous retombent sur le
fallback local (`main.dart` + `server_push_service._restoreGenericFallback`).

### Deux défauts de la notif locale

1. **Avatar dupliqué.** `scheduleDailyDigestNotification` et
   `scheduleDailyGoodNewsNotification` utilisaient `MessagingStyleInformation`
   avec un `sender = Person(name: senderName)` **sans icône** → Android génère un
   monogramme « T » coloré à côté de l'icône launcher.
2. **Pas de bullets.** Le fallback local planifiait **toujours** `variantA`, et
   les teasers Essentiel étaient supprimés de Hive
   (`server_push_service.dart:99`, `syncDigestTeasers`). Cold-start n'avait donc
   rien à rendre en bullets.

## Fix — Part 1 (mobile-only, aucune migration)

### 1a. Supprimer l'avatar dupliqué
`MessagingStyleInformation` → `BigTextStyleInformation` (pattern déjà utilisé par
`scheduleWeeklyCommunityPick` / `scheduleVeilleNotification`, sans ce bug) pour
le digest, les bonnes nouvelles, et `showRemoteNotification`.

### 1b. Restaurer les bullets en local (variantB)
- `server_push_service.dart` : ne plus supprimer `notif_essentiel_teasers` ;
  `_restoreGenericFallback` planifie `variantB` + teasers si présents.
- `syncDigestTeasers` : **persiste** les teasers Essentiel (au lieu de les
  supprimer) puis replanifie `variantB` quand présents.
- `main.dart` cold-start : lit les teasers persistés et planifie `variantB`.

> **Tradeoff (PO ok, phasé) :** les bullets locaux viennent du dernier fetch
> (potentiellement J-1). Le digest exact du jour viendra du push serveur (Part 2).

### 1c. `showRemoteNotification` (foreground)
Parse `message.data['teasers']` (JSON) → `buildCopy(variantB, teasers)` →
`BigTextStyleInformation`. Fallback sur `notification.title/body` sinon.

## Part 2 — Réanimer le push serveur (cause « 0 device »)

**État live confirmé (DB prod partagée, 2026-06-30) :** `push_devices` = 0,
`push_deliveries` (total **et** 7j) = 0, `user_notification_preferences.push_enabled`
= 31. La registration n'a **jamais** réussi une seule fois.

### Cause racine = config/ops (hors repo), deux suspects compounding
1. **Backend non configuré.** `PUT /api/devices` renvoie **503** si
   `FIREBASE_SERVICE_ACCOUNT_{JSON,BASE64}` n'est pas set côté Railway
   (`push_devices.py:43-50`). Le mobile **avale** la `DioException`
   (`return false`) → fallback local silencieux. Et `dispatch_daily_essentiel_pushes`
   se **désactive** sans ce secret (`push_dispatcher._firebase_configured`).
2. **App : token FCM null.** `google-services.json` absent/incohérent pour le
   flavor (`facteur.app` prod / `com.example.facteur.staging` staging, fournis
   au build, hors repo) ⇒ `getToken()` null avant même d'appeler le backend.

### Code livré dans cette PR (rend le diagnostic décidable + bullets hors-app)
- **Instrumentation registration** (`server_push_service.dart`) : event PostHog
  `push_register` avec `outcome` ∈ {`token_null`, `session_null`,
  `endpoint_error`(+`status_code`), `registered`, `exception`}. Après la
  prochaine release on lit l'outcome dominant pour trancher suspect 1 vs 2.
  `PushDevicesApiService.upsert` surface désormais le `statusCode` (le 503 était
  jeté).
- **FCM data-only Android + bullets hors-app** : `push_dispatcher._send_fcm`
  passe en data-only (plus de bloc `notification` top-level → Android réveille
  `firebaseMessagingBackgroundHandler`, qui rend le BigText à bullets via le
  chemin de `showRemoteNotification`). iOS garde un **alert APNS visible**
  (corps = 1er titre, sans bullets — acceptable). `showRemoteNotification` gère
  le cas data-only (notification null).

### Actions ops/PO restantes (NON codables — hors repo)
1. **Railway** : vérifier/poser `FIREBASE_SERVICE_ACCOUNT_JSON` (ou `_BASE64`)
   sur **les deux** services (`api-staging-40d3` **et** `facteur-production`).
   Sans ça, `PUT /api/devices` = 503 et le dispatcher reste désactivé.
2. **Firebase console + CI** : confirmer que les applicationIds `facteur.app`
   (prod) et `com.example.facteur.staging` (staging) sont enregistrés, sender ID
   = secrets CI, et que `google-services.json` par flavor est bien injecté au
   build (`android/app/src/{prod,staging}/`).

Après ces 2 actions + une release : relancer un opt-in → vérifier qu'une ligne
apparaît dans `push_devices`, puis déclencher `dispatch_daily_essentiel_pushes`
→ `push_deliveries.status = 'sent'` + rendu on-device (bullets).

## Fichiers

**Part 1 (mobile)**
- `apps/mobile/lib/core/services/push_notification_service.dart` — BigTextStyle, parse teasers, data-only render
- `apps/mobile/lib/core/services/server_push_service.dart` — persistance teasers, fallback variantB, bg handler, instrumentation
- `apps/mobile/lib/features/settings/providers/notifications_settings_provider.dart` — persiste teasers, reschedule variantB
- `apps/mobile/lib/main.dart` — cold-start variantB

**Part 2**
- `apps/mobile/lib/core/api/push_devices_api_service.dart` — surface `statusCode` (503)
- `apps/mobile/lib/core/services/server_push_service.dart` — event `push_register`
- `packages/api/app/services/push_dispatcher.py` — FCM data-only Android + alert APNS iOS
- `packages/api/tests/services/test_push_dispatcher.py` — test data-only
