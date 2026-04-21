# PR — Hotfix feed par défaut qui load indéfiniment en prod (P0)

## Quoi

Ajoute un `asyncio.wait_for` (8 s) + fallback curated-only sur la requête
two-phase du feed par défaut (mode sans filtre). Sur timeout : rollback de
session + exécution d'une requête de repli sur les sources curated, plus un
log structuré pour mesurer la fréquence en prod. Aucun changement de
sémantique sur le chemin heureux.

## Pourquoi

Incident prod du 2026-04-21 : le feed en mode par défaut charge indéfiniment
dès que l'utilisateur a des sources suivies. Les vues filtrées (theme, topic,
source, entity, keyword) répondent normalement. Root cause identifiée dans
`recommendation_service.py:2430-2447` : la branche `_use_two_phase` applique
uniquement `Source.id IN (followed_source_ids)` après tous les filtres
personnalisés, sans la contrainte `is_curated ∧ source_tier ≠ "deep"` que les
autres branches appliquent. Le planner Postgres choisit parfois un plan lent
qui dépasse le `statement_timeout` libpq de 30 s ou sature la session sans la
libérer. Le cache applicatif Round 5 (PR #436) masque partiellement via les
hits TTL 30 s, mais chaque miss retombe sur cette requête.

Ce PR borne l'UX client (jamais de spinner infini) et dégrade gracieusement
sur la même vue curated que pour les utilisateurs sans sources suivies. Le
log émis permet de mesurer la fréquence du fallback et de décider si un
index supplémentaire ou un autre plan est nécessaire (hors-scope).

## Fichiers modifiés

Backend :
- `packages/api/app/services/recommendation_service.py`
  - Nouvelle constante module `_FEED_TWO_PHASE_TIMEOUT_S = 8.0`
  - Branche `_use_two_phase` (lignes 2449-2479) : `asyncio.wait_for` +
    `except TimeoutError` → `session.rollback()` + fallback curated +
    `logger.warning("feed_two_phase_timeout_fallback_curated", …)`

Tests :
- `packages/api/tests/test_feed_two_phase_timeout.py` (nouveau, 2 tests)
  - `test_two_phase_timeout_triggers_curated_fallback` : lock-in du fallback
  - `test_two_phase_happy_path_does_not_rollback` : garde-fou contre un
    rollback fantôme en régime nominal

Docs :
- `docs/bugs/bug-feed-default-hang.md` (nouveau) : diagnostic complet + plan
  de fix + hors-scope follow-ups

## Zones à risque

- `RecommendationService._get_candidates` est le point chaud du feed — tout
  le pipeline de scoring/ranking en aval dépend de `candidates_list`. Le
  fallback produit un `list[Content]` identique en forme, juste issu d'une
  autre `WHERE`.
- `self.session.rollback()` : la session est récupérée en bon état après une
  requête cancellée par `wait_for`. Pattern déjà utilisé ailleurs dans le
  service pour `PendingRollbackError`.
- Le fallback n'est pas lui-même wrappé dans `wait_for` : la requête
  curated-only est connue pour être rapide (c'est la branche par défaut des
  utilisateurs sans sources suivies). Choix assumé pour garder le fix
  minimal ; si jamais le fallback hang aussi, le `statement_timeout` libpq
  (30 s, `app/database.py:63`) reste notre filet de dernière chance.

## Points d'attention pour le reviewer

1. **Valeur du timeout (8 s)** — Le mobile time-out à 45 s par appel et
   `RecommendationService.generate_feed` a encore du travail (scoring,
   carousels, exclusions) après `_get_candidates`. 8 s laisse ~35 s de marge.
   Ajustable si besoin, constante module.

2. **Sémantique du fallback** — Retomber sur `is_curated ∧ tier ≠ "deep"`
   revient à servir la vue « utilisateur sans sources suivies ». Acceptable
   comme dégradation ponctuelle, mais pas équivalent au feed normal (l'user
   perd temporairement ses sources non-curated suivies). Alternative écartée :
   laisser la requête aller au bout → risque de hang persistant. À challenger
   si la volumétrie du fallback devient non-négligeable.

3. **`except TimeoutError`** — Capture `TimeoutError` (builtin, Python 3.11+),
   alias de `asyncio.TimeoutError`. Même pattern que le hotfix singleflight
   `/digest/both` (PR #448, commit `ec94c76`) après la correction lint UP041.

4. **Fallback query — réutilise `query`** — le `query` à ce stade contient
   déjà tous les filtres non-source (mutes, paywall, content_type, mode,
   serein, digest_content_ids). Le fallback n'ajoute que la contrainte
   curated + order/limit. Cohérent avec la branche `else` ligne 2334.

5. **Tests** — Mocks d'`AsyncSession` ; n'exécutent pas de vraie requête.
   Vérifient : comptage des appels `scalars`, `rollback.assert_awaited_once`,
   et absence de hang (outer `wait_for` 5 s comme garde-fou contre régression).

## Ce qui N'A PAS changé (mais pourrait sembler affecté)

- **Sémantique du feed par défaut sur le chemin heureux** : identique.
  Seul le cas timeout diffère.
- **Indexes DB** : aucune migration Alembic ajoutée. Les 4 indexes composites
  existants sur `content` (cf. `app/models/content.py:36-49`) couvrent déjà
  les axes principaux. Un index supplémentaire sans diagnostic prod serait
  du cargo-cult.
- **Cache Round 5 (`FEED_CACHE`)** : inchangé. Ce fix agit en aval du cache
  (sur le calcul de candidats, pas sur la clé de cache ni la TTL).
- **Autres branches de `_get_candidates`** : filtered paths (theme/topic/
  entity/keyword/source_id) inchangés, ils ne passent jamais par le
  `_use_two_phase`.

## Comment tester

### Unit test (déjà dans ce PR)

```bash
cd packages/api
DATABASE_URL="postgresql+psycopg://postgres:postgres@localhost:54322/postgres" \
  uv run --extra dev pytest tests/test_feed_two_phase_timeout.py -v
# → 2 passed
```

Les tests `tests/recommendation/` (34 tests) restent verts.

### Manuel post-deploy

1. Se connecter sur l'app prod avec un utilisateur qui a ≥ 20 sources suivies
   et un cache vide (force-kill de l'app ou attendre 30 s après dernière
   requête).
2. Ouvrir le feed en mode par défaut (aucun filtre actif).
3. **Attendu** : réponse en < 10 s. Aucun spinner infini.

### Observabilité

- Logs Railway : chercher `feed_two_phase_timeout_fallback_curated`.
  - Absent → fix pas déclenché, les users sont sur le chemin rapide.
  - Présent, rare → le fix protège ponctuellement, OK.
  - Présent, fréquent → déclencher `EXPLAIN ANALYZE` sur Supabase et
    envisager un index additionnel (follow-up hors-scope).
- Sentry : le `logger.warning` est capturé ; alerte possible si fréquence > N/min.

### Hors-scope volontairement

- **Pas d'index ajouté** : les 4 indexes existants (`ix_contents_source_published`,
  `ix_contents_curated_published`, `ix_contents_published_at`,
  `ix_contents_source_id`) couvrent les axes principaux. Ajouter sans
  `EXPLAIN ANALYZE` prod = cargo-cult. Piste documentée dans la doc bug.
- **Pas de `statement_timeout` session-level** : remplacerait proprement le
  wrapper `asyncio.wait_for` à l'échelle du service, mais demande un audit
  global des requêtes longues. Quick fix prioritaire ici.
- **Pas de cap sur la taille de la liste `followed_source_ids`** : changement
  produit (pagination des sources au scoring), pas technique.

## Références

- Doc bug : `docs/bugs/bug-feed-default-hang.md`
- Contexte Round 5 cache : `docs/bugs/bug-infinite-load-requests.md`
- Pattern timeout similaire : PR #437 (stability hotfix), PR #448 (singleflight
  `/digest/both`)
- Branche : `claude/update-claude-docs-XWWVB`
- Commit : `84c9b32`
