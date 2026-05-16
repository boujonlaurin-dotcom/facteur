# PR — feat(api): interest state unifié + favorites tables + endpoints (Story 22.1, 1/3)

## Summary

- **Story 22.1 — PR 1/3 (backend uniquement)** : pose le moteur du système d'intérêts unifié à 4 états (`hidden` / `unfollowed` / `followed` / `favorite`) appliqué aux Thèmes (`user_interests`), Sujets (`user_topic_profiles`) et Sources (`user_sources`). Cap dur à 3 favoris par catégorie (intérêts vs sources, séparés).
- 6 nouveaux endpoints (`GET/PATCH /api/user/interests`, `POST /api/user/interests/reorder` + symétriques pour `/api/user/sources`). `GET /api/users/top-themes` lit désormais `user_favorite_interests` en priorité (fallback weight desc + filter articles 14j). `GET /api/feed?topic=` accepte un slug OU un UUID custom_topic (lookup scoped user_id).
- Câblage `state` dans le pilier Pertinence : `hidden` → score 0 (court-circuit) ; `favorite` → weight/multiplier floor à 1.5 (boost garanti). Applique aux Thèmes ET aux Sujets pour cohérence sémantique.

## Mobile rétrocompat

Le mobile actuel **ignore** les nouveaux endpoints → 0 régression attendue. Les endpoints legacy (`PUT /api/personalization/topics/{id}`, `PUT /api/sources/{id}/weight`) restent intacts pour rétrocompat le temps que le mobile rattrape en PR 22.1.2 + 22.1.3.

`GET /api/users/top-themes` garde la forme `List[TopThemeResponse]` (mobile actuel fait `.take(2)` sur la réponse → toujours OK). Quand des favoris sont déclarés, ils priment ; sinon fallback inchangé.

## Migration impact

- **Tables touchées** : `user_interests` (+ colonne `state` + UNIQUE `(user_id, interest_slug)`), `user_topic_profiles` (+ colonne `state`), `user_sources` (+ colonne `state`).
- **Tables créées** : `user_favorite_interests`, `user_favorite_sources` (PK composite `(user_id, position)` + CHECK position 0..2 garantissant le cap=3 au niveau DB).
- **Type créé** : `interest_state` (PostgreSQL ENUM, 4 valeurs).
- **Dedupe défensif** : 39 doublons `(user_id, interest_slug)` confirmés en prod via audit MCP Supabase (`mcp__supabase__execute_sql`). Migration garde la row de plus grand `weight` pour chaque paire avant de poser la UNIQUE constraint. No-op sur DB neuve.
- **Migration de données conservatrice** : `weight ≤ 0.5` → `hidden` (0 lignes en prod actuellement, défensif pour futur) ; `priority_multiplier = 0.2` → `hidden` (75 sources + 52 topics affectés en prod). **Aucun favori auto-promu** — le user devra les déclarer explicitement via la nouvelle UI (PR 22.1.2).
- **Downgrade** : reverse complet testé localement (`alembic downgrade -1 && alembic upgrade head` round-trip OK).

## Algo reco — note pour review

La modification de `_score_behavioral` et `_score_custom_topics` touche un système calibré (V2). Garde-fous :
- `state=followed` (default sur toutes les rows post-migration) → comportement strictement identique à pré-PR (test `test_followed_default_unchanged_from_legacy`).
- `state=hidden` → court-circuit total (test `test_hidden_state_short_circuits_behavioral_score`).
- `state=favorite` + `weight=1.0` → bonus identique à `state=followed` + `weight=1.5` (test `test_favorite_state_floors_weight_to_15`).

Aucun user n'a `state=hidden` ou `state=favorite` au moment du merge (seuls 75 sources + 52 topics auto-hidden par la migration sur des `priority_multiplier=0.2`, mais ces rows étaient déjà filtrées en pratique). Impact algo immédiat ≈ nul.

## PostHog events

3 events flat snake_case (convention existante `waitlist_signup`, `veille_config_submitted`) :
- `interest_state_changed` (kind, target_id, new_state, prev_state)
- `interest_favorite_reordered` (favorite_count, kind: "interests"|"sources")
- `interest_cap_blocked` (kind, target_id, current_count)

## Cache invalidation

Chaque mutation invalide `FEED_CACHE` + `SOURCES_CACHE` pour le user concerné. Pattern hérité de `app/routers/personalization.py:143-144`.

## Test plan

- [x] `pytest -v` complet : **1121 passed, 13 skipped, 0 failures** (incluant les 18 nouveaux tests Story 22.1)
- [x] `alembic heads` → 1 ligne unique (`22a1_interest_state_favorites`)
- [x] `alembic upgrade head` sur DB vide OK
- [x] Round-trip `alembic downgrade -1 && alembic upgrade head` OK
- [x] Boot serveur OK, 4 nouvelles routes enregistrées
- [x] Pré-audit Supabase prod : 39 doublons → dedupe défensif intégré dans la migration
- [ ] CI verte (alembic-smoke + pytest + ruff)
- [ ] Peer review APPROVED

## Files

**Migration** : `packages/api/alembic/versions/22a1_interest_state_favorites.py`

**Models** : `app/models/enums.py` (+InterestState), `app/models/user.py` (+state UserInterest + UniqueConstraint), `app/models/user_topic_profile.py` (+state), `app/models/source.py` (+state UserSource), `app/models/user_favorites.py` (UserFavoriteInterest + UserFavoriteSource), `app/models/__init__.py`

**Schemas** : `app/schemas/user_interests.py` (request/response + cap validation)

**Service** : `app/services/user_interests_service.py` (UserInterestsService + UserSourcesStateService + exceptions FavoriteCapReached, TargetNotFound, TargetNotFavorite)

**Routers** : `app/routers/user_interests.py`, `app/routers/user_sources_state.py`, `app/routers/users.py` (get_top_themes étendu), `app/routers/feed.py` (topic UUID lookup), `app/main.py` (include_router × 2)

**Reco** : `app/services/recommendation/scoring_engine.py` (+user_interest_states), `app/services/recommendation/pillars/pertinence.py` (câblage 2 pillars), `app/services/recommendation_service.py` (populate)

**Constantes** : `app/constants.py` (`FAVORITE_CAP=3`)

**Tests** : `tests/routers/test_user_interests.py`, `tests/routers/test_user_sources_state.py`, `tests/routers/test_top_themes_with_favorites.py`, `tests/recommendation/test_pertinence_state.py`, `tests/alembic/test_interest_state_migration.py`

**Conftest** : `tests/conftest.py` (CREATE TYPE `interest_state` en pré-requis de `create_all` — sinon `psycopg.errors.UndefinedObject` au boot des tests)

**Story doc** : `docs/stories/core/22.1.systeme-interets-unifie.md` (créée)
