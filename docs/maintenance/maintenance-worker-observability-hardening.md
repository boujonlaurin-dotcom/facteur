# Maintenance — Durcissement observabilité du worker de classification

Type : **Maintenance (observabilité / durcissement)**. Prérequis du
redéploiement worker prod (cf. plan `.context/handoff_worker_classif_asap.md`).
Sert à **voir en minutes** l'état du worker post-deploy et à **débugger** s'il
refuse encore de tourner, sans dépendre des logs.

## Contexte

Le worker de classification ML (task asyncio du lifespan) est mort
silencieusement le 30/06 (CancelledError) et **personne ne l'a vu pendant ~3
semaines** : aucun endpoint d'état, et les logs `structlog` (worker, sondes
pool) n'atteignaient pas Railway. `main` porte déjà la remédiation #948
(superviseur `_on_task_done` + loop BaseException-safe + alerte 12 h). Il
manquait les **yeux** : c'est l'objet de cette PR (aucun nouveau code worker,
uniquement de l'observabilité).

## Changements

### 1. `GET /api/health/classification` (`app/main.py`)

Endpoint `tags=["Health"]`, unauth (diagnostic, aucune donnée user), pattern
`Depends(get_db)` + `JSONResponse`. Expose :

- `worker_running` (`get_worker().running`) ;
- `pending` / `oldest_pending_age_s` (`ClassificationQueueService.get_pending_stats()`) ;
- `last_completed_at` / `last_completed_age_s` (`MAX(processed_at)`).

Codes : **503** si `ML_ENABLED=true` mais worker down (état actionnable /
alertable par simple code HTTP + `logger.critical`) ; **200** `ok` si le worker
tourne ; **200** `disabled` si `ML_ENABLED=false` (service sans worker).

### 2. Visibilité des logs

- `app/main.py` : structlog routé vers **stderr**
  (`PrintLoggerFactory(file=sys.stderr)`). Railway ne remonte de façon fiable
  que stderr ; le stdout du process est block-buffered en conteneur → les logs
  applicatifs étaient avalés.
- `packages/api/Dockerfile` : `ENV PYTHONUNBUFFERED=1` (flush immédiat).

Combinés : plus aucun log worker/pool invisible côté Railway.

### 3. Force-drive admin (`app/routers/internal.py`)

`POST /api/internal/admin/classification/drive` (gaté `require_admin_token`) :
déclenche `ClassificationWorker.drive_once()` hors run-loop. Utile si le worker
refuse de démarrer après deploy : force un batch pour capturer l'exception
exacte (via stderr/Sentry) ou prouver que le pipeline tourne. Sûr en parallèle
du worker vivant (`dequeue_batch` = `FOR UPDATE SKIP LOCKED`, aucun
double-traitement).

## Bug latent corrigé au passage — robustesse fuseau

`get_pending_stats()` (et le nouveau calcul `last_completed_age_s`) faisaient
`datetime.utcnow() - <colonne>`. Les colonnes reviennent **naïves en prod**
(`timestamp`, d'où l'absence de crash historique) mais **tz-aware sous le
harness de test** (`create_all` → `timestamptz`) : la soustraction levait
`can't subtract offset-naive and offset-aware datetimes`. Normalisé en UTC
(`replace(tzinfo=UTC)` + `datetime.now(UTC)`) → correct et identique en prod,
et enfin testable. Sans ce fix, l'endpoint aurait **500** dès qu'un
`processed_at` existe si prod migrait un jour vers `timestamptz`.

## Tests

- `tests/test_health_classification.py` : 503 worker_down / 200 ok+age /
  200 disabled ; robustesse fuseau prouvée (200 sur `processed_at` aware).
- `tests/routers/test_internal_classification_drive.py` : 401 sans token ;
  200 + `dequeued` avec token.
- `tests/workers/test_classification_worker_drive.py` : `drive_once` délègue à
  `_process_batch` et renvoie son compte.
- `tests/test_logging_stderr.py` : `logger_factory._file is sys.stderr`.

Suite complète backend : **2452 passed**. Smoke uvicorn local :
`GET /api/health/classification` → 200 `disabled` (worker off).

## Suite (ops, hors PR)

Une fois mergé et entré dans la release : réconcilier le drift Alembic, puis
Weekly Release, puis vérifier `/api/health/classification` (`worker_running=true`,
`pending` qui chute) et le SQL de monitoring. Cf.
`.context/handoff_worker_classif_asap.md`.
