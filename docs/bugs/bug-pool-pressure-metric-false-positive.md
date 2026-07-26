# Bug — « DB pool pressure CRITICAL » est un faux positif (PYTHON-63)

- **Sentry** : [PYTHON-63](https://facteur.sentry.io/issues/PYTHON-63) — `level=fatal`
- **Occurrences** : 2 (première 2026-07-21 18:30 UTC, dernière 2026-07-25 14:20 UTC)
- **Message** : `DB pool pressure CRITICAL: 91.7% (>= 90%)`
- **Impact utilisateur** : aucun
- **Statut** : corrigé — la métrique était fausse, il n'y a jamais eu d'incident de capacité

## Symptôme

La sonde `_pool_health_probe` (`app/workers/scheduler.py`, toutes les 5 min) a levé une
alerte Sentry `fatal` annonçant un pool de connexions DB à 91,7 % de sa capacité, à deux
reprises en journée (18h30 puis 14h20 UTC — hors fenêtre des jobs de nuit). Aucune lenteur,
aucune erreur, aucun symptôme côté app.

## Cause racine — le dénominateur n'était pas la capacité

`app/observability/pool_stats.py` calculait :

```python
usage_pct = checked_out / (size + max(overflow or 0, 0))
```

L'intention était de diviser par la **capacité** du pool, soit
`pool_size + max_overflow` = 10 + 10 = **20** (`app/database.py`, `PROD_POOL_KWARGS`).

Mais `pool.overflow()` de SQLAlchemy ne renvoie **pas** `max_overflow`. Il renvoie
`_overflow`, le nombre de connexions **actuellement vivantes au-delà de `pool_size`** —
initialisé à `-pool_size` et incrémenté à chaque connexion créée :

```python
# sqlalchemy/pool/impl.py (2.0.25)
def size(self)       -> int: return self._pool.maxsize          # pool_size, constant
def overflow(self)   -> int: return self._overflow              # vivantes au-delà de pool_size
def checkedin(self)  -> int: return self._pool.qsize()          # idle en file
def checkedout(self) -> int: return self._pool.maxsize - self._pool.qsize() + self._overflow
```

Le dénominateur suivait donc les connexions vivantes, pas la capacité. En injectant
`checkedout()` dans la formule, elle se réduit à :

```
usage_pct = 1 - checked_in / (size + overflow)
```

⇒ **la métrique ne dépendait que du nombre de connexions idle en file.** Elle atteignait
100 % dès que la file se vidait momentanément, avec encore 10 connexions d'overflow
disponibles — et ne pouvait plus jamais en redescendre tant que l'overflow restait engagé.

Le flag `status: "saturated"` (`checked_out >= size + max(overflow, 0)`) souffrait du même
défaut : il se réduisait à `checked_in <= 0`, pas à « pool épuisé ».

### Mesure sur un vrai `QueuePool` (pool_size=10, max_overflow=10)

| checked_out | overflow() | usage_pct AVANT | usage_pct APRÈS |
|---|---|---|---|
| 9 / 20 | -1 | **90,0 %** → page `fatal` | 45,0 % |
| 10 / 20 | 0 | **100,0 %** → `saturated` | 50,0 % |
| 11 / 20 | 1 | **100,0 %** | 55,0 % |
| 18 / 20 | 8 | 100,0 % | 90,0 % → page `fatal` |
| 20 / 20 | 10 | 100,0 % | 100,0 % → `saturated` |

Le seuil de page (90 %) était donc franchi dès **9 connexions sorties sur 20**, soit 45 % de
charge réelle.

### Décodage de l'événement du 25/07

`91,7 % = 11/12` ⇒ `overflow = 2`, `checked_in = 1`, `checked_out = 11`.
Charge réelle : **11 / 20 = 55 %**, avec 9 connexions d'overflow encore libres.

### Corollaire sur PYTHON-5M

L'alerte historique PYTHON-5M (25/06, « pool à 100 % », marquée Résolue après limitation de
la concurrence des jobs de nuit) était très probablement **le même artefact** : la formule
renvoyait 100 % dès que `checked_in == 0`. Le fix PYTHON-5M n'a donc pas « lâché » — il n'y
avait vraisemblablement rien à corriger côté capacité.

Les mitigations mises en place à l'époque (`concurrency_limit=5` sur le job digest, decay
décalé à 06h50, `max_instances=1`) restent saines et **n'ont pas été revert**.

## Correctif

1. `app/observability/pool_stats.py` — lire `max_overflow` via `pool._max_overflow` (aucun
   accesseur public n'existe ; l'attribut est stable de SQLAlchemy 1.4 à 2.0), exposer
   `capacity = size + max_overflow`, et calculer `usage_pct = checked_out / capacity`.
   `saturated` devient `checked_out >= capacity`. `overflow` reste exposé pour le
   diagnostic, mais n'entre plus dans le dénominateur. Si `max_overflow < 0` (illimité), pas
   de `usage_pct`.
2. `app/observability/pool_stats.py` — **garde-fou anti-silence** : si le pool est
   dimensionné (`size()` répond) mais que la capacité est illisible (attribut privé renommé
   par une future version de SQLAlchemy, ou `max_overflow < 0`), on loggue
   `pool_capacity_unreadable` en `error`. Sans ça, `usage_pct` disparaîtrait, la sonde
   prendrait sa branche « NullPool » et **cesserait d'alerter silencieusement** — le pire
   mode de défaillance pour une métrique d'alerte.
3. `app/workers/scheduler.py` — les `capture_message` n'interpolent plus de chiffre variable
   dans le texte (Sentry groupe par message : `usage_pct` dans le texte crée une issue par
   valeur). Les compteurs partent dans le contexte Sentry `db_pool`.
4. `app/main.py` — le log `db_pool_pressure_high` de `/api/health/pool` expose désormais
   `capacity` (le dénominateur réel) en plus d'`overflow`, qui avait induit en erreur.

**Seuils inchangés** (warn 70 %, page 90 %, sustained 2) : ils portent désormais sur la
capacité réelle, soit 14 et 18 connexions sorties.

**Pas de changement de `pool_size`/`max_overflow`** — le pic réel observé est 11/20 (55 %).
Cf. `docs/bugs/bug-infinite-load-requests.md` : interdit sans preuve métrique.

## Non-régression

`packages/api/tests/test_pool_observability.py` :

- `test_read_pool_stats_does_not_page_on_engaged_overflow` — rejoue l'événement du 25/07
  (`size=10, overflow=2, checked_out=11`) et exige 55 %, sous le seuil de page.
- `test_read_pool_stats_capacity_matches_real_queuepool` — le garde-fou qui manquait :
  construit un **vrai** `QueuePool` avec les kwargs de prod et vérifie la capacité et le
  ratio à 9 puis 20 connexions sorties. Les fakes ne protégeaient pas contre une
  mécompréhension de l'API SQLAlchemy, qui est exactement l'origine du bug.
- `test_read_pool_stats_logs_when_sized_pool_has_unreadable_capacity` — supprime
  `_max_overflow` pour simuler un renommage SQLAlchemy et exige le log `error`.
- `test_read_pool_stats_nullpool_stays_quiet` — NullPool (dev) ne doit pas déclencher ce log.

## Suites à décider après ré-observation

Le nouveau signal étant fiable, surveiller une semaine les logs `db_pool_probe` (info, 5 min)
pour établir le p95 réel de `checked_out`. Pistes de pression identifiées pendant
l'investigation mais **non prouvées** par cette alerte :

- `app/services/push_dispatcher.py` — transaction ouverte pendant les envois FCM
  (`await asyncio.to_thread(sender, ...)`), avec `idle_in_transaction_session_timeout = 10 s`
  posé par `safe_async_session()` : un envoi lent peut tuer la transaction et faire perdre
  les écritures `status='sent'` de la boucle. **C'est un bug de correction en soi**, à traiter
  indépendamment de la pression pool.
- `app/services/recommendation_service.py` — jusqu'à 3 connexions simultanées par
  `/api/feed` (session request-scope idle-in-tx + 2 sessions courtes en `asyncio.gather`),
  amplifié par le single-flight de `app/routers/feed.py` qui fait attendre les waiters
  connexion déjà sortie.
- `app/services/grille_selector.py` — `asyncio.gather` de deux requêtes sur la **même**
  `AsyncSession` (`InterfaceError: another operation is in progress`).
- `app/workers/classification_worker.py` — engine séparé en `NullPool`, donc invisible de
  cette sonde et de `/api/health/pool`.
