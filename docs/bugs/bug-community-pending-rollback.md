# Bug — `PendingRollbackError` on `/api/community/recommendations` (PYTHON-14)

- **Sentry issue** : `PYTHON-14`
- **Last seen** : 2026-04-18 15:11 UTC (juste avant saturation quota Sentry)
- **Occurrences** : 14 events / 3 users distincts
- **Surface impactée** : `app.routers.community.get_community_recommendations`
- **Sévérité** : moyenne — surface optionnelle, contrat fail-open déjà en place, donc pas de 500 côté mobile, mais pollue Sentry et indique un slot de pool en état invalide.

## Symptôme

Stack trace Sentry récurrente :

```
sqlalchemy.exc.PendingRollbackError:
  This Session's transaction has been rolled back due to a previous exception
  during flush. To begin a new transaction with this Session, first issue
  Session.rollback().
  (Original cause: <Supabase/PgBouncer connection kill>)
```

Le handler retournait bien une réponse vide (fail-open OK côté mobile), mais la session SQLAlchemy restait marquée "dirty" et polluait Sentry jusqu'à saturation du quota.

## Root cause

1. Supabase / PgBouncer tue des connexions de façon asynchrone et remonte des erreurs que SQLAlchemy ne classe **pas** automatiquement comme `is_disconnect=True`.
2. Le listener `_invalidate_on_supabase_kill` (Round 3, `packages/api/app/database.py` l.120-156) matche un ensemble fini de signatures (`server closed the connection`, `dbhandler exited`, etc.). Certaines signatures Supabase ne sont pas couvertes → le listener ne déclenche pas l'invalidation → SQLAlchemy garde la session dans un état dirty.
3. Le handler `get_community_recommendations` attrape l'exception (`except Exception`) et retourne `CommunityCarouselsResponse()` vide — **contrat fail-open assumé** : mobile ne doit jamais voir un 500 sur cette surface optionnelle.
4. Comme l'exception est avalée dans le handler, `get_db` (qui rollback sur exception remontée) **ne voit rien** et ne rollback pas. La session sort du handler en état dirty.
5. Prochaine requête sur la même session (jamais, car `async with` la ferme), mais SQLAlchemy journalise `PendingRollbackError` au niveau de fermeture → Sentry reçoit 14× la même trace.

## Fix

Rollback **explicite** dans le bloc `except` du handler, lui-même guardé par un `try/except` pour que l'échec du rollback (si la connexion est vraiment morte) ne casse pas le contrat fail-open.

Patch (`packages/api/app/routers/community.py`) :

```python
except Exception:
    logger.exception("community_recommendations_failed")
    # Explicit rollback — _invalidate_on_supabase_kill misses some PgBouncer kill signatures (PYTHON-14)
    try:
        await db.rollback()
    except Exception as rb_exc:
        logger.debug("community_rollback_failed", error=str(rb_exc))
    return CommunityCarouselsResponse()
```

Même pattern défensif que `get_db` (`database.py` l.261-269) : un rollback sur connexion déjà morte ne doit jamais propager.

## Tests

`packages/api/tests/test_community_recommendations_rollback.py` couvre :

1. Service raise → handler rollback + fail-open.
2. Service raise + `rollback()` raise → handler **toujours** fail-open.
3. Nominal (pas d'exception) → pas de rollback (régression guard).

## Pourquoi pas un middleware global (pour l'instant)

Arbitrage CTO D3 : **targeted first, audit after 24h metrics**.

- Le correctif ciblé réduit immédiatement le bruit PYTHON-14 sans changer le comportement des 40+ autres routes.
- Un middleware global qui rollback sur toute exception non remontée impliquerait d'auditer chaque handler fail-open pour vérifier l'absence d'effet de bord.
- Si, après 24h de métriques post-déploiement, on constate la même signature sur d'autres routes, on ouvrira un ticket "global rollback middleware" avec audit complet de chaque handler fail-open.

## Références

- Sentry issue : `PYTHON-14`
- Round 3 (`bug-infinite-load-requests.md`) : contexte du listener `_invalidate_on_supabase_kill`.
- `packages/api/app/database.py` l.120-156 (listener), l.242-280 (`get_db`).
- `packages/api/app/routers/community.py` l.143-150 (fix D3 initial).

## Extension Round 6 (2026-04-19)

Après le crash 16:59 Paris (cf. `.context/perf-watch/2026-04-19-round6-1659.md`),
audit des handlers fail-open. Deux sites supplémentaires identifiés avec le
**même anti-pattern** que PYTHON-14 :

1. **`packages/api/app/routers/digest.py` l.164** — `_enrich_community_carousel` :
   `except Exception: logger.exception(...)` sans rollback. Appelé depuis
   `get_digest` (l.293) et `get_both_digests` (l.417-419). Risque HAUT : tout
   kill PgBouncer pendant l'enrichissement carousel laissait la session `db`
   injectée en état dirty → 500 via `PendingRollbackError` au commit final de
   `get_db`. Patch : rollback explicite garde par try/except (même pattern D3).

2. **`packages/api/app/routers/feed.py` l.326** — `feed_precommit_failed` :
   `except SQLAlchemyError: logger.warning(...)` sans rollback. Si `db.commit()`
   échoue à ce point (commit transitoire avant l'appel Learning), la session
   est dirty. Risque moyen (l'erreur à ce point précis est rare) mais patché
   par défense en profondeur — mêmes conséquences potentielles.

### Tests R6

- `tests/test_enrich_community_carousel_rollback.py` — 3 cas (service raise →
  rollback + fail-open ; rollback raise → toujours fail-open ; nominal empty →
  pas de rollback).
- Pas de test dédié pour `feed.py:326` — fix est un mirror 1:1 du pattern D3
  déjà couvert par `test_community_recommendations_rollback.py`.

### Systémique (D5 — pas dans ce patch)

L'audit Round 6 a confirmé que D3 ciblé était insuffisant. La même famille de
bugs peut exister sur d'autres endpoints non audités. Backlog story à ouvrir :
audit systématique des `except` fail-open dans `packages/api/app/routers/`
utilisant une session `db` injectée par `get_db` sans ni reraise ni rollback.
