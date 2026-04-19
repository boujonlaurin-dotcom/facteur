# PR #437 — Stability hotfix : filtre Sentry `trafilatura` + rollback `community`

> Deux fixes ciblés issus du handoff CTO 2026-04-19 (D1 F1 + D3). Branche `claude/backend-stability-scalability-PAzL7` → `main`.

## Quoi

Deux commits atomiques sur la même branche :

1. **`8a84a4e` — D1 F1 (observabilité)** : ajout d'un callback `before_send` à `sentry_sdk.init(...)` dans `packages/api/app/main.py`. Drop (retourne `None`) les events qui matchent **simultanément** `logger.startswith("trafilatura")` ET un message contenant `"not a 200 response"` ou `"download error:"` (case-insensitive, teste `logentry.message` puis `message` top-level).
2. **`582ca53` — D3 ciblé (DB)** : `await db.rollback()` explicite dans le bloc `except` de `app.routers.community.get_community_recommendations`, guardé par son propre `try/except` pour ne pas casser le contrat fail-open de l'endpoint.

## Pourquoi

**D1** : quota Sentry projet **entièrement saturé** depuis 2026-04-18 15:00 UTC par du bruit HTTP externe émis par la lib `trafilatura` (404, timeouts, paywalls lors de l'extraction d'articles) remonté comme events `ERROR` via `LoggingIntegration`. Conséquence : **0 event accepté** pendant les ~6h suivant le déploiement de la release `c2d2d802` (PR #436 "infinite-load > 100 users"). On vole aux instruments cassés sur du code prod frais.

**D3** : Sentry issue `PYTHON-14` — 14 occurrences de `PendingRollbackError` sur 3 users distincts, culprit `community.get_community_recommendations`, dernière occurrence 2026-04-18 15:11 UTC (juste avant la saturation du quota). R3 (`_invalidate_on_supabase_kill`, `database.py:142`) devait neutraliser ce cas mais rate certaines signatures PgBouncer. Le handler attrape l'exception pour fail-open (mobile ne doit pas voir de 500 sur cette surface optionnelle), donc `get_db` ne voit rien et ne rollback pas → session dirty → PYTHON-14.

## Fichiers modifiés

**Backend (code)** :
- `packages/api/app/main.py` — `_sentry_before_send(event, hint)` + wire `before_send=_sentry_before_send` dans `sentry_sdk.init(...)`.
- `packages/api/app/routers/community.py` — bloc `except` enrichi d'un `try/await db.rollback()/except` avec log `debug`.

**Backend (tests)** :
- `packages/api/tests/test_sentry_before_send.py` (**nouveau**) — 8 cas.
- `packages/api/tests/test_community_recommendations_rollback.py` (**nouveau**) — 3 cas (FastAPI TestClient async + dependency_overrides).

**Docs** :
- `docs/maintenance/maintenance-sentry-trafilatura-filter.md` (**nouveau**) — problème / fix / portée / rollback.
- `docs/bugs/bug-community-pending-rollback.md` (**nouveau**) — root cause, trace, pourquoi fix ciblé (pas middleware global).

**Pas de changement** : mobile, migrations Alembic, schémas Pydantic, DB, infra, CI.

## Zones à risque

1. **`_sentry_before_send` (main.py)** — un filtre trop large couperait de vrais bugs HTTP internes. Le code exige `logger.startswith("trafilatura")` **ET** message matching : les deux conditions simultanément sont la garantie de non-régression. Vérifier que la logique de priorité `event.get("logentry", {}).get("message", "") or event.get("message", "") or ""` n'a pas de trou (cas : `logentry` présent avec `message=None`, `logentry` absent avec `message` top-level).

2. **Rollback guardé (community.py)** — le `try/except Exception` autour de `db.rollback()` est **voulu** et reprend le pattern de `get_db` (`database.py:261-269`). Si le reviewer pense qu'il faut remonter l'erreur de rollback, **non** : le contrat fail-open de cet endpoint est critique pour mobile (la surface `recommendations` est optionnelle, un 500 ici casse des écrans entiers).

3. **`sentry_sdk.init` ordre des args** — `before_send` ajouté en fin de kwargs, après `send_default_pii=False`. Pas d'impact comportemental mais à vérifier cohérence stylistique.

## Points d'attention pour le reviewer

- **Priorité de match message** : vérifier que `event.get("logentry", {}).get("message", "")` ne lève pas si `logentry` est `None` (Sentry peut le mettre à `None` explicitement, pas juste absent). Le test `test_passes_event_with_no_logger_field` couvre `logger` absent mais PAS `logentry=None`. Tolérance via le `or` chain qui repasse sur `message` top-level — acceptable mais à confirmer.

- **Portée du filtre volontairement étroite** : on ne filtre PAS tous les events `trafilatura.*`. Les vrais bugs internes de la lib (parsing OOM, stack non-HTTP) continuent de remonter. Décision assumée — voir doc maintenance.

- **Assertion `rollback.assert_awaited_once()`** dans le test nominal : c'est un `assert_not_awaited()` (pas appelé). Vérifier qu'on ne régresse pas vers un rollback inutile dans le happy path.

- **Pas de fix global D3** : per arbitrage CTO, on ne touche QUE `community.py`. Si le reviewer voit le même anti-pattern (handler `except + swallow + return fail-open sans rollback`) dans d'autres routers, **ne pas étendre dans cette PR** — c'est un backlog story à ouvrir après 24h de métriques post-D1.

- **Commentaire inline (1 ligne chacun)** : volontaire, CLAUDE.md interdit les docstrings multi-lignes dans le code. Le "pourquoi" non-évident est dans la doc maintenance/bug.

## Ce qui N'A PAS changé (mais pourrait sembler affecté)

- **`get_db` / `database.py`** : inchangé. Le listener `_invalidate_on_supabase_kill` n'est pas modifié. D3 est un fix **à l'appelant**, pas au pool. Si on élargit plus tard, ça se fera via un middleware ou un patch listener séparé.
- **Autres routers** : aucun autre handler fail-open n'est modifié, même s'ils ont probablement le même anti-pattern. Backlog story prévue.
- **Schémas Pydantic / Contrat API mobile** : `CommunityCarouselsResponse()` vide reste le retour fail-open, comportement identique côté mobile.
- **Release `c2d2d802` (Round 5, PR #436)** : PAS rollbackée. Décision CTO D2 en attente de 24h de données post-D1.
- **`uv.lock`** : non commité. Il a été régénéré par `uv pip install readability-lxml` en sandbox pour débloquer les tests locaux (dep manquante de `pyproject.toml`, à traiter séparément — hors scope hotfix stabilité).

## Comment tester

**Unitaires (reproductibles sans DB)** :

```bash
cd packages/api
./.venv/bin/python -m pytest tests/test_sentry_before_send.py tests/test_community_recommendations_rollback.py -v
# Attendu : 11 passed
```

**Suite adjacente (community + sentry + rollback)** :

```bash
./.venv/bin/python -m pytest tests/ -k "community or sentry or rollback" -p no:warnings
# Attendu : 25 passed
```

**Suite globale** :

```bash
./.venv/bin/python -m pytest tests/ -p no:warnings -q
# Attendu : 621 passed, 13 skipped, 43 errors
# Les 43 errors sont PRÉ-EXISTANTES (sandbox sans Postgres sur 127.0.0.1:54322).
# Vérifiable en stashant la PR : `git stash && pytest tests/test_source_management.py`
# reproduit la même erreur → non lié au diff.
```

**Validation post-merge (prod)** :

1. Après déploiement Railway, ouvrir Sentry → vérifier que le quota n'est plus saturé sous 24h (events `trafilatura` noise non acceptés, autres events OK).
2. Surveiller Sentry `PYTHON-14` sur 24h — doit arrêter de firer sur `community.get_community_recommendations`.
3. Si après 24h on voit la même signature sur un AUTRE router → rouvrir l'option "audit systématique" (D3 variante).

**Pas testé volontairement (scope + moyens)** :

- Pas de test E2E sur environnement Sentry réel (le sandbox n'a pas de quota de test Sentry).
- Pas de validation UI mobile (`/validate-feature`) : changement backend-only, pas de surface UI touchée.
- Pas de test de charge : hors scope hotfix stabilité, concerne D4 (scalabilité digest) qui reste en sprint planning.
