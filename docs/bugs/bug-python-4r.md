# Bug — `PendingRollbackError` au commit final du job digest (PYTHON-4R)

> **Élevé** — remonté par le triage Sentry nocturne du 2026-08-01.
> Issue Sentry : `PYTHON-4R`, culprit `run_digest_generation`.

## Symptôme

Le job `daily_digest` remonte en échec sur Sentry avec un `PendingRollbackError`
levé par le `await session.commit()` final de `run_digest_generation`
(`packages/api/app/jobs/digest_generation_job.py`).

C'est un **faux échec** : tous les digests ont bien été générés et committés en
amont. Seule la clôture de la transaction de lecture partagée plante. Conséquences
réelles : bruit Sentry, run marqué en échec, et le watchdog de 08h15 peut relancer
une génération inutile.

## Cause racine

`job.run()` est correctement isolé — chaque utilisateur, le mot du jour et la
couverture tournent dans leur propre session fille, avec leur propre commit. Mais
plusieurs étapes best-effort touchent la **session batch partagée** avec ce motif,
introduit par les patches PYTHON-5G / PYTHON-5M :

```python
with contextlib.suppress(Exception):
    await session.rollback()
    await apply_session_timeouts(session)   # ré-ouvre une tx via SET LOCAL
```

`apply_session_timeouts` (`packages/api/app/database.py:174`) **avale sa propre
exception** (log `debug`, pas de rollback). Si le `SET LOCAL statement_timeout`
échoue — scénario documenté de pression pool matinale / connexion Supavisor
flaky — la nouvelle transaction reste en `PENDING_ROLLBACK`, l'erreur est
silencieusement avalée, et rien ne rollback avant la fin. Le `commit()` final
explose alors.

Le span `http.client GET europe1.fr` visible dans la trace Sentry est ambiant
(travail éditorial concurrent), pas la cause.

## Correctif

Un seul fichier touché, périmètre strict du job digest. Avant le commit final :

```python
if session.in_transaction() and not session.is_active:
    await session.rollback()
try:
    await session.commit()
except PendingRollbackError:
    logger.warning("digest_generation_final_commit_pending_rollback")
    await session.rollback()
```

- `in_transaction() and not is_active` est la détection publique et exacte d'une
  transaction « invalide / needs rollback » en SQLAlchemy 2.0 — on la nettoie
  *avant* de committer.
- Le `except PendingRollbackError` est une ceinture-bretelles : si l'état de
  transaction nous échappe, on rollback au lieu de crasher, et on retourne quand
  même le résultat (le travail réel est déjà persisté).

Le commit final est le point de convergence de toutes les étapes amont : on ferme
la classe entière de bug quelle que soit l'étape qui a sali la session, sans jouer
au whack-a-mole. Aucun autre chemin (`except: rollback(); raise`) n'est modifié.

## Vérification

- `pytest tests/test_digest_generation_job.py` — vérifier qu'aucun test n'assertait
  un raise sur ce commit final.
- En staging : lancer un run digest, confirmer que les digests sont générés et
  qu'aucun `PendingRollbackError` ne remonte.
- Surveiller le log `digest_generation_final_commit_pending_rollback` : s'il
  apparaît, le garde-fou a joué — cela confirme la cause et signale une pression
  pool à regarder.

## Suivi hors périmètre

La racine partagée est `apply_session_timeouts`, qui avale son erreur sans
rollback. La corriger là (rollback dans son `except`) protègerait **tous** les
appelants, pas seulement le digest. C'est de l'infra partagée
(`packages/api/app/database.py`) → ticket séparé.
