# feat(api): cache feed observable, correct et ciblé (PR 2)

Base `main`. **Aucune migration.** Backend-only (0 fichier mobile).

## Résumé

PR 2 du plan « Accélérer et fiabiliser l'écran Essentiel ». L'écran Essentiel est
lent : chaque cold-open fait un fan-out de 10 à 14 `GET /api/feed?personalized=true`,
chacun payant le pipeline de scoring complet sur 1 seul worker uvicorn.

Un cache existait (`app/services/feed_cache.py`, clé `(user, variant)`, TTL 60 s)
mais était **neutralisé en pratique** : `invalidate(user_id)` purge *tous* les
variants du user, et l'écriture dominante est `POST /contents/{id}/status` en
`SEEN`, émise **à chaque scroll**. Scroller trois articles vidait le cache des
~12 sections de la Tournée.

Doc : `docs/maintenance/maintenance-essentiel-loading-speed.md` (décisions +
protocole de vérification staging).

PR 1 (`#1017`, mergée) a traité le volet mobile « Sources favorites toujours
rendues + attente lisible ».

## 1. Observabilité — la baseline, à lire avant de toucher au TTL

- `app/routers/feed.py` : un log structlog `feed_request` par requête —
  `cache=hit|miss|bypass`, `variant_class=default|personalized|none`,
  `duration_ms`, `items`. Avant, `feed_total` n'était émis que par
  `_compute_feed` : **un hit ne produisait aucun log**, le hit rate était
  invisible. `items` seulement sur miss/bypass (le compter sur un hit imposerait
  un `json.loads` du payload sur le chemin rapide).
- `app/main.py` : `GET /api/health/feed-cache`, calqué sur `/api/health/pool`,
  avec deux écarts assumés :
  - **gate par header `X-Health-Token`** (`hmac.compare_digest`) quand
    `HEALTH_METRICS_TOKEN` est configuré — nouveau champ `health_metrics_token`
    dans `Settings` (`app/config.py`), à côté de `admin_api_token`. `size` est un
    proxy du nombre d'users actifs. Sans le secret (staging), l'endpoint reste
    **ouvert** : fail-open assumé, à l'inverse de `require_admin_token` qui est
    fail-closed ;
  - `uptime_seconds` ajouté à `stats()` : les compteurs sont cumulatifs depuis le
    boot, donc le hit rate se lisse et masquerait une régression. La lecture se
    fait sur le **delta de deux échantillons**.

## 2. Correction préalable : les générations (bug pré-existant)

Sous le lock single-flight, `_compute_feed` prend 1,5 à 5 s puis `put()` écrivait
**inconditionnellement**. Une `invalidate` arrivant dans cette fenêtre était
écrasée : **un article masqué pouvait réapparaître** jusqu'à expiration du TTL.

Le bug existait déjà, mais l'invalidation ciblée l'aggraverait (elle inspecte le
payload *en cache*, l'ancien, alors que le payload en cours de calcul contient
l'article ⇒ faux négatif systématique dans la fenêtre) et un TTL plus long
multiplierait la durée du symptôme. Corrigé **avant** de scoper.

`generation(user_id)` renvoie `(compteur du user, compteur global)` — le second
sert aux invalidations cross-user, dont le rayon d'action inclut des users sans
entrée en cache. Le endpoint le capture juste avant `_compute_feed` et le repasse
à `put()`, qui droppe l'écriture si le couple a bougé. Un compteur global seul
aurait laissé l'écriture d'un user annuler le `put()` en vol de tous les autres,
soit en permanence avec le SEEN à chaque scroll.

## 3. Invalidation content-scoped, limitée aux sites prouvés sûrs

`invalidate_content(user_id, content_id)` ne purge que les variants du user
**dont le payload mentionne l'id** (scan d'octets, ~50 µs pour 12 variants).

> Pourquoi un scan d'octets plutôt qu'un `frozenset` d'ids capturé au `put()` :
> le set exigerait un walk qui connaît le schéma (`items`, `carousels[].items`,
> `clusters[]…`) et **manquerait silencieusement** les items imbriqués ⇒ faux
> négatifs, donc contenu périmé servi après écriture. Le scan est agnostique du
> schéma et son seul mode d'échec est le faux positif (une purge en trop,
> inoffensive). Le risque réel, une évolution de sérialisation qui casserait le
> match en silence, est épinglé par `test_cached_payload_item_ids_match_str_uuid`.

**Le point critique, c'est le périmètre.** Vérifié dans `content_service.py` :
like, save, hide, note upsert et la transition CONSUMED mutent
`UserSubtopic.weight` et `UserEntityAffinity.affinity`, qui alimentent le scoring
de *toutes* les sections. Les scoper laisserait un **classement** périmé partout.
On ne les touche pas.

| Site | Après |
|---|---|
| `update_content_status` **sans** transition consumed (SEEN au scroll) | `invalidate_content` ← **le gain principal** |
| `impress_content` (n'écrit que `manually_impressed`/`last_impressed_at`) | `invalidate_content` |
| `unsave_content` / `unhide_content` (aucun poids ajusté) | `invalidate_content` |
| `delete_note` — **n'invalidait rien** | `invalidate_content` (bug fix) |
| like/unlike, save, hide, feedback, status→CONSUMED | `invalidate()` inchangé |
| `upsert_note` — **n'invalidait rien**, or il boost les poids | `invalidate()` (bug fix) |
| `report_not_serene` — **n'invalidait rien**, et `is_serene=False` est un flip **global cross-user** | `invalidate_content_global` (bug fix) |
| les 27 autres sites (mute, follow, prefs, custom topics, refresh…) | inchangés |

Deux garde-fous notables :

- **Ne pas purger `_locks` dans `invalidate*`** : retirer un `Lock` détenu par
  des waiters casserait le single-flight, soit le thundering herd que ce cache
  existe pour éviter. Gardé par `test_invalidate_keeps_locks_alive`.
- Faux négatif résiduel borné par le TTL : le payload caché est une tranche
  top-N ; une action sur un article hors-tranche ne purge pas la variante, ce qui
  est correct puisqu'il n'était pas affiché.

## Décisions documentées (ce qui ne change PAS)

- **`--workers 2` : non.** Le cache est in-process et `invalidate` est
  process-local : avec 2 workers, un `POST /hide` traité par le worker A ne purge
  pas le cache du worker B ⇒ l'article masqué réapparaît. Idem
  `_analysis_cache` / `_perspectives_cache`. Condition de réouverture :
  invalidation partagée (Redis pub/sub). Et si le besoin est du parallélisme CPU,
  la vraie réponse est de sortir le scoring du chemin requête.
- **`FEED_CACHE_PERSONALIZED_TTL_SECONDS=300` : hors PR.** Étape ops Railway, à
  faire **après** lecture du hit rate réel. Défaut code inchangé à 60 s.
- `degraded_fallback` dans `FeedResponse` : abandonné (champ additif sans
  consommateur UI ; le log `feed_request` couvre le besoin).
- `profile_feed_latency.py` : pas réécrit — il bypasse le endpoint *et* le cache.

## Tests

- `tests/services/test_feed_cache.py` : +18 unitaires — invalidation ciblée /
  globale, générations (stale droppé, per-user, bump même sans purge), garde
  anti-régression sur `_locks`, `uptime_seconds`.
- `tests/routers/test_feed_cache_invalidation_sites.py` (nouveau) : épingle
  **quels endpoints purgent tout et lesquels ciblent**, plus l'invariant de
  sérialisation dont dépend le scan d'octets.
- `tests/test_health_feed_cache.py` (nouveau) : métriques exposées, fail-open
  sans secret, 404 avec secret configuré.
- `tests/test_feed_personalized_cache.py` : +3 sur le log `feed_request`
  (miss→hit, classe default, bypass paginé).
- Suite complète backend : **2648 passed, 18 skipped, 2 xfailed**.
- `ruff check` + `ruff format --check` OK sur les fichiers touchés ;
  `alembic heads` = 1 head (`sa02_alerts_v2`).
- Smoke live `uvicorn` : `/api/health/feed-cache` → 200 sans secret,
  `uptime_seconds` croissant sur deux échantillons ; avec `HEALTH_METRICS_TOKEN`
  posé → 404 sans header, 404 avec mauvais token, 200 avec le bon.

## Vérification sur staging (après déploiement)

1. Deux lectures de `/api/health/feed-cache` encadrant une ouverture d'app → hit
   rate sur le **delta**.
2. `grep 'feed_request'` dans les logs Railway sur 5 min d'usage réel.
3. **Scroller 3 articles puis rouvrir la Tournée < 60 s** → sections servies du
   cache. C'est le scénario que cette PR débloque.
4. `hide` un article visible + pull-to-refresh immédiat → il ne revient pas (test
   des générations).
5. Deux comptes en mode serein : A signale non-serein, B pull-to-refresh →
   l'article disparaît chez B.

Puis seulement : poser `FEED_CACHE_PERSONALIZED_TTL_SECONDS=300` et re-mesurer.

## Suivi post-merge (hors PR)

- `HEALTH_METRICS_TOKEN` n'est pas configuré sur Railway : l'endpoint sera
  **ouvert** sur staging (fail-open documenté). À décider avant que `production`
  n'avance.
- PR 3 (SWR client par section) : périmètre réel et ses **trois bloquants**
  (reseed nu qui détruirait l'hydratation, sections source non hydratées,
  `_dismissedIds` en mémoire seule) documentés en fin de doc maintenance.

## Hors périmètre

Aucun changement mobile, aucune migration DB, aucun changement de TTL.
