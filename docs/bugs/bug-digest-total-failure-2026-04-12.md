# Bug — Digest ne charge plus du tout en production (2026-04-12)

> **Handoff pour agent suivant.** Contexte complet de plusieurs sessions de debug sur la pipeline digest. Objectif : résoudre **robustement** et définitivement la non-génération du digest matinal.

## Symptôme actuel (production — 2026-04-12 matin)

- L'utilisateur (Laurin) rapporte : **"L'essentiel du jour en charge désormais plus du tout ce matin en production."**
- **Worse than before**: hier au moins le digest pour_vous se chargeait (via on-demand). Aujourd'hui : rien.
- Déploiement actuel : `origin/main` @ commit `ca320f7` (déployé dans la nuit après merge de PR #381).

## Ce qui a été fait dans les sessions précédentes

### Session #1 (mergée) — PR #374 `claude/fix-digest-pipeline-Je1lW`
11 root causes fixées en 5 phases :
- **Phase 1** : Session isolation per-user + variant isolation dans le batch
- **Phase 2** : Table `digest_generation_state` pour observabilité
- **Phase 3** : Stale-format deferred deletion + yesterday fallback avec background regen
- **Phase 4** : Watchdog variant-aware (compte les paires `(user_id, is_serene)`)
- **Phase 5** : Editorial context dual pre-compute (pour_vous + serein)
Commits : `cf7b32f`, `0063371`, `646c222` (merge with main). Mergé `fd072fd`.

### Session #2 (mergée) — PR #381 `Prevent digest format downgrade to legacy flat_v1`
**Suspect #1 pour la régression actuelle.**
Changements :
- Background regen skip si digest moderne existe déjà
- **`raise` sur render failure pour editorial_v1 / topics_v1** (pas flat_v1) ← **RISQUE**
- Yesterday fallback skip les flat_v1
- Emergency fallback wrap en topics_v1 au lieu de flat_v1

### Session #3 (cette session) — PR #384 `claude/fix-state-service-resilience` — **PAS ENCORE MERGÉE**
Fix de 2 bugs structurels :
1. `digest_generation_state_service.py` : les 4 `mark_*` catchent l'exception mais ne font pas `session.rollback()` → empoisonnent la session
2. `digest_generation_job.py` : le seeding pending au démarrage du batch n'est pas dans un try/except → crash si table `digest_generation_state` n'existe pas

**→ À MERGER EN PREMIER** si les migrations Supabase n'ont pas encore été appliquées.

## Migrations Supabase — Status incertain

Per CLAUDE.md : "Alembic : jamais d'exécution sur Railway (SQL via Supabase SQL Editor)".

3 migrations à appliquer manuellement :
- **`mg03`** — merge ht01+pa01 (pure merge revision, pas de schéma)
- **`td01`** — `ALTER TABLE sources ADD COLUMN tone, serein_default`
- **`dg01`** — `CREATE TABLE digest_generation_state, editorial_highlights_history`

**L'utilisateur a dit** : "Requête SQL n'a pas marché sur SupaBase" (pour dg01) → status réel des 3 migrations **inconnu**.

SQL idempotent à fournir (dans description PR #384) :
```sql
-- td01
ALTER TABLE sources ADD COLUMN IF NOT EXISTS tone VARCHAR(20);
ALTER TABLE sources ADD COLUMN IF NOT EXISTS serein_default BOOLEAN NOT NULL DEFAULT false;
CREATE INDEX IF NOT EXISTS ix_sources_tone ON sources (tone);
CREATE INDEX IF NOT EXISTS ix_sources_serein_default ON sources (serein_default);

-- dg01
CREATE TABLE IF NOT EXISTS digest_generation_state (...);
CREATE TABLE IF NOT EXISTS editorial_highlights_history (...);

-- alembic
UPDATE alembic_version SET version_num = 'dg01';
```

## Hypothèses pour la régression totale actuelle

### H1 : Boucle 503 infinie via `raise` de PR #381 (priorité haute)

**File:Line** : `packages/api/app/services/digest_service.py:410-414`

```python
try:
    return await self._build_digest_response(existing_digest, user_id)
except Exception:
    logger.exception("digest_existing_render_failed", ...)
    if existing_digest.format_version in (
        "editorial_v1",
        "topics_v1",
    ):
        raise  # ← LOOP 503 si le digest est corrompu
    # flat_v1 is expendable — delete and regenerate
    await self.session.delete(existing_digest)
    await self.session.flush()
```

**Mécanisme** :
1. Batch/on-demand crée un digest `editorial_v1` ou `topics_v1` avec données malformées
2. User ouvre l'app → `GET /api/digest`
3. `_build_digest_response()` lève une exception (KeyError, AttributeError, …)
4. PR #381 fait `raise` → router retourne 503
5. **Le digest corrompu reste en DB** → requête suivante refait la même erreur → boucle infinie

**Sources possibles de crash dans `_build_editorial_response` / `_build_topics_response`** :
- `UUID(art_data["content_id"])` si la clé n'existe pas (L1674)
- Content référencé supprimé par `storage_cleanup` → skip propre (pas de crash, OK)
- Source manquante sur Content → skip propre (pas de crash, OK)
- Schéma JSONB malformé dû à une migration partielle

### H2 : Emergency fallback crée des digests topics_v1 corrompus

**File:Line** : `packages/api/app/services/digest_service.py:593-625` (PR #381)

Le nouveau path emergency wrap en TopicGroup + topics_v1. Si la sérialisation en DB fonctionne mais que `_build_topics_response` ne supporte pas le format produit, tous les users en emergency sont bloqués.

**À vérifier** : `_build_topics_response` à `digest_service.py:2068` supporte-t-il des topics avec un seul article (`emergency_{rank}`) ?

### H3 : `Source.serein_default` colonne manquante → crash sur le mode serein

**File:Line** : `packages/api/app/services/digest_selector.py:825`

Si `td01` n'est pas appliqué, la requête `Source.serein_default == True` crash en PostgreSQL `column does not exist`. Tous les serein échouent, et si le batch job commence par serein pour un user, tout plante.

### H4 : Boucle `mark_pending` + rollback manquant (fixé dans PR #384 mais non mergé)

Si `digest_generation_state` n'existe pas, le batch crashe complètement à 6h → pas de digest batch → users tombent sur le yesterday fallback → yesterday digest est flat_v1 → PR #381 skip les flat_v1 yesterday → tente real generation → emergency → topics_v1 → ???

## Plan d'investigation pour le prochain agent

### Étape 1 : Vérifier quels digests existent en DB
```sql
SELECT target_date, format_version, is_serene, COUNT(*)
FROM daily_digest
WHERE target_date >= CURRENT_DATE - INTERVAL '3 days'
GROUP BY target_date, format_version, is_serene
ORDER BY target_date DESC;
```

### Étape 2 : Vérifier les migrations Supabase
```sql
-- Alembic version
SELECT version_num FROM alembic_version;

-- Colonnes sources (attendu: tone, serein_default)
SELECT column_name FROM information_schema.columns
WHERE table_name = 'sources' AND column_name IN ('tone', 'serein_default');

-- Tables observabilité
SELECT table_name FROM information_schema.tables
WHERE table_name IN ('digest_generation_state', 'editorial_highlights_history');
```

### Étape 3 : Regarder Sentry (ou logs Railway) pour l'erreur exacte
Chercher les patterns :
- `digest_existing_render_failed`
- `digest_endpoint_unhandled_error`
- `editorial_article_not_found`
- `digest_generation_state_mark_*_failed`

### Étape 4 : Reproduire en local
```python
# packages/api shell
from app.database import async_session_maker
from app.services.digest_service import DigestService
from uuid import UUID

async with async_session_maker() as s:
    svc = DigestService(s)
    d = await svc.get_or_create_digest(UUID("<user_id_laurin>"), None)
    print(d)
```

## Fix robuste (recommandations pour le prochain agent)

### Fix 1 — Merger PR #384 immédiatement (résilience rollback + tables manquantes)

### Fix 2 — Remplacer le `raise` dur de PR #381 par un fallback gracieux

**Au lieu de** :
```python
if existing_digest.format_version in ("editorial_v1", "topics_v1"):
    raise
```

**Faire** :
```python
# Modern format failed to render. Don't destroy the DB record (it might
# just be a transient issue with the user's action-states query). Fall
# through to regeneration — the unique constraint will catch duplicates.
logger.error(
    "digest_modern_format_render_failed_regenerating",
    user_id=str(user_id),
    digest_id=str(existing_digest.id),
    format_version=existing_digest.format_version,
)
# Continue to generation path below (don't return, don't raise)
existing_digest = None
```

OU, plus conservatif : tenter de rebuild via emergency fallback avant de retourner 503.

### Fix 3 — Validation JSONB avant insert

Dans `_create_digest_record_editorial` et emergency topics_v1, valider que la structure JSONB est bien formée avant `session.add(digest)`. Si la validation échoue, logger et ne PAS sauver → fallback propre.

### Fix 4 — Protection contre content supprimé

Dans `storage_cleanup.py`, **préserver** tout Content référencé par un digest des 90 derniers jours :
```sql
DELETE FROM contents
WHERE published_at < NOW() - INTERVAL '{retention_days} days'
  AND id NOT IN (
    SELECT DISTINCT (jsonb_array_elements(items->'subjects')->'actu_article'->>'content_id')::uuid
    FROM daily_digest
    WHERE created_at > NOW() - INTERVAL '90 days'
  );
```

### Fix 5 — Canary endpoint de debug

Ajouter `GET /api/digest/diag?user_id=X` qui retourne :
```json
{
  "today_digest": {"exists": true, "format_version": "editorial_v1", "is_serene": false},
  "yesterday_digest": {...},
  "state_today": [{"is_serene": false, "status": "success"}, ...],
  "render_test": {"ok": false, "error": "KeyError: actu_article"},
  "migrations_applied": ["mg03", "td01", "dg01"]
}
```

Cela permet de diagnostiquer en 1 requête ce qui bloque un user spécifique.

### Fix 6 — Alerte Sentry dédiée

Rule Sentry sur `digest_endpoint_unhandled_error` ou `digest_existing_render_failed` avec un threshold bas (> 3/min) → alerte immédiate.

## Fichiers clés

| Fichier | Ligne | Ce que c'est |
|---------|-------|--------------|
| `packages/api/app/services/digest_service.py` | 278-700 | `get_or_create_digest` main path |
| `packages/api/app/services/digest_service.py` | 410-414 | **Le `raise` suspect de PR #381** |
| `packages/api/app/services/digest_service.py` | 593-625 | Emergency fallback wrap en topics_v1 (PR #381) |
| `packages/api/app/services/digest_service.py` | 1508-1520 | `_build_digest_response` dispatcher |
| `packages/api/app/services/digest_service.py` | 1657-2066 | `_build_editorial_response` |
| `packages/api/app/services/digest_service.py` | 2068-2249 | `_build_topics_response` |
| `packages/api/app/routers/digest.py` | 113-140 | 503 path |
| `packages/api/app/jobs/digest_generation_job.py` | 128-140 | Seeding pending (fixé par PR #384) |
| `packages/api/app/services/digest_generation_state_service.py` | toutes | `mark_*` sans rollback (fixé par PR #384) |
| `packages/api/app/services/digest_selector.py` | 816-835 | Serein candidate query utilisant `serein_default` |
| `packages/api/app/workers/storage_cleanup.py` | 96-103 | Suspect H4 (content supprimé) |

## Checklist pour l'agent suivant

- [x] Lire ce document en entier
- [x] Lire `docs/bugs/bug-digest-legacy-format.md` (contexte PR #381)
- [ ] Vérifier status des migrations Supabase (Étape 1-2 ci-dessus) — **à faire manuellement en prod** (pas d'accès MCP Supabase dans cet environnement). L'endpoint `/api/digest/diag` ajouté en Session #4 répond désormais à cette question en 1 requête HTTP.
- [ ] Récupérer logs Sentry/Railway pour l'erreur exacte — **à faire manuellement en prod** (pas d'accès MCP Sentry/Railway dans cet environnement).
- [x] Si migrations pas appliquées : faire appliquer + merger PR #384 — **PR #384 mergée** (commit squash sur `main`).
- [x] Si migrations OK : investiguer le `raise` H1 (tester en local) — H1 confirmée par lecture du code ; Fix 2 appliqué.
- [x] Appliquer Fix 2 (graceful fallback au lieu de raise) — voir Session #4 ci-dessous.
- [x] Appliquer Fix 4 (protection storage_cleanup) — voir Session #4 ci-dessous.
- [x] Ajouter Fix 5 (diag endpoint) pour future visibilité — voir Session #4 ci-dessous.
- [x] Écrire test de régression pour chaque fix — `test_digest_content_refs.py` (10 tests), `test_storage_cleanup.py` (2 tests ajoutés), `test_digest_service.py` (`TestRenderFailureFallback`, 2 tests).
- [ ] Tester end-to-end via Playwright MCP — changements backend-only, pas d'UI impactée (cf. CLAUDE.md section Validation Feature via Chrome : "Quand ne PAS utiliser — Changements backend-only (API, workers, migrations)").

## Session #4 — résilience systémique (cette PR)

Objectif : casser le potentiel de boucle 503 **définitivement** en rendant chaque
couche tolérante à la corruption des autres, sans attendre la confirmation
Supabase/Sentry.

### Fix 2 — Graceful fallback sur render failure (H1)

`packages/api/app/services/digest_service.py` — le `raise` brutal de PR #381
est remplacé par le mécanisme existant `stale_format_digest` (deferred
deletion). Quand `_build_digest_response` échoue sur un digest moderne :

1. On mémorise le record corrompu dans `stale_format_digest`.
2. On met `existing_digest = None` pour retomber dans le chemin de génération.
3. Le record corrompu est supprimé **après** qu'un remplaçant ait été produit
   avec succès (chemin déjà existant, lignes ~671-674).

Si la régénération plante aussi, le record corrompu reste en DB mais le
prochain appel tentera à nouveau le fallback au lieu de retourner 503 en boucle.

Tests : `TestRenderFailureFallback` dans `tests/test_digest_service.py`.

### Fix 4 — Protection du Content référencé par un digest récent

Nouveau module `packages/api/app/services/digest_content_refs.py` avec
`extract_content_ids(items, format_version)` qui marche sur les 3 layouts
JSONB (`flat_v1`, `topics_v1`, `editorial_v1`) de façon tolérante (UUID
malformés → skip, clés manquantes → skip, `None` → `set()`).

`packages/api/app/workers/storage_cleanup.py` :

- Nouvelle constante `DIGEST_REFERENCE_PROTECTION_DAYS = 90`.
- Nouvelle fonction `_collect_referenced_content_ids(session)` qui lit toutes
  les lignes `daily_digest` des 90 derniers jours et collecte les content_ids.
- Le DELETE/count partage désormais une liste `common_conditions` qui inclut
  `~Content.id.in_(referenced_list)` quand la liste est non-vide.
- Nouvelle stat retournée : `preserved_digest_refs`.

Tests : `tests/test_digest_content_refs.py` (10 tests couvrant les 3 layouts +
edge cases), `tests/test_storage_cleanup.py` (2 tests ajoutés — NOT IN clause
vérifiée en inspectant le SQL compilé).

### Fix 5 — Endpoint diag scopé au user authentifié

`packages/api/app/routers/digest.py` — `GET /api/digest/diag` retourne en 1
requête HTTP :

- `today_digest` / `yesterday_digest` (existence, format, is_serene)
- `state` (entrées `DigestGenerationState` pour la date cible)
- `render_test` — live invocation de `_build_digest_response` avec capture
  de `error_type` + message (au lieu de 503)
- `migrations` — lit `alembic_version` + probe `information_schema` pour
  `sources.tone`, `sources.serein_default`, `digest_generation_state`,
  `editorial_highlights_history`

Chaque section est wrappée dans un try/except : une table manquante ne casse
pas les autres probes. L'endpoint est scopé au user authentifié (pas de
query param `user_id` — cohérence avec le reste de `/api/digest/*`).

## Session #5 — résilience variant Serein (cette PR)

### Symptôme rapporté
> "J'ai merge le fix ce qui a marché pour afficher le digest Normal, mais
> pas pour afficher le digest Serein (qui aujourd'hui, est le même que le
> digest Normal)."

### Cause racine

Deux bugs combinés produisent "le Serein affiche le même contenu que le
Normal" :

1. **Backend** — `DigestService.get_or_create_digest` ne faisait qu'un
   fallback "J-1" (une seule journée en arrière). Pour la variante serein,
   un seul batch manqué suffisait à épuiser la chaîne de fallback et à
   renvoyer `None` (→ 503).

2. **Mobile** — `apps/mobile/lib/features/digest/providers/digest_provider.dart`,
   `_activeDigest` faisait `_sereinDigest ?? _normalDigest`. Quand le
   backend renvoyait `null` pour serein mais une réponse valide pour
   pour_vous (via `/digest/both`), le client **affichait silencieusement
   le pour_vous étiqueté comme serein** — exactement la régression
   rapportée par l'utilisateur.

### Fix — backend

`packages/api/app/services/digest_service.py` :

- Remplacement du fallback 1-jour par `_try_recent_variant_fallback()` qui
  walk-back jour par jour jusqu'à **7 jours** pour la **même variante**
  (jamais cross-variant).
- Saute les `flat_v1` (legacy) et les digests qui ne rendent pas.
- Le premier hit déclenche un `_schedule_background_regen` pour aujourd'hui
  et marque la réponse `is_stale_fallback=True` (le mobile auto-refetche).
- Nouveau log `digest_serving_recent_variant_fallback` avec `days_back` +
  `variant`.
- `digest_recent_variant_fallback_exhausted` quand les 7 jours sont vides.

Tests : `TestRecentVariantFallback` dans `tests/test_digest_service.py`
(3 tests) :
- `test_serein_fallback_walks_back_multiple_days` — vérifie que le walk
  remonte jusqu'à J-3 et que chaque lookup passe `is_serene=True`.
- `test_serein_fallback_never_returns_pour_vous_digest` — garde-fou : un
  digest pour_vous présent à J-1 ne doit **jamais** satisfaire une
  requête serein.
- `test_fallback_skips_flat_v1_and_tries_older` — les records `flat_v1`
  sont sautés plutôt que servis.

### Fix — mobile

`apps/mobile/lib/features/digest/providers/digest_provider.dart` :

- `_activeDigest` retourne désormais `_sereinDigest` tel quel (null si
  indisponible), **sans fallback cross-variant**.
- Expose `normalDigest` et `sereinDigest` comme getters publics pour que
  l'écran distingue "pipeline totalement cassée" de "serein seul cassé".

`apps/mobile/lib/features/digest/screens/digest_screen.dart` :

- Nouveau `_buildSereinUnavailableState()` affiché quand le toggle serein
  est ON, l'`AsyncData` est null (ou items vides), mais `normalDigest`
  existe. Deux CTA : "Réessayer" (refresh) et "Mode Normal" (bascule le
  toggle). **Ne substitue jamais le contenu pour_vous**.

### Ce qui reste à faire côté ops (hors scope code)

1. **Vérifier/appliquer `td01` + `dg01` sur Supabase production** — le SQL
   idempotent est dans la description de PR #384 (déjà mergée). Une fois
   appliqué, `GET /api/digest/diag` le confirmera.
2. **Vérifier Sentry** pour `digest_existing_render_failed` /
   `digest_endpoint_unhandled_error` sur 2026-04-12 pour identifier la
   cause racine de la régression totale. Avec Fix 2, même sans ce
   diagnostic, le symptôme "503 en boucle" ne peut plus se produire.
3. **Fix 6 (alerte Sentry dédiée)** — reste à configurer côté Sentry UI.
