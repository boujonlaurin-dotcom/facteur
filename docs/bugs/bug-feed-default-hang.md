# Bug — Feed hang sur vue par défaut (mode non-filtré)

**Statut** : En cours
**Branche** : `claude/update-claude-docs-XWWVB`
**Sévérité** : 🔴 Critique (prod, P0)
**Fichiers critiques** :
- `packages/api/app/services/recommendation_service.py`
- `packages/api/app/routers/feed.py`

## Symptôme

Signalé en prod le 2026-04-21 :

- **Feed par défaut** (aucun filtre actif) → chargement infini
- **Feed avec filtre** (source, thème, topic, entity, keyword) → charge normalement

Le mobile reste sur le loader jusqu'à timeout client (45s), aucun payload reçu.

## Diagnostic

Le `RecommendationService._get_candidates` (recommendation_service.py:2200-2472)
construit sa requête SQL selon la combinaison `filter × followed_source_ids`.
Lignes 2312-2329, 4 branches mutuellement exclusives :

| Cas | Filtre de source appliqué au `query` |
|-----|--------------------------------------|
| `source_id` présent | `Content.source_id == source_id` |
| `theme/topic/entity/keyword` + followed | `OR(curated ∧ tier≠deep, id ∈ followed)` |
| `theme/topic/entity/keyword` sans followed | `curated ∧ tier≠deep` |
| **Rien + followed** (vue par défaut) | **aucun → `_use_two_phase=True`** |
| Rien + pas de followed | `curated ∧ tier≠deep` |

Dans la branche **two-phase** (recommendation_service.py:2430-2447), le
filtre de source est appliqué *après* tous les autres (mutes, paywall,
content_type, mode, serein) :

```python
user_query = query.where(Source.id.in_(list(followed_source_ids)))
user_query = user_query.order_by(Content.published_at.desc()).limit(500)
user_result = await self.session.scalars(user_query)   # ← pas de timeout
```

### Pourquoi ça hang uniquement en mode par défaut

1. **Pas de contrainte `curated ∧ tier≠deep`** → le pool de candidats potentiels
   avant `ORDER BY … LIMIT 500` est beaucoup plus large que dans les autres
   branches. Choix produit intentionnel (pas d'enrichissement curated dans le
   feed par défaut, voir commentaires lignes 2431-2432) mais coûteux en SQL.
2. **`Source.id IN (…)` à grande cardinalité** combiné avec tous les filtres
   personnalisés (mutes thèmes + topics + content_types + paywall +
   serein_exclusion) force parfois le planner Postgres à un plan lent (scan +
   sort au lieu de merge-append via `ix_contents_source_published`).
3. **Aucun timeout** sur la requête → si le plan dérape (stats périmées, pool
   DB chargé), la requête tire jusqu'à épuisement de la session et le mobile
   voit un spinner infini.
4. **Cache Round 5 (PR #436) masque partiellement** : un hit cache (TTL 30s)
   répond instantanément, mais le *miss* (cold open, invalidation sur write,
   bascule d'onglet après 30s) retombe sur la requête lente.

Les branches filtrées évitent le two-phase : leur `WHERE` inclut toujours
`Source.is_curated ∧ source_tier≠"deep"` (lignes 2319, 2324), ce qui réduit
drastiquement la cardinalité avant `ORDER BY` et permet au planner de choisir
un plan rapide — d'où « ça marche dès qu'on filtre ».

### Indexes existants (vérifiés dans `app/models/content.py:36-49`)

- `ix_contents_source_published (source_id, published_at)`
- `ix_contents_curated_published (published_at, source_id)`
- `ix_contents_published_at`
- `ix_contents_source_id`

→ **Ajouter un index supplémentaire n'est pas le quick fix.** Postgres peut
déjà scanner les index existants en sens inverse. Le vrai problème est le plan
choisi sous charge, qu'un `EXPLAIN ANALYZE` sur la requête prod devra confirmer.

## Plan de fix

### Quick fix (ce PR) — Timeout + fallback curated-only

`recommendation_service.py:2430-2447`, wrapper la requête `two-phase` dans
`asyncio.wait_for` :

- **Timeout** : 8.0s (marge sous le timeout mobile 45s, laisse le temps à
  `RecommendationService.generate_feed` de boucler proprement).
- **Sur `TimeoutError`** :
  1. `await self.session.rollback()` pour désamorcer la session et permettre
     sa réutilisation (même pattern que gestion `PendingRollbackError` déjà
     présente dans le service).
  2. **Fallback** : re-exécuter `query.where(Source.is_curated, Source.source_tier != "deep")` (la même branche que le cas « utilisateur sans sources suivies »
     ligne 2329) avec le même `ORDER BY/LIMIT`.
  3. `logger.warning("feed_two_phase_timeout_fallback_curated", …)` avec
     `user_id`, `followed_source_count`, `timeout_seconds` → visibilité
     Sentry/Railway pour mesurer la fréquence et déclencher le fix long-terme.

### Pourquoi ce fix

| Critère | Choix |
|---------|-------|
| **Alignement Round 5** | Reproduit le pattern `asyncio.wait_for` + fallback déjà utilisé sur `/digest/both` (PR #437, #448) |
| **Sémantique produit** | Préservée en cas nominal. Fallback = vue curated (acceptable comme dégradation ponctuelle) |
| **Risque** | Faible : ajout défensif, aucun changement du chemin heureux |
| **Réversibilité** | Revert trivial (un seul try/except) |
| **Observabilité** | Log structuré → on saura si le fallback se déclenche souvent |

### Hors-scope de ce PR (follow-up après observation prod)

1. **Diagnostic SQL** — `EXPLAIN ANALYZE` sur la requête prod via Supabase SQL
   Editor, identifier le plan réel et la cardinalité effective.
2. **Index additionnel** si nécessaire — envisageable uniquement si
   l'analyse confirme qu'un index spécifique manque. Pas de CREATE INDEX à
   l'aveugle : les 4 indexes existants couvrent déjà les axes principaux.
3. **Réduction de cardinalité IN** — cap à N sources suivies les plus récemment
   consultées (pagination du pool), à évaluer côté produit.
4. **`statement_timeout` session-level** — pourrait remplacer le wrapper
   `asyncio.wait_for` à l'échelle globale du service (plus propre, moins
   verbeux), mais nécessite audit de toutes les requêtes longues.

## Tests

### Unitaire

- `tests/test_recommendation_service_feed_timeout.py` (nouveau)
  - Happy path : la requête retourne dans les temps → comportement inchangé.
  - Timeout : la requête two-phase timeout → fallback curated s'active,
    `session.rollback` appelé, log warning émis, candidats non-vides si des
    sources curated existent.

### Manuel (post-deploy)

- Ouvrir l'app, vider le cache (ou attendre TTL 30s), charger le feed par
  défaut → répond en <10s (même si plan lent).
- Vérifier logs Railway : absence de `feed_two_phase_timeout_fallback_curated`
  en régime normal. Si présent → trigger l'investigation SQL.

## Validation CI + peer review

- Hook `post-edit-auto-test.sh` lance les tests liés automatiquement.
- Hook `stop-verify-tests.sh` bloque tant que les tests ne passent pas.
- PR `--base main` obligatoire (`staging` déprécié).
