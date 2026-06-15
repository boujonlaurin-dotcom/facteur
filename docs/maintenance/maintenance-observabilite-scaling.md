# Maintenance — Observabilité scaling (instrumentation API externes + pool + digest)

> **Type** : Maintenance / instrumentation (enabler scaling). **Aucun impact user-facing.**
> **Origine** : phase 1 de l'[investigation scaling 200 users](../scaling/scaling-investigation-200-users.md) — WP-E (observabilité). Débloque la mesure de WP-D (quotas/coûts Mistral), WP-B (digest), WP-A (pool).
> **Principe** : *mesurer avant de remédier*. PR **purement additive** — on instrumente, on ne change aucun comportement métier.
> **Statut** : ✅ CODE + VERIFY terminés (3 volets + migration) — en attente du GO pour la PR.

> **Réalisation (2026-06-10)** : les 3 volets sont implémentés et vérifiés.
> - **Migration** : `au01_api_usage_events`, `down_revision = gr02_grille_featured_article` (le head courant — *pas* `vf02` qui était le head au 2026-06-04 ; `gr02` a été ajouté depuis par #784). 1 seul head confirmé. Chaîne `upgrade head` + `downgrade -1` rejouées sur **DB vide** (scratch) → table + 2 index créés, rollback propre.
> - **VERIFY** : ~355 tests backend verts sur les modules touchés (`tests/test_usage_recorder.py`, `tests/test_pool_observability.py`, `tests/ml/`, `tests/editorial/`, `tests/workers/`, `tests/test_digest_generation_job.py`, `tests/test_health_pool.py`, `tests/services/search/`). Intégration live : `record_api_call` écrit bien 1 ligne/appel (Mistral + Brave), kill-switch `usage_tracking_enabled=False` ⇒ 0 insert, et la requête WP-D `GROUP BY provider, model, day` renvoie les comptes attendus.

---

## 1. État actuel (ce qui existe déjà — à RÉUTILISER)

L'exploration a montré que plusieurs briques existent ; cette PR **comble les trous** sans réinventer :

| Brique | Existant | Réf | Gap à combler |
|--------|----------|-----|---------------|
| Conso Mistral/Brave | Compteurs **en mémoire** `_brave_calls_month` / `_mistral_calls_month`, reset au redéploiement, **veille uniquement** | `smart_source_search.py:40-41,459,537` | **Aucune trace persistée** ; classif + éditorial **non comptés** |
| Logs structurés | structlog JSON + Sentry `LoggingIntegration` (ERROR→event) | `main.py:40-50,173-202` | — (réutiliser le pattern `logger.warning(event, **kw)`) |
| Alerte pool | `db_pool_pressure_high` loggé à `usage_pct ≥ 75 %` **mais seulement quand `/api/health/pool` est appelé** (passif) | `main.py:629-663` | Pas de **sonde périodique** active |
| Idle-in-transaction | `zombie_session_sweeper` tue les sessions idle > 5 min toutes les 5 min | `scheduler.py:247-253` | Le sweep n'**émet aucune métrique** (combien tué ?) |
| Durée digest | `digest_generation_job_completed` loggue `duration_seconds` + stats (structlog + PostHog) | `digest_generation_job.py:282-289` | **Couverture %** absente du log always-on (calculée seulement dans le watchdog quand < 90 %) |
| Table miroir | `source_search_logs` = pattern d'insert best-effort (`safe_async_session`, try/except, never raises) | `models/source_search_log.py`, `smart_source_search.py:150-165` | Modèle de référence pour la nouvelle table |
| Analytics | `analytics_events`, PostHog client fire-and-forget | `models/analytics.py`, `services/posthog_client.py` | — |

---

## 2. Périmètre

### ✅ Dans le scope (3 volets, 1 PR cohérente)
1. **Tracking persistant des appels API externes** (Mistral toutes passes + Brave) — nouvelle table append-only + recorder best-effort + instrumentation de tous les call sites.
2. **Résumé de run digest** always-on (durée + couverture %) — log structuré + event PostHog (réutilise les stats existantes).
3. **Sonde pool périodique + métrique idle-in-tx** — job APScheduler 5 min réutilisant l'introspection pool existante + compteur de sessions zombies tuées.

### ❌ Hors scope (volontairement, pour garder la PR additive et sûre)
- **Ne PAS** rebrancher l'enforcement des caps veille (`_brave/_mistral_calls_month`) sur la table → c'est un **changement de comportement**, renvoyé à WP-D une fois qu'on a les chiffres réels.
- **Ne PAS** corriger la *cause* des idle-in-transaction (band-aid sweeper déjà en place) → renvoyé à la PR « Hygiène DB ».
- **Ne PAS** toucher au DROP de l'index `ix_user_content_status_exclusion` → PR « Hygiène DB ».
- Aucun dashboard (Sentry/PostHog) créé par code — la donnée devient juste *requêtable*.

---

## 3. Plan technique

### Volet 1 — Table `api_usage_events` + recorder

**3.1 Modèle** — `packages/api/app/models/api_usage_event.py` (miroir de `source_search_log.py`)

Append-only, 1 ligne par appel API externe. Pas de contrainte d'unicité → **aucune contention de hot-row** (vs un compteur agrégé), et granularité temporelle par appel gratuite (analyse de pics, distribution horaire pour WP-C/D).

```python
class ApiUsageEvent(Base):
    __tablename__ = "api_usage_events"
    id: Mapped[UUID]        = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    provider: Mapped[str]   = mapped_column(String(16), nullable=False)   # "mistral" | "brave"
    model: Mapped[str | None] = mapped_column(String(48), nullable=True)  # "mistral-small-latest"… / None pour brave
    call_site: Mapped[str]  = mapped_column(String(48), nullable=False)   # voir enum §3.2
    user_id: Mapped[UUID | None] = mapped_column(PGUUID(as_uuid=True), nullable=True)  # null = système (classif/éditorial)
    status: Mapped[str]     = mapped_column(String(16), nullable=False, default="ok")  # ok | error | rate_limited
    latency_ms: Mapped[int | None] = mapped_column(Integer, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=datetime.utcnow, nullable=False)
    __table_args__ = (
        Index("ix_api_usage_events_created_at", "created_at"),
        Index("ix_api_usage_events_provider_created", "provider", "created_at"),
    )
```

**3.2 Recorder** — `packages/api/app/services/observability/usage_recorder.py`

```python
CALL_SITES = {
  "classification_pass1",   # mistral-small  (classification_service)
  "good_news_pass2",        # mistral-large  (good_news_classifier)
  "editorial",              # editorial llm_client (curation/pipeline/deep/perspective)
  "veille_suggester",       # mistral-medium (source/angle suggesters)
  "smart_search_mistral",   # mistral-small fallback (smart_source_search)
  "smart_search_brave",     # brave (smart_source_search)
}

async def record_api_call(provider, call_site, *, model=None, user_id=None,
                          status="ok", latency_ms=None) -> None:
    """Best-effort, jamais bloquant, jamais levant. Gated par settings.usage_tracking_enabled."""
    if not get_settings().usage_tracking_enabled:
        return
    try:
        async with safe_async_session() as session:
            session.add(ApiUsageEvent(...))
            await session.commit()
    except Exception as exc:                       # noqa: BLE001
        logger.warning("usage_recorder.persist_failed", call_site=call_site, error=str(exc))
```

> Volume attendu : ~3 000 inserts/jour (~90k/mois) — trivial, append-only, même classe que `analytics_events`. Cleanup ajouté (§3.5) pour borner.

**3.3 Instrumentation des call sites** (1 appel `await record_api_call(...)` par site, après la réponse — englobé en try/finally pour capter aussi `status="error"`) :

| Call site | Fichier | Ancre |
|-----------|---------|-------|
| classification_pass1 | `services/ml/classification_service.py` | `_call_mistral` ~`:378-388` |
| good_news_pass2 | `services/ml/good_news_classifier.py` | `_call` ~`:153-157` |
| editorial | `services/editorial/llm_client.py` | `chat_json` `:85`, `chat_text` `:189` (point unique pour curation/pipeline/deep/perspective) |
| veille_suggester | `services/veille/llm/{source,angle}_suggester.py` | `:155` / `:149` (passent par `EditorialLLMClient` → couvert si on instrumente `llm_client`, sinon ajouter `call_site`) |
| smart_search_mistral | `services/search/smart_source_search.py` | `_search_mistral` ~`:1047-1064` |
| smart_search_brave | `services/search/smart_source_search.py` | après `self.brave.search()` ~`:991` (à côté des `_brave_calls_month += 1` existants, qu'on **laisse en place**) |

> Astuce réutilisation : `editorial/llm_client.py` est le point unique pour 4 chemins (curation, pipeline, deep_matcher, perspective). On instrumente `chat_json`/`chat_text` une fois ; le `call_site` est passé en paramètre par l'appelant (défaut `"editorial"`). Veille passe par ce même client → on lui passe `call_site="veille_suggester"`.

### Volet 2 — Résumé de run digest (durée + couverture)

- Extraire le calcul de couverture du watchdog (`scheduler.py:72-96`) dans une petite fonction réutilisable `compute_digest_coverage(session, target_date) -> tuple[int,int,float]`.
- À la fin de `run_digest_generation` (`digest_generation_job.py` ~`:282`), émettre un **log always-on** `digest_run_summary` + un event PostHog avec : `duration_seconds`, `total_users`, `success`, `failed`, `coverage_pct`. (Réutilise `self.stats` déjà présent.)
- Aucune nouvelle table : `digest_generation_state` couvre déjà le timing par job.

### Volet 3 — Sonde pool périodique + métrique idle-in-tx

- Factoriser l'introspection pool de `main.py:629-633` dans `app/observability/pool_stats.py: read_pool_stats(engine) -> dict`.
- Nouveau job APScheduler `_pool_health_probe` (IntervalTrigger 5 min, à côté du zombie sweeper, `scheduler.py:~249`) : lit le pool, loggue `db_pool_pressure_high` + `sentry_sdk.capture_message(level="warning")` si `usage_pct >= settings.pool_alert_threshold_pct` (défaut 80).
- `zombie_session_sweeper` : émettre `db_idle_in_transaction_swept{count=N}` (réutilise le résultat du sweep) pour rendre l'idle-in-tx visible dans Sentry/structlog.

### Config (`config.py`, pattern `BaseSettings` + `@lru_cache`)
```python
usage_tracking_enabled: bool = True       # kill-switch instrumentation API
pool_alert_threshold_pct: int = 80        # seuil alerte sonde pool périodique
```

### Volet migration (Alembic) — zone à risque DB
- `cd packages/api && alembic revision --autogenerate -m "add api_usage_events table"` (autogenerate après import du modèle).
- **Additif pur** (CREATE TABLE + 2 index) → **non destructif**, rollback trivial (`downgrade` = `drop_table`).
- **Exactement 1 head** : `down_revision = gr02_grille_featured_article` (head courant au 2026-06-10 ; `vf02_favorite_veille_target` cité au plan était le head au 2026-06-04, dépassé depuis par #784). Nouveau head après migration : `au01_api_usage_events`. `alembic heads` ⇒ 1 seul head confirmé ; le hook `post-edit-alembic-heads.sh` bloque si > 1 head.
- Tester `upgrade head` **sur DB vide** (`make db-reset` / `facteur_test` 54322) — le `Dockerfile` rejoue `alembic upgrade head` au boot Railway, une migration cassée plante le déploiement.

---

## 4. Fichiers touchés

**Nouveaux** : `models/api_usage_event.py`, `services/observability/usage_recorder.py`, `observability/pool_stats.py`, `alembic/versions/<id>_add_api_usage_events_table.py`, tests `tests/test_usage_recorder.py`.
**Modifiés** : `config.py` (+2 settings) ; `models/__init__.py` (export) ; les 5 fichiers de call sites Mistral/Brave (§3.3) ; `services/editorial/llm_client.py` (param `call_site`) ; `jobs/digest_generation_job.py` (résumé run) ; `workers/scheduler.py` (sonde pool + métrique sweep + extraction coverage) ; `main.py` (factorisation `read_pool_stats`).

---

## 5. Tests & VERIFY

- **Unitaires** : `record_api_call` (best-effort : n'émet rien si flag off ; ne lève jamais même si la session échoue — mock qui raise) ; `compute_digest_coverage` ; `read_pool_stats` (pool mocké). Les hooks `post-edit-auto-test.sh` lancent les tests liés.
- **Intégration locale** : exporter `DATABASE_URL` → `facteur_test` (54322) (pas de `.venv` en Conductor) ; `alembic upgrade head` sur DB vide ; lancer une classif → vérifier des lignes dans `api_usage_events` ; `curl /api/health/pool`.
- **Suite complète** : `pytest -v` (backend). ⚠️ La suite mobile a ~27 échecs pré-existants (Hive/Supabase) hors scope — la CI ne lance que le backend.
- **Critères d'acceptation** :
  - [x] Une ligne `api_usage_events` par appel Mistral (call_sites `classification_pass1`, `good_news_pass2`, `editorial`, `veille_suggester`, `smart_search_mistral`) et Brave (`smart_search_brave`). *Instrumentation en `try/finally` à chaque site ; chemin live prouvé (Mistral + Brave écrits avec champs corrects, `model` null pour Brave).*
  - [x] `usage_tracking_enabled=False` ⇒ zéro insert (kill-switch). *Prouvé en live + test unitaire.*
  - [x] Recorder ne lève/ne bloque jamais (best-effort). *Test `test_record_never_raises_on_db_error` + design `safe_async_session` / `except Exception`.*
  - [x] `digest_run_summary` loggué à chaque run avec `coverage_pct` (+ `coverage_pct` ajouté à l'event PostHog `digest_generated`). *`compute_digest_coverage` factorisé, partagé avec le watchdog (tests verts).*
  - [x] Sonde pool émet l'alerte au-dessus du seuil (`pool_alert_threshold_pct`, défaut 80) + `sentry_sdk.capture_message` ; sweep émet `db_idle_in_transaction_swept{count}` always-on. *Tests `test_pool_observability.py`.*
  - [x] 1 seul head Alembic (`au01_api_usage_events`) ; `upgrade head` + `downgrade -1` OK sur DB vide (scratch).
  - [x] WP-D peut requêter la conso : `SELECT provider, model, date_trunc('day',created_at), count(*) FROM api_usage_events GROUP BY 1,2,3`. *Requête exécutée OK.*

---

## 6. Risques & rollback
- **Write amplification** sur le hot path classification (~3k/j) : append-only + best-effort + flag → négligeable ; rollback = `usage_tracking_enabled=False` (sans redéploiement de schéma) ou `alembic downgrade -1`.
- **Latence ajoutée** : insert best-effort dans une session courte dédiée, jamais dans la transaction métier ; fire-and-forget.
- **Pas de changelog user** : PR backend sans impact visible (la règle changelog vise l'impact user / les PR majeures user-facing).

## 7. Hors scope (rappel) → phases suivantes
WP-D (rebrancher les caps sur la table + modèle coût), PR « Hygiène DB » (cause idle-in-tx, DROP index mort, purge `classification_queue`), dashboards Sentry/PostHog.
