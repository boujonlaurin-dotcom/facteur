# Bug : Erreur sources lors de l'onboarding — IdleInTransactionSessionTimeout

**Date** : 2026-05-25
**Statut** : Fix en cours
**Sentry** : PYTHON-4R, PYTHON-3C, PYTHON-3H, PYTHON-3Z, PYTHON-3R, PYTHON-37, PYTHON-34
**Impact** : Élevé — utilisateurs en onboarding bloqués à l'étape "Sélection des sources" avec erreur `sources_unavailable` (HTTP 503).

---

## Symptômes

À l'étape sources de l'onboarding, le mobile appelle `GET /sources` et reçoit un HTTP 503 `sources_unavailable`. L'écran d'erreur Facteur s'affiche, bloquant la progression.

Récurrent : plusieurs utilisateurs en onboarding touchés (confirmé par Sentry — PYTHON-4R encore actif le 2026-05-25).

---

## Chaîne causale

```
IdleInTransactionSessionTimeout (PYTHON-3C / 3H / 3Z / 3R / 37)
  → session laissée en état invalide
  → PendingRollbackError sur requête suivante (PYTHON-4R — actif aujourd'hui)
  → retry_db_op() exhauste 3 tentatives
  → HTTPException 503 sources_unavailable (PYTHON-34)
  → mobile : erreur à l'étape sources
```

---

## Cause racine

### Partie 1 — Architectural (critique)

`get_sources()` reçoit une session via `Depends(get_db)` qui **ouvre la transaction immédiatement** (`BEGIN; SET LOCAL idle_in_transaction_session_timeout=10000`). Ensuite l'handler acquiert `SOURCES_CACHE.lock(user_uuid)` pour éviter le thundering herd.

**Problème** : si un autre request concurrent du même user tient le lock (ex. retry automatique de `userSourcesProvider`), le second request attend le lock avec sa transaction IDLE ouverte. Si l'attente dépasse 10 s → Postgres kill → `InternalError: IdleInTransactionSessionTimeout`.

Les retries de `retry_db_op()` (3 tentatives) n'aident pas car ils se produisent APRÈS l'acquisition du lock — qui peut lui-même retomber dans le même état si le premier holder est lent.

```
Request 1 : acquiert lock → BEGIN; SET LOCAL idt=10s → 8 queries (lent)
Request 2 : BEGIN; SET LOCAL idt=10s → attend lock ...
             [10 s s'écoulent]
             → InternalError: IdleInTransactionSessionTimeout
             → retry × 3 (même séquence)
             → HTTPException 503
```

### Partie 2 — Performance (N+1, aggravant)

`get_all_sources()` appelle `get_curated_sources()` (5 queries) puis re-exécute 3 des mêmes queries pour les sources custom. Total : **8 queries avec 4 redondantes** (confirmé PYTHON-46 / PYTHON-1W "N+1 Query").

Le lock holder met plus longtemps → fenêtre d'idle plus large pour les waiters.

```
get_all_sources() :
  SELECT UserPersonalization         ← redondante (aussi dans get_curated_sources)
  → get_curated_sources() :
      SELECT Source (curated)
      SELECT UserSource.source_id    ← redondante
      SELECT UserSource.multiplier   ← redondante
      SELECT UserSource.subscription ← redondante
      SELECT UserPersonalization     ← redondante
  SELECT UserSource.multiplier       ← re-exécuté
  SELECT UserSource.subscription     ← re-exécuté
  SELECT Source (custom, join UserSource)
```

---

## Fix

### Fix 1 — `packages/api/app/routers/sources.py`

Supprimer `db: AsyncSession = Depends(get_db)` de `get_sources()`.  
Ouvrir une `safe_async_session()` **à l'intérieur de l'handler, après l'acquisition du lock**.

→ Le timer `idle_in_transaction_session_timeout` ne démarre qu'au moment où les queries commencent réellement. Plus de risque d'idle pendant l'attente de lock.

### Fix 2 — `packages/api/app/services/source_service.py`

Extraire un helper `_build_source_response()` (synchrone, pur).  
Refactoriser `get_all_sources()` pour charger les données user en une seule passe :
- 1 query UserSource combinée (source_id + multiplier + subscription)
- 1 query UserPersonalization
- 1 query Source curated
- 1 query Source custom

**4 queries au lieu de 8**, 0 redondance. `get_curated_sources()` aussi optimisée (3 queries au lieu de 5).

---

## Fichiers modifiés

| Fichier | Modification |
|---|---|
| `packages/api/app/routers/sources.py` | Session ouverte après lock (Fix 1) |
| `packages/api/app/services/source_service.py` | Élimination des queries redondantes (Fix 2) |

---

## Vérification

```bash
cd packages/api && pytest tests/test_sources.py -v
cd packages/api && pytest -v

# Test concurrence (thundering herd simulé)
# Les 2 requests doivent réussir sans 503
for i in 1 2; do
  curl -s -H "Authorization: Bearer <jwt>" localhost:8080/api/sources &
done
wait
```

Sentry : PYTHON-4R, PYTHON-3C ne doivent plus apparaître après déploiement.
