# fix(observability): la métrique de pression du pool DB divisait par les connexions vivantes, pas par la capacité

## Résumé

L'alerte Sentry [PYTHON-63](https://facteur.sentry.io/issues/PYTHON-63)
`DB pool pressure CRITICAL: 91.7% (>= 90%)` (`level=fatal`, 2 occurrences depuis le 21/07)
est un **faux positif**. Le pool n'a jamais été proche de la saturation : la métrique était
fausse.

Base `main`. **Aucune migration.** Aucun impact mobile.

## Cause racine

`app/observability/pool_stats.py` calculait :

```python
usage_pct = checked_out / (size + max(overflow or 0, 0))
```

Le dénominateur était censé être la capacité (`pool_size + max_overflow` = 10+10 = **20**).
Mais `pool.overflow()` de SQLAlchemy ne renvoie pas `max_overflow` : c'est `_overflow`, le
nombre de connexions **vivantes** au-delà de `pool_size` (initialisé à `-pool_size`).

Le dénominateur suivait donc les connexions vivantes, pas la capacité. En injectant
`checkedout() = maxsize - qsize + _overflow` (source SQLAlchemy 2.0.25), la formule se
réduit à `usage_pct = 1 - checked_in / (size + overflow)` : **elle ne dépendait que du
nombre de connexions idle en file**, et saturait à 100 % dès que la file se vidait.

Mesuré sur un vrai `QueuePool(pool_size=10, max_overflow=10)` :

| checked_out | AVANT | APRÈS |
|---|---|---|
| 9 / 20 | **90,0 %** → page `fatal` | 45,0 % |
| 10 / 20 | **100,0 %** → `saturated` | 50,0 % |
| 11 / 20 (l'événement réel) | **100,0 %** | 55,0 % |
| 18 / 20 | 100,0 % | 90,0 % → page `fatal` |
| 20 / 20 | 100,0 % | 100,0 % → `saturated` |

Le seuil de page était donc franchi dès **9 connexions sorties sur 20** (45 % de charge
réelle), puis restait bloqué à 100 %.

`91,7 % = 11/12` ⇒ `overflow=2`, `checked_in=1`, `checked_out=11` → charge réelle
**11/20 = 55 %**, avec 9 connexions d'overflow libres.

**Corollaire** : le « 100 % » de **PYTHON-5M** (25/06) était très probablement le même
artefact. Le fix d'alors n'a pas « lâché » — il n'y avait rien à corriger côté capacité.
Ses mitigations ne sont **pas** revert.

## Changements

- `app/observability/pool_stats.py` — capacité lue via `pool._max_overflow` (pas
  d'accesseur public ; stable SQLAlchemy 1.4→2.0) ; expose `capacity` et `max_overflow` ;
  `usage_pct = checked_out / capacity` ; `saturated = checked_out >= capacity`. `overflow`
  reste exposé pour le diagnostic mais sort du dénominateur.
- `app/observability/pool_stats.py` — **garde-fou anti-silence** : si le pool est dimensionné
  mais que la capacité est illisible (attribut privé renommé par une future version de
  SQLAlchemy, ou `max_overflow < 0`), on loggue `pool_capacity_unreadable` en `error`. Sans
  ça, `usage_pct` disparaîtrait, la sonde prendrait sa branche « NullPool » et **cesserait
  d'alerter silencieusement** — le pire mode de défaillance pour une métrique d'alerte.
- `app/workers/scheduler.py` — les `capture_message` n'interpolent plus de chiffre variable
  dans le texte (Sentry groupe par message : `usage_pct` dans le texte crée **une issue par
  valeur**). Les compteurs partent dans le contexte Sentry `db_pool`, via un helper local
  qui dédoublonne les deux branches d'alerte.
- `app/main.py` — le log `db_pool_pressure_high` de `/api/health/pool` expose désormais
  `capacity` (le dénominateur réel) en plus d'`overflow`, qui avait induit en erreur.
- Docs : `docs/bugs/bug-pool-pressure-metric-false-positive.md` (neuf) + encart de
  correction en tête de `docs/maintenance/maintenance-saturation-pool-db-nocturne.md`.

**Seuils inchangés** (warn 70 %, page 90 %) : ils portent désormais sur la capacité réelle,
soit 14 et 18 connexions sorties. Le pic observé (11) reste silencieux — c'est voulu.

**Aucun changement de `pool_size`/`max_overflow`** : le pic réel est 11/20. Interdit sans
preuve métrique (`docs/bugs/bug-infinite-load-requests.md`).

Clés ajoutées uniquement (`capacity`, `max_overflow`) → `/api/health/pool` gagne des champs,
rien ne casse.

## Tests

`packages/api/tests/test_pool_observability.py` :

- `test_read_pool_stats_does_not_page_on_engaged_overflow` — rejoue l'événement du 25/07
  (`size=10, overflow=2, checked_out=11`) et exige 55 %, sous le seuil de page.
- `test_read_pool_stats_capacity_matches_real_queuepool` — **le garde-fou qui manquait** :
  construit un vrai `QueuePool` avec les kwargs de prod et vérifie le ratio à 9 puis 20
  connexions sorties. Les fakes ne protégeaient pas contre une mécompréhension de l'API
  SQLAlchemy, qui est l'origine exacte du bug.
- `test_read_pool_stats_logs_when_sized_pool_has_unreadable_capacity` — supprime
  `_max_overflow` pour simuler un renommage SQLAlchemy et exige le log `error`.
- `test_read_pool_stats_nullpool_stays_quiet` — NullPool ne doit pas déclencher ce log.
- `test_read_pool_stats_unbounded_overflow_has_no_usage_pct` — `max_overflow < 0`.
- `test_read_pool_stats_ok_with_negative_overflow` — attendu corrigé 50 % → 25 %.

Suite backend complète : `1992 passed, 1 failed, 547 errors` — l'échec
(`test_essentiel_endpoint.py::test_get_essentiel_uses_user_context_from_router`) et les 547
erreurs sont dus à l'absence de Postgres local sur le port 54322, et sont **reproduits à
l'identique sur `origin/main`** (vérifié via worktree).

## ⚠️ Après merge (actions PO)

1. Le texte du message Sentry change → **nouveau groupe d'issue**. Résoudre **PYTHON-63**
   en « faux positif — métrique corrigée ».
2. Surveiller 1 semaine les logs `db_pool_probe` (info, 5 min) pour établir le p95 réel de
   `checked_out` avant toute autre action.

## Suivi identifié (hors périmètre, non prouvé par cette alerte)

- `app/services/push_dispatcher.py` — transaction ouverte pendant les envois FCM
  (`await asyncio.to_thread`) avec `idle_in_transaction_session_timeout = 10 s` : un envoi
  lent peut tuer la transaction et faire perdre les écritures `status='sent'`.
  **Bug de correction en soi**, à traiter séparément.
- `app/services/recommendation_service.py` — jusqu'à 3 connexions simultanées par
  `/api/feed`.
- `app/services/grille_selector.py` — `asyncio.gather` sur la **même** `AsyncSession`.
- `app/workers/classification_worker.py` — engine `NullPool` séparé, invisible de la sonde.
