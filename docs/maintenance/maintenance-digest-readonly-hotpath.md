# Maintenance — Digest read-only hot path

> **Date** : 2026-04-27
> **Branche** : `boujonlaurin-dotcom/digest-readonly-hotpath`
> **PR ciblée** : `main`
> **Type** : refactor architectural (cause racine, pas symptôme)

## Contexte

Pendant des mois, `GET /api/digest/both` a chargé indéfiniment côté mobile lors d'incidents upstream (Mistral, Supabase, OpenAI). 15 PRs successives ont patché des symptômes :

| PR | Symptôme corrigé |
|---|---|
| #385, #396, #397 | Timeouts initiaux pipeline |
| #405, #408, #409, #412 | Fail-open emergency, SQL race |
| #414 | Yesterday fallback rendu user-visible |
| #422 | Auto-refetch silencieux mobile sur `is_stale_fallback` |
| #442 | Clone editorial cross-user |
| #448 | Singleflight per user_uuid |
| #456, #457 | Sessions DB courtes pendant LLM, post-gather guards |
| #479 | Restart policy + worker session leaks |
| #484 | Post-gather rollback wrapper bornage |

Le 27/04/2026, le user (CEO Laurin) a posé la question architecturale : *"le digest est généré la nuit par un cron — pourquoi `GET /digest/both` peut-il déclencher la pipeline LLM en runtime ? Ça devrait être un simple SELECT, résilient et rapide."*

## Cause racine

`get_or_create_digest` dans `packages/api/app/services/digest_service.py:342` est appelée depuis le hot path et peut, dans plusieurs branches (format mismatch, render fail, nouveau user sans clone dispo), passer la main à `selector.select_for_user` → pipeline éditoriale LLM (3-5 min). Quand un upstream tousse, la requête hang malgré les wraps `wait_for` (qui ne couvrent pas tous les chemins). Le retry mobile (4 requêtes concurrentes par défaut sur Dio) sature alors le pool de 25 connexions DB, et **l'app entière** passe en chargement infini — pas seulement le digest.

## Décision architecturale

`/digest` et `/digest/both` deviennent **strictement read-only** au moment de la requête. La pipeline LLM est désormais l'apanage exclusif de :

1. **Cron `daily_digest`** à 06:00 Paris — `packages/api/app/workers/scheduler.py:129`
2. **Watchdog `digest_watchdog`** à 07:30 Paris (relance si coverage < 90%)
3. **Worker background `_schedule_background_regen`** — fire-and-forget depuis le hot path quand on sert un fallback ou 202
4. **Endpoint admin/debug `POST /digest/generate`** — conservé tel quel avec son wrap 60s

## Architecture cible

```
GET /api/digest/both  (et GET /api/digest)
  └── read_digest_or_fallback(user_id, target_date, is_serene)
      ├─ 1. SELECT today's editorial_v1 digest pour ce user
      │     → trouvé : _build_digest_response → return 200 (~50ms)
      ├─ 2. SELECT n'importe quel editorial_v1 d'aujourd'hui (clone)
      │     → trouvé : _try_clone_global_editorial_digest → return 200 (~80ms)
      ├─ 3. SELECT yesterday's editorial_v1 ou topics_v1 pour ce user
      │     → trouvé : schedule_digest_regen + return is_stale_fallback=true (~80ms)
      ├─ 4. SELECT digest dans les 7 derniers jours pour ce user
      │     → trouvé : schedule_digest_regen + return is_stale_fallback=true (~100ms)
      └─ 5. sinon : schedule_digest_regen + return 202 "preparing"
```

**Aucune branche du hot path n'appelle `selector.select_for_user`. Aucune branche ne dépasse ~200ms côté DB.**

## Composants supprimés du hot path

- **Singleflight** (`_digest_both_inflight`, `DIGEST_BOTH_FOLLOWER_TIMEOUT_S`) — un SELECT ne pile pas
- **Variant + gather timeouts** (`DIGEST_BOTH_VARIANT_TIMEOUT_S=25s`, `DIGEST_BOTH_GATHER_TIMEOUT_S=30s`) — plus de LLM, plus besoin de wait_for
- **Wrap wait_for `DIGEST_SINGLE_TIMEOUT_S=30s`** sur `/digest`
- **Branche `is_generation_running()` 202** — le helper la couvre implicitement
- **Post-gather rollback wrapper** (#484) — sans LLM 25-30s, la session n'est plus idle, plus de PgBouncer kill

## Composants conservés intentionnellement

- `get_or_create_digest` reste, utilisée par `_schedule_background_regen` (force=True) et `POST /digest/generate`
- `_schedule_background_regen` — rate-limit 1/min par (user, date, variant), tâche pinnée, session propre
- Branche yesterday-fallback interne à `get_or_create_digest` — désormais redondante mais bénigne ; suppression repoussée à un PR de cleanup pour limiter la taille du diff
- `is_stale_fallback` Pydantic + Freezed + auto-refetch silencieux mobile (#422)
- `POST /digest/generate` (avec wrap 60s) pour debug admin
- `GET /digest/diag` — read-only, déjà sain

## Plan de rollback

- Diff localisé à 2 fichiers (`router/digest.py`, `services/digest_service.py`)
- `git revert <sha>` + redeploy Railway = restauration en <10 min
- Aucune migration DB
- Aucun changement mobile → rien à rollback côté app stores

## Critères de succès (post-merge sur 7j en prod)

- ✅ Taux de succès `GET /api/digest/both` >99.5% (vs ~85% avant)
- ✅ Latence p95 <500ms (vs >5s avant)
- ✅ Plus aucun `long_session_checkout endpoint=/api/digest/both` >1s
- ✅ Plus aucun 502 à 900s
- ✅ Confirmation user (Laurin) : plus jamais de spinner infini matinal

## Métriques à surveiller (Railway logs)

- `digest_serving_yesterday_while_regenerating` — augmentation attendue (c'est le but du fallback)
- `digest_background_regen_scheduled` — augmentation attendue
- `digest_both_timeout` — doit disparaître
- `digest_both_singleflight_join` — doit disparaître
- `digest_format_mismatch_deferring_delete` — neutralisé sur le hot path (les flat_v1/topics_v1 cessent d'être renvoyés comme today's digest)
