# Bug : Chargements Infinis du Digest (récurrents)

**Date** : 2026-04-27
**Branche** : `claude/fix-digest-loading-sWZRJ`
**Statut** : En cours
**Impact** : Critique (UX dégradée à chaque ouverture d'app sur certains profils)

## Symptôme

L'utilisateur voit un spinner "Chargement de votre Essentiel..." pendant 30 à 90 secondes,
parfois suivi d'un message d'erreur, alors que le digest est censé être pré-calculé chaque
nuit (cron 8h00 Paris) et figé pour les 24h suivantes.

## Mental model utilisateur vs. réalité du code

| Croyance | Réalité |
|---|---|
| Digest identique pour tous, calculé une fois | Digest **personnalisé par utilisateur** (sources suivies, weekly_goal, mode serein, format éditorial/topics) |
| Calcul async toutes les 24h, jamais en ligne | Cron 8h Paris, **mais fallback synchrone dans la requête HTTP** si pas de cache |
| Ouverture d'app = lecture rapide d'un row | `GET /digest/both` peut **régénérer 2 digests + appels LLM** dans la requête |

## Cause Racine (CONFIRMÉE par lecture du code)

Le chemin `GET /api/digest/both` (utilisé par mobile au lancement) passe par
`DigestService.get_or_create_digest()` qui contient **trois portes synchrones lourdes** :

### 1. Invalidation de cache sur format_version mismatch (`digest_service.py:152-162`)

```python
if existing_digest and existing_digest.format_version != expected_version:
    await self.session.delete(existing_digest)
    await self.session.flush()
    existing_digest = None
```

→ Si le cron a généré le digest en `topics_v1` mais que la config a basculé sur
`editorial_v1` (ou inversement), le cache est **détruit** et **régénéré dans la requête HTTP**.

### 2. Régénération synchrone si pas de digest pour aujourd'hui

`get_or_create_digest` appelle `selector.select_for_user(...)` qui peut déclencher la
**pipeline éditoriale** (`digest_selector.py` + `editorial/pipeline.py`) avec **appels LLM**.
Latence observée : **20-60s** par variante. Doublé pour `/digest/both` (séquentiel).

### 3. Sérialisation normal + serein dans `/digest/both` (`routers/digest.py:137-138`)

```python
normal = await service.get_or_create_digest(user_uuid, target_date, is_serene=False)
serein = await service.get_or_create_digest(user_uuid, target_date, is_serene=True)
```

→ Les deux variantes sont générées **en série**. En cas de cache miss double, on attend 2× la latence.

### 4. Pool DB sous-dimensionné (`database.py:49-52`)

`pool_size=5, max_overflow=5` → max **10 connexions simultanées**. Un job de catchup
au démarrage qui régénère pour tous les users (semaphore=10) **sature le pool**, et toute
ouverture d'app pendant ce temps timeout.

### 5. Mobile retry policy amplifie la perception

`digest_provider.dart:70-75` :
```dart
_digestMaxRetries = 3
_digestRetryDelays = [5s, 10s, 15s]
timeout = 45s par tentative
```

→ Worst case = **(45 + 5) + (45 + 10) + (45 + 15) = 165s** de spinner avant erreur.

## Pourquoi ça empire après un déploiement

Chaque deploy redémarre le container → `_startup_digest_catchup()` (main.py:163-208) attend
60s puis lance `run_digest_generation()` pour TOUS les users. Pendant ce burst :
- Le pool DB est saturé
- Les LLM editorial calls sont en concurrence
- Toute requête utilisateur arrive sur un service surchargé

C'est exactement le phénomène que tu observes "à chaque fois".

## Fix Proposé

### Principe directeur

> **Le chemin HTTP `GET /digest*` ne doit JAMAIS faire de génération lourde.**
> Il sert ce qui est en base. Si rien n'est en base, il sert le plus récent disponible.
> La génération reste l'affaire du cron (et d'un endpoint explicite `POST /digest/generate`).

### Changements backend

1. **`DigestService.get_or_create_digest`** — nouveau paramètre `allow_generation: bool = True`.
   - Le router GET passe `allow_generation=False`.
   - Le router POST `/generate` et le job cron passent `allow_generation=True` (comportement actuel).
   - Quand `allow_generation=False` :
     - Si digest existe (même format obsolète) → **on le sert tel quel** (pas de delete+regen).
     - Si pas de digest aujourd'hui → on cherche le **plus récent existant** (jusqu'à 7 jours en arrière), on le sert.
     - Si rien trouvé → 202 (preparing) + planifie une tâche background `asyncio.create_task(generate_digest_for_user(...))`.
   - Le mobile gère déjà 202 → DigestPreparingException → retry.

2. **`/digest/both`** — paralléliser via `asyncio.gather`.
   ```python
   normal, serein, serein_enabled = await asyncio.gather(
       service.get_or_create_digest(user_uuid, target_date, is_serene=False, allow_generation=False),
       service.get_or_create_digest(user_uuid, target_date, is_serene=True, allow_generation=False),
       service._get_user_serein_enabled(user_uuid),
   )
   ```

3. **Format mismatch** — déplacer la régénération hors de la requête HTTP.
   Le check `format_version != expected_version` se fait toujours, mais déclenche un
   `asyncio.create_task` de régénération background **et sert l'existant** dans la même requête.

4. **Pool DB** — passer à `pool_size=10, max_overflow=10` pour laisser de la marge
   pendant les bursts de catchup. (Supabase pooler accepte ~60 connexions partagées.)

5. **Startup catchup** — réduire `concurrency_limit` de 10 → 5 pour ne pas saturer le pool
   pendant la génération de masse. Et passer `hours_lookback=48` (déjà le cas) suffit.

### Changements mobile

1. **Réduire les retry delays** — 503 doit devenir extrêmement rare après le fix backend.
   Garder 1 retry à 3s suffit.
2. **202 → spinner explicite "préparation"** — déjà le cas, mais on peut afficher un message
   "Votre essentiel se prépare, encore quelques secondes..." pour réduire la frustration.

### Migrations Alembic

**Aucune migration nécessaire.** Le fix est code-only.

## Plan d'exécution

| # | Tâche | Fichier | Risque |
|---|---|---|---|
| 1 | Ajouter `allow_generation` à `get_or_create_digest` | `digest_service.py` | Faible |
| 2 | Servir cache obsolète + scheduler regen background | `digest_service.py` | Moyen (logique de fallback) |
| 3 | Paralléliser `/digest/both` via gather | `routers/digest.py` | Faible |
| 4 | Routeur GET passe `allow_generation=False` | `routers/digest.py` | Faible |
| 5 | Pool DB 10+10 | `database.py` | Faible |
| 6 | Startup catchup concurrency=5 | `main.py` | Faible |
| 7 | Mobile : 1 retry à 3s au lieu de 3×progressifs | `digest_provider.dart` | Faible |
| 8 | Tests : `test_digest_service.py` cas `allow_generation=False` | `tests/` | — |

## Validation

- [ ] `pytest packages/api/tests/test_digest_service.py -v`
- [ ] `pytest packages/api/tests/test_digest_generation_job.py -v`
- [ ] `flutter test apps/mobile/test/features/digest/` 
- [ ] Sur Railway après merge : ouvrir l'app dans les 60s post-deploy → digest doit s'afficher en <2s (digest existant servi)
- [ ] Logs Sentry : disparition de `digest_generation_returned_none` et `digest_endpoint_unhandled_error` sur le chemin GET

## Hors scope (à voir après)

- Migration vers un cache Redis pour les digests (rapidité + offload Postgres)
- Désactiver complètement la pipeline éditoriale en mode dégradé si le LLM provider est down
- Monitoring Prometheus de la latence p95/p99 par endpoint
