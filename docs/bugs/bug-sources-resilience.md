# Bug : Résilience endpoint /sources + UX erreur "Mes sources de confiance"

**Date** : 2026-04-26
**Statut** : Fix proposé (PR à venir)
**Impact** : Élevé — l'écran "Mes sources de confiance" affiche un message brut « DioException Error » à l'utilisateur lors d'erreurs DB transientes du backend (récurrentes en prod selon Sentry).

---

## Symptômes

1. **[Critique] Message d'erreur brut.** Quand `GET /sources` échoue, l'écran affiche `Erreur: DioException [...]` au milieu d'un `Center`, sans retry, sans message dans l'esprit Facteur. Pour un utilisateur c'est anxiogène et illisible.
2. **Aucun retry visible.** L'`ApiClient` Dio retry déjà sous le capot (timeout/connection/5xx), mais quand l'erreur passe à travers, l'utilisateur n'a pas de bouton "Réessayer" — il doit fermer/rouvrir l'écran.
3. **Pas de pull-to-refresh.** L'écran n'a pas de geste de refresh — incohérent avec les autres écrans Facteur.
4. **Endpoint backend fragile.** `GET /sources` appelle le service sans `try/except`, sans cache, sans retry sur erreur DB transiente. Sous pression du pool Postgres, n'importe quelle requête DB qui rate fait remonter une 500 brute → DioException côté mobile.

---

## Cause racine

**Sentry confirme les vraies pannes** (project `python`, top issues unresolved récents) :

| Issue | Title | Implication |
|---|---|---|
| PYTHON-26 | `InternalError: Unable to check out connection from the pool due to timeout` | Pool DB épuisé sous charge |
| PYTHON-4 | `OperationalError: server closed the connection unexpectedly` | Drop TCP transient Supabase ↔ Railway |
| PYTHON-14 | `PendingRollbackError: Can't reconnect until invalid transaction is rolled back` | Session DB corrompue après une erreur précédente |
| PYTHON-27 / PYTHON-1Q | `InternalError: DbHandler exited` | Erreur psycopg lourde |
| PYTHON-28 | `GC cleaning up non-checked-in connection` | Fuite de connexion contribuant à l'épuisement du pool |
| PYTHON-T / PYTHON-1W | `N+1 Query` sur sources | Confirme la sensibilité au pool |

Ces erreurs ne sont pas exclusives à `/sources`, mais cet endpoint **multiplie le risque** car son service `get_all_sources` enchaîne 5+ requêtes DB séquentielles sur 4 tables (Source, UserSource, UserPersonalization, UserInterest) :

- `packages/api/app/routers/sources.py:99-108` — handler minimal, pas de protection.
- `packages/api/app/services/source_service.py:46-104` — fan-out de queries.

Côté mobile :

- `apps/mobile/lib/features/sources/screens/sources_screen.dart:148` — affichait `Center(child: Text('Erreur: $err'))`.

---

## Résolution

### Backend — résilience `GET /sources`

**1. Try/except global + 503 + log structuré** (`packages/api/app/routers/sources.py`)
Wrap le handler dans `try/except (SQLAlchemyError, DBAPIError)` → log `sources_endpoint_db_error` + raise `HTTPException(503, "sources_unavailable")`. Le code 503 matche le pattern détecté par `FriendlyErrorView` côté mobile (« Petit souci de serveur »).

**2. Retry helper sur erreurs DB transientes** (`packages/api/app/utils/db_retry.py` — nouveau)
Helper `retry_db_op(op, session, max_attempts=3, base_delay=0.1, max_delay=1.0)` qui :
- Catche `OperationalError`, `InternalError`, `PendingRollbackError`, `DBAPIError`.
- Fait `await session.rollback()` avant chaque retry (clé pour récupérer d'un `PendingRollbackError`).
- Backoff exponentiel court (max 1s — l'utilisateur attend).
- Re-raise la dernière exception après `max_attempts`.

Pas de dépendance externe (tenacity non utilisé dans le repo) — implémentation pure stdlib en ~30 lignes.

**3. Cache court 30s SOURCES_CACHE** (`packages/api/app/services/sources_cache.py` — nouveau)
Calque de `feed_cache.FeedPageCache` : per-user, single-flight via `asyncio.Lock`, TTL configurable (`SOURCES_CACHE_TTL_SECONDS`, défaut 30s, `0` désactive). Réduit mécaniquement la pression sur le pool DB et rend l'écran instantané au refresh.

Invalidation explicite ajoutée à toutes les mutations qui affectent le catalog visible :
- `sources.py` : `add_source`, `delete_source`, `trust_source`, `untrust_source`, `update_source_weight`, `update_source_subscription`.
- `personalization.py` : `mute_source`, `unmute_source`.

### Mobile — UX erreur "Mes sources de confiance"

**1. `FriendlyErrorView` + `LaurinFallbackView`** (`apps/mobile/lib/features/sources/screens/sources_screen.dart`)
Reprend le pattern éprouvé de `feed_screen.dart:1215-1224` :
- Compteur `_consecutiveErrorCount` synchronisé avec l'état du provider via `ref.listen`.
- 1ère erreur → `FriendlyErrorView` (détecte timeout / réseau / 503 / générique → message Facteur + bouton Réessayer).
- 2 échecs consécutifs → `LaurinFallbackView` (proposition de prévenir Laurin par mail/WhatsApp).

**2. Pull-to-refresh** (idem)
Body wrappé dans `RefreshIndicator`. Helper `_scrollableCenter` ajouté pour rendre les états loading/error/empty compatibles avec le geste de refresh (les Center fixes ne scrollent pas ; on les enrobe d'un `SingleChildScrollView` à hauteur min = viewport).

**3. Bonus — 3 autres écrans alignés sur `FriendlyErrorView`**
- `apps/mobile/lib/features/saved/screens/saved_all_screen.dart:221`
- `apps/mobile/lib/features/saved/screens/collection_detail_screen.dart:267`
- `apps/mobile/lib/features/sources/screens/theme_sources_screen.dart:160-186` (avait un widget custom, migré pour cohérence).

---

## Fichiers impactés

```
packages/api/app/routers/sources.py             # try/except + cache + invalidation
packages/api/app/routers/personalization.py     # invalidation cache sur mute/unmute source
packages/api/app/services/sources_cache.py      # NOUVEAU — TTL cache singleton
packages/api/app/utils/db_retry.py              # NOUVEAU — retry helper
packages/api/tests/test_sources_resilience.py   # NOUVEAU — 13 tests (retry + cache + endpoint)

apps/mobile/lib/features/sources/screens/sources_screen.dart            # FriendlyError + LaurinFallback + RefreshIndicator
apps/mobile/lib/features/saved/screens/saved_all_screen.dart            # bonus
apps/mobile/lib/features/saved/screens/collection_detail_screen.dart    # bonus
apps/mobile/lib/features/sources/screens/theme_sources_screen.dart      # bonus
```

---

## Suivi (hors scope cette PR)

- **N+1 Query** (PYTHON-T / PYTHON-1W) : refonte de `get_curated_sources` / `get_all_sources` pour eager loading via `selectinload`. Demande une PR dédiée car ça touche les modèles SQLAlchemy.
- **GC cleaning up non-checked-in connection** (PYTHON-28) : audit séparé des paths qui leak des sessions.

---

## Vérification

- ✅ `pytest tests/test_sources_resilience.py -v` : **13 tests passent** (retry success/failure/exhaust/rollback-resilient/non-transient + cache miss/hit/expire/invalidate/disabled/stats + endpoint 503/recover/cache-hit-skips-db).
- ✅ `ruff check` clean sur tous les fichiers modifiés.
- ✅ `flutter analyze` clean sur les 4 fichiers modifiés (warnings `withOpacity` préexistants, non introduits).
- ⏳ Test manuel `/validate-feature` recommandé : ouvrir l'écran "Mes sources de confiance", couper le wifi, faire pull-to-refresh → `FriendlyErrorView` ; 2 échecs → `LaurinFallbackView` ; reconnecter wifi + retry → liste s'affiche, compteur reset.
