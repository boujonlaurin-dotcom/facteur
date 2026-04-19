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
- `packages/api/app/routers/community.py` l.143-150 (fix).
