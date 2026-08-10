# Bug — N+1 d'upsert sur les impressions du feed (PYTHON-5Q)

> **Élevé** — remonté par le triage Sentry nocturne du 2026-08-01.
> Issue Sentry : `PYTHON-5Q`, culprit annoncé `get_personalized_feed`.

## Symptôme

Requêtes répétées / `SET LOCAL` en rafale sur le chemin feed, remontés comme un
N+1 par le monitoring. Sous charge, ça consomme le pool de connexions pendant que
l'utilisateur parcourt son flux.

## Cause racine

**Le culprit nommé par Sentry est trompeur.** Le chemin de *lecture*
`get_personalized_feed` → `_compute_feed` → `RecommendationService.get_feed` est
déjà entièrement batché : `_get_candidates` fait un `selectinload(Content.source)`,
`_hydrate_user_status` charge les statuts en un seul `IN (...)`, `_build_carousels`
passe par le catalogue unifié `build_phase_b`, et le contexte utilisateur est
chargé via `asyncio.gather` sur des short sessions. Plusieurs vagues de fixes N+1
antérieures y sont déjà documentées (Round 3/4/5, PYTHON-1C, PYTHON-37).

Le vrai N+1 est une **boucle d'écriture**, adjacente au culprit :

- `refresh_feed` (`packages/api/app/routers/feed.py`) : un `await db.execute(insert(...).on_conflict_do_update(...))` **par `content_id`** ;
- `undo_refresh` : le même motif, une requête par entrée à restaurer.

Ce sont les endpoints d'impressions que l'app tire pendant l'usage du feed — donc
N requêtes par rafraîchissement, plus un `SET LOCAL` par itération sous le wrapper
de session qui arme les timeouts par statement.

## Correctif

Les deux boucles sont collapsées en un seul `INSERT ... ON CONFLICT DO UPDATE`
multi-lignes.

Côté `undo_refresh`, la sémantique per-row est préservée via la pseudo-table
`EXCLUDED` : `stmt.excluded.last_impressed_at` restaure la valeur propre à chaque
ligne (y compris `NULL`), là où la boucle passait une valeur littérale différente
à chaque itération.

### La déduplication est load-bearing

Postgres refuse qu'un `ON CONFLICT DO UPDATE` vise deux fois la même ligne cible
dans un même statement (`cannot affect row a second time`). La boucle d'origine
n'avait pas ce problème — chaque `execute()` n'affectait qu'une ligne. Le passage
au bulk **introduit** donc un crash latent si le payload contient un `content_id`
en double. D'où :

- `refresh_feed` : `dict.fromkeys(...)` — dédup en gardant l'ordre ; toutes les
  valeurs sont identiques (`now`), l'ordre de gain est indifférent ;
- `undo_refresh` : `{e.content_id: e for e in ...}` — **last-write-wins**, ce qui
  reproduit exactement la sémantique de la boucle.

Effet de bord assumé : `refreshed` / `restored` comptent désormais les
`content_id` **uniques** et non les entrées reçues.

## Vérification

`pytest tests/test_feed_refresh_undo.py` — 9 tests verts contre un vrai Postgres
(pas un mock), dont deux ajoutés par ce correctif :

- `test_refresh_with_duplicate_content_ids`
- `test_undo_with_duplicate_content_ids`

Ces deux tests ont été validés en négatif : en désactivant temporairement la
déduplication, ils échouent tous les deux avec le `ProgrammingError` Postgres
« ON CONFLICT DO UPDATE command cannot affect row a second time ». Ils gardent donc
réellement l'invariant, ils ne font pas que passer.

Le cas « tous les `previous_last_impressed_at` à NULL » est couvert par le test
préexistant `test_undo_after_first_refresh_restores_null`, également vert contre
Postgres — ce qui écarte un souci d'inférence de type sur la colonne all-NULL du
bulk insert.
