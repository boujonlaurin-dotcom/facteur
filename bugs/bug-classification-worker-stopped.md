# Bug — La classification ML est à l'arrêt depuis le 30/06 ~01:00 UTC

Type : **Bug prod**. Statut : cause racine établie (données prod, read-only) ;
garde-fou code livré ; restauration ops (Railway) restante.

## Symptôme

Le worker de classification ML (in-process, lifespan FastAPI, gaté sur
`settings.ml_enabled`) ne tourne plus. Conséquence : `content.theme` /
`content.topics` sont **NULL sur tout le contenu frais** → le scoring
thème/subtopic est inerte au moment où les users lisent, la curation retombe au
source-level. ~26 k articles empilés en `pending`, backlog qui grossit.

## Root cause — établie par les données prod (read-only, 09/07/2026)

**Arrêt net, horodaté : 2026-06-30 ~01:00 UTC.**

- `classification_queue` : coupure franche — tout ce qui a > ~9,7 j est
  `completed`, tout ce qui est plus récent est `pending` (26 063 pending, oldest
  9 j 16 h). Ce n'est pas un retard qui s'écoule : c'est un traitement qui a
  **cessé**.
- `api_usage_events` : le call-site `classification_pass1` (et `good_news_pass2`)
  produit des appels jusqu'au **30/06 01:00** puis **plus AUCUN appel**, quel que
  soit le statut, jusqu'à aujourd'hui. Dernier appel OK : 30/06 01:00 (135 ok).
- **Mistral n'est pas en cause** : le call-site `editorial` (mistral-large)
  tourne tous les jours jusqu'au 09/07 (~40 appels/j). Clé + provider sains.
  `ML_ENABLED` a forcément été `true` (des milliers d'appels classif jusqu'au
  30/06). Ce n'est donc **ni la clé, ni le cap, ni un flip d'env évident**.
- **Le process est resté vivant** : `editorial` + digest quotidien continuent →
  ce n'est pas tout le service qui est tombé, c'est **la task asyncio du worker
  classif qui s'est arrêtée isolément**.

**Mécanisme le plus probable (code) :** `_run_loop()`
(`classification_worker.py`) ne rattrape que `except Exception` par tour, puis
`await asyncio.sleep`. Une **`asyncio.CancelledError` (sous-classe de
`BaseException`, non attrapée)** ou tout autre `BaseException` qui remonte d'un
`await` interne **termine la task** sans que `self.running` repasse à `False` et
**sans redémarrage** : le worker reste « down » silencieusement tant que le
process n'est pas rebooté avec un `start()` neuf. Aucune alerte n'existait sur la
profondeur de file → 10 j d'angle mort.

**Signal secondaire (pas la cause de l'arrêt permanent) :** le
**29/06 03:00→15:00**, tempête d'erreurs sur `classification_pass1`
(~550–900 err/h, latence 55–70 ms = rejets client immédiats, pas des timeouts ni
du 429 — le 429 est loggé séparément en `rate_limited`). Elle **s'est
auto-résorbée à 16:00** (retour `ok`, ~900 ms). Distincte de l'arrêt de 01:00 le
30/06.

### Un vrai bug secondaire repéré (hors périmètre de cette PR)

`classification_worker.py` (`if rec["retry_count"] < 2:`) → après épuisement des
retries, l'item est `mark_completed_with_entities(topics=[])`, donc **quitte la
file en `completed` avec `content.theme` NULL**. Explique le plafond ~68 % de
couverture sur le contenu 7-20 j (pas 100 %). **Décision PO : hors périmètre** —
à traiter dans une PR séparée si besoin.

## Décisions PO (tranchées)

- **Périmètre** : Volet 1 (restauration ops) + Volet 3 (garde-fou
  observabilité). La fuite thème NULL `retry_count < 2` est **hors périmètre**.
- **Service cible du worker** : **`production` uniquement**
  (`facteur-production`). Cadence hebdo → cohérent avec un arrêt non réparé
  depuis le 30/06 (pas de reboot prod entre-temps). **Ne PAS activer `ML_ENABLED`
  sur staging.**
- **Seuil d'alerte** `oldest_pending_age` : **12 h**.

## Fix — 3 volets

### Volet 1 — Restaurer (ops, nécessite l'accès Railway — BLOQUÉ)

- Sur **`facteur-production`** : confirmer `ML_ENABLED=true` ; **redéployer /
  restart** le service pour que la lifespan rejoue `start()`. (Ne pas activer sur
  staging.)
- Vérifier : `lifespan_ml_worker_started` dans les logs, réapparition d'appels
  `classification_pass1`, et **décroissance du `pending_count`**.

> **Bloquant** : le token Railway CLI est `Unauthorized` dans ce workspace et le
> MCP Railway n'est pas chargé → le Volet 1 ne peut pas être exécuté ici. À
> débloquer avant l'implémentation ops. La vérification décisive des
> logs/deploys autour du 30/06 01:00 UTC (deploy/restart, `ML_ENABLED` réel,
> `lifespan_ml_worker_started` vs `_skipped`, trace `CancelledError`/OOM) reste à
> faire sur le service qui héberge le worker.

### Volet 2 — Rattraper le backlog (26 k), sans régression

- Débit soutenu ≈ `batch_size=5` / `interval_s=10` → ~30 items/min ≈ ~36 k/j
  théorique ; ingestion ~2 500/j → le backlog (26 k) se résorbe en < 1 j une fois
  le worker relancé.
- **Ne PAS remonter `batch_size`** (régression Bonnes Nouvelles, PR #152). Si le
  drain mesuré est trop lent, le seul knob sûr est une **baisse temporaire bornée
  de `interval_s`** (env-only), pas le batch size.

### Volet 3 — Garde-fou anti-angle-mort (LIVRÉ dans cette PR)

Deux couches complémentaires :

**a. Superviseur de la task du worker** (`classification_worker.py`) :
- `start()` attache un `add_done_callback(self._on_task_done)` à `self._task`.
- `_on_task_done` : si la task se termine alors que `self.running` est encore
  `True` (mort inattendue, typiquement `CancelledError`), il émet une alerte
  Sentry (`capture_exception` si exception, sinon `capture_message` level=error)
  et **relance la task** (via `_spawn_loop`, se ré-attache). Si `self.running`
  est `False` (arrêt volontaire via `stop()`), il ne fait rien.
- **Redémarrage borné** : au-delà de `_MAX_RAPID_RESTARTS` (5) morts dans une
  fenêtre glissante `_RESTART_WINDOW_S` (60 s), il abandonne (alerte `fatal` +
  `running=False`) et laisse la restart-policy Railway (ALWAYS) recycler le
  process — évite une tight loop qui spammerait Sentry.

**b. Alerte externe sur la profondeur de file**
(`scheduler.py` → `_classification_queue_health_check`) :
- Job APScheduler toutes les 30 min. Lit
  `ClassificationQueueService.get_pending_stats()` et `capture_message` Sentry
  `level=error` si `oldest_pending_age > classification_queue_alert_age_hours`
  (défaut **12 h**, `config.py`). Fonctionne **même si le worker est mort**, tant
  que le scheduler tourne. Message stable (pas d'âge exact) pour garder un
  fingerprint Sentry unique ; valeurs exactes dans le log structuré.

## Fichiers modifiés

- `packages/api/app/workers/classification_worker.py` — `start()` +
  `_on_task_done` (superviseur).
- `packages/api/app/workers/scheduler.py` — `_classification_queue_health_check`
  + enregistrement du job (Interval 30 min).
- `packages/api/app/config.py` — `classification_queue_alert_age_hours = 12`.
- Tests : `tests/workers/test_classification_worker_supervisor.py` (nouveau),
  `tests/workers/test_scheduler.py` (job health-check).
- Aucune migration Alembic (pas de DDL).

## Vérification

- **Garde-fou (a)** : tests unitaires du superviseur — task morte sur exception
  → `capture_exception` + relance ; task annulée (CancelledError) + running=True
  → `capture_message` + relance ; running=False (stop volontaire) → no-op.
- **Garde-fou (b)** : tests unitaires du job — `oldest_age > 12 h` →
  `capture_message` ; sous le seuil / file vide → pas d'alerte ; erreur DB →
  swallow (ne crashe pas le scheduler).
- `cd packages/api && pytest tests/workers/ -q` : vert.
- **Restauration (post-Railway)** : après restart, logs
  `lifespan_ml_worker_started` ; `SELECT count(*) FROM classification_queue
  WHERE status='pending'` décroît ; `api_usage_events` montre des
  `classification_pass1` récents ; couverture `content.theme` sur 0-24 h repasse
  > 0 %.
