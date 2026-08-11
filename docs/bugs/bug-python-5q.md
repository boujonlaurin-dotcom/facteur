# Bug — requêtes répétées sur `GET /api/feed/` (famille Sentry PYTHON-5Q)

> **Élevé** — reclassifié le 2026-08-10 après inspection des événements Sentry.
> Organisation `facteur`, projet `python`, région `https://de.sentry.io`.

## Symptôme et périmètre réel

Les issues `PYTHON-5V`, `PYTHON-5Q`, `PYTHON-5S`, `PYTHON-67`, `PYTHON-68`,
`PYTHON-69`, `PYTHON-6G` et `PYTHON-6H` sont toutes non résolues et groupées
sous `app.routers.feed.get_personalized_feed`
(`GET /api/feed/`, `packages/api/app/routers/feed.py`).

Ce n'est pas un culprit trompeur : les événements inspectés portent bien
`method=GET`, `url=https://facteur-production.up.railway.app/api/feed/` et
`status=200`. `PYTHON-5V` a encore reçu un événement le 2026-08-10 à 10:26 UTC.

Deux causes distinctes partagent le même détecteur N+1 Sentry ; elles doivent
rester séparées.

## (a) Sur-fetch réel — fenêtres de fraîcheur adaptatives

Concerne `PYTHON-5V`, `PYTHON-5S`, `PYTHON-67` à `PYTHON-69`, `PYTHON-6G` et
`PYTHON-6H`.

Dans `_get_candidates`, le mode de section personnalisée rejoue la requête
entière pour chaque palier `24`, `48`, `72` heures, puis peut la rejouer à
30 jours pour une section source sans article récent. Chaque requête SQL
`contents JOIN sources` est donc suivie par son `selectinload(Content.source)`
sur le petit ensemble de résultats. Le `selectinload` est correct ; c'est la
réexécution de la requête par palier qui constitue le sur-fetch.

### Correctif retenu

Conserver les requêtes adaptatives 24/48/72 h et leur `LIMIT
limit_candidates`. Les paliers plus larges ne sont interrogés que lorsque le
précédent n'atteint pas `THEMATIC_MIN_POOL_SIZE`; aucun chemin ne doit charger
tous les candidats de la fenêtre 72 h pour les filtrer ensuite en mémoire.

Le repli source « pas d'article récent » reste strictement identique : il ne
s'applique que lorsque le pool 72 h est vide, interroge alors les 30 jours et
positionne `source_no_recent_source` uniquement si ce repli fournit des
candidats. Cette requête est nécessairement distincte de la fenêtre 72 h.

Le test de non-régression vérifiera qu'une section source vide à 24/48 h mais
remplie à 72 h utilise trois requêtes de candidats toutes bornées (et un seul
chargement de sources), sans repli 30 jours. Les tests existants continueront
à protéger la sémantique 24 h, l'élargissement et le repli source.

## (b) Faux positif du détecteur — initialisation des sessions courtes

Concerne `PYTHON-5Q` seulement. Son motif répété est :

```sql
SET LOCAL statement_timeout = 30000
SET LOCAL idle_in_transaction_session_timeout = 10000
```

environ six fois par requête. `safe_async_session` les pousse à chaque ouverture
de session, en plus de `get_db`. Les sessions courtes du chemin de lecture sont
délibérées : elles empêchent le retour de transactions zombies `idle in
transaction` constaté le 2026-04-28. Elles ne doivent pas être fusionnées ou
supprimées pour satisfaire un détecteur de répétition.

### Décision retenue

Filtrer, avant envoi à Sentry, **uniquement les spans SQL dont la description
est exactement l'un de ces deux `SET LOCAL` de protection**, via
`before_send_transaction`. La transaction, ses autres spans SQL et sa durée
restent envoyés : le détecteur N+1 ne voit plus le bruit d'initialisation, sans
masquer une vraie répétition métier ni modifier l'architecture anti-zombie.

La latence est un sujet de performance séparé : l'événement étudié durait
11,3 s malgré un statut 200. Elle sera suivie avec le log existant
`feed_request` (`cache`, `variant_class`, `duration_ms`, `items`) et les spans
restants, non présentée comme un N+1 d'upsert.

## Correctif #1056 : valide, mais hors de ces issues

Le commit `e02391ca` (« Fixes PYTHON-5Q ») a correctement remplacé les boucles
d'upsert N+1 de `POST /api/feed/refresh` et
`POST /api/feed/refresh/undo` par des `INSERT ... ON CONFLICT DO UPDATE` bulk.
Ce N+1 d'écriture était réel et ses tests Postgres restent pertinents.

Il ne peut toutefois pas fermer les issues ci-dessus : aucun de leurs
événements n'est émis par ces endpoints `POST`. Les commentaires qui relient
ces upserts à la famille Sentry `PYTHON-5Q` devront être rendus neutres afin de
ne pas réintroduire cette confusion.

## Mesure et déploiement

Comparer avant/après les agrégats `feed_request` par `cache` et
`variant_class` : p50/p95 de `duration_ms`, nombre d'items et volume de misses
des sections personnalisées. L'attendu est un volume de candidats borné par
palier, sans variation de résultats à palier choisi identique.

La production Railway (`WEB`, environnement `production`) exécute actuellement
`fae905cb`, déployé le 2026-08-01. Un merge sur `main` ne changera les nouveaux
événements qu'après le prochain **Weekly Production Release**. Jusqu'à ce
déploiement, tout diagnostic Sentry doit vérifier le tag `release` des nouveaux
événements ; la persistance d'événements sur `fae905cb` ne constitue pas un
échec du correctif.
