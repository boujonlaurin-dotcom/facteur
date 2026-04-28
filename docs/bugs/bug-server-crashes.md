# Bug — Crashs serveur récurrents (restart manuel Railway requis)

**Statut** : FIX Phase 1 vraiment appliquée le 2026-04-26 (PR #465 avait édité `railway.json` déprécié — sans effet sur le déploiement, qui lit `railway.toml` depuis PR #368)
**Branche** : `boujonlaurin-dotcom/fix-server-crashes`
**Sévérité** : 🔴 P0 — plusieurs restarts manuels/jour
**Rapporté** : 2026-04-23 (Laurin)

---

## Symptômes

1. « Crash » matinal récurrent ~9h Paris (après le batch digest 6h + watchdog 7h30 + top3 8h).
2. 2-3 indisponibilités supplémentaires par jour à horaires variables.
3. Chaque épisode nécessite un **restart manuel** des services Railway.
4. Les endpoints `/api/sources/*` parfois continuent à 500 même après restart.

---

## Cause racine — matinale (confirmée statique)

**Site 1** : `packages/api/app/workers/scheduler.py:96-125,192-200` — `_scheduled_restart()` est enregistré comme job cron à **01h00, 09h00, 17h00 Europe/Paris** :

```python
async def _scheduled_restart() -> None:
    logger.warning("scheduled_restart_initiated", ...)
    os.kill(os.getpid(), signal.SIGTERM)
```

**Site 2** : `railway.json:10` — `"restartPolicyType": "ON_FAILURE"`.

**Mécanisme** :
1. 09:00 Paris — SIGTERM envoyé au process API.
2. uvicorn intercepte le signal, draine les requêtes, **exit code 0** (arrêt propre).
3. Railway interprète exit 0 = shutdown volontaire. Avec `ON_FAILURE`, **ne relance pas**.
4. Container reste à l'arrêt. L'app est indisponible jusqu'au restart manuel.

Le 09:00 tombe ~1h après la fin du batch digest (6h→7h30 watchdog→8h top3), d'où l'association « après le digest ».

**Historique** : `_scheduled_restart` a été ajouté comme mitigation temporaire de la fuite de sessions SQLAlchemy (cf. `bug-infinite-load-requests.md`). Le commentaire de la fonction dit : *« À retirer dès que le fix architectural (P1/P2) est déployé et validé ≥ 48h sans saturation du pool. »* Les fixes P1/P2 sont référencés comme déployés dans `bug-infinite-load-requests.md` (Round 3+). On retire donc le job en même temps qu'on passe la policy Railway à `ALWAYS` — si jamais le leak revenait (monitoring Sentry), on réactive via rollback.

---

## Fix Phase 1

### F1.1 — `railway.toml` → `restartPolicyType: ALWAYS`

```diff
 "deploy": {
     "healthcheckPath": "/api/health",
     "healthcheckTimeout": 120,
-    "restartPolicyType": "ON_FAILURE"
+    "restartPolicyType": "ALWAYS",
+    "restartPolicyMaxRetries": 10
 }
```

**Effet** :
- Railway relance le container après n'importe quel exit (y compris code 0 post-SIGTERM).
- Couvre aussi tout futur exit propre mal géré (OOM adjacent, uvicorn qui quit sur un shutdown path mal câblé, etc.).
- `maxRetries=10` + `healthcheckTimeout=120s` → borne une boucle de crash infini. Si l'app ne se stabilise pas sur 10 tentatives, Railway marque le déploiement `UNHEALTHY` et alerte.
- **Note** : Railway ne reset pas le compteur `maxRetries` après une période de stabilité (pas de `restartPolicyMaxRetriesWindow`). Un crash unique après plusieurs heures d'uptime décompte quand même dans les 10. Si ce comportement pose problème à terme, Phase 2 peut introduire un liveness check DB externe.

**Risque** : très faible. `ALWAYS` est la policy par défaut pour les services HTTP sur Railway. Réversible en 1 ligne.

### F1.2 — Retirer le job `scheduled_restart` du scheduler

Fichier : `packages/api/app/workers/scheduler.py`.

On retire :
- La fonction `_scheduled_restart()` (lignes 96-125 sur main)
- L'enregistrement du job dans `start_scheduler()` (lignes 185-200 sur main)
- Les imports `os` et `signal` devenus inutiles en haut du fichier
- Le champ `scheduled_restart_cron` du log de démarrage

Tests : on remplace `test_scheduler_includes_scheduled_restart_job` et `test_scheduled_restart_sends_sigterm` par un seul test de garde `test_scheduled_restart_job_is_not_registered` qui assure la non-régression.

**Justification** : avec F1.1, `_scheduled_restart` n'est plus qu'un redémarrage cosmétique 3×/jour. Les fixes architecturaux P1/P2 (cf. `bug-infinite-load-requests.md`) sont déployés. En cas de retour de la fuite, le monitoring Sentry remonte la signature `QueuePool limit reached` → rollback git d'une seule commit suffit.

---

## Phase 2 (à décider après 48h observation post-merge)

Si symptôme résiduel persiste (indisponibilités qui ne correspondent pas à une fenêtre SIGTERM) → traiter séparément. Hypothèses candidates :
- Pool saturé par digest 6h + top3 8h (`pool_size=10, max_overflow=10, concurrency_limit=10` → aucune marge pour trafic utilisateur).
- `BackgroundTasks` de `sync_source` qui retient des sessions longtemps.

Voir plan complet : `/Users/laurinboujon/.claude/plans/system-instruction-you-are-working-lovely-lake.md` (ordonnancement F2.1 décalage top3, F2.2 réduction concurrency, F3.1 worker dédié).

---

## Fichiers modifiés (Phase 1)

| Fichier | Changement |
|---------|------------|
| `railway.toml` | `ON_FAILURE` → `ALWAYS` + `restartPolicyMaxRetries: 10` (correction 2026-04-26 : PR #465 avait visé `railway.json` déprécié) |
| `railway.json` | Supprimé (orphelin depuis PR #368, source de la confusion PR #465) |
| `packages/api/app/workers/scheduler.py` | Retrait `_scheduled_restart` + job + imports `os`/`signal` |
| `packages/api/tests/workers/test_scheduler.py` | Tests remplacés par garde de non-régression |
| `docs/bugs/bug-server-crashes.md` | Ce document |

---

## Vérification post-merge

- [ ] Déploiement Railway observé : configuration acceptée (pas de config error).
- [ ] Logs startup scheduler : 5 jobs uniquement (`rss_sync`, `daily_top3`, `daily_digest`, `digest_watchdog`, `storage_cleanup`). Le job `scheduled_restart` ne doit PLUS apparaître.
- [ ] Traverse le prochain créneau 09:00 Paris sans SIGTERM : pas de log `scheduled_restart_initiated` attendu, app reste up.
- [ ] 24h sans restart manuel requis.
- [ ] Pool `checked_out` observé si métrique disponible — reste sain. Si signature Sentry `QueuePool limit reached` remonte dans les 48h → rollback git immédiat du retrait de `_scheduled_restart`.

Si d'autres types d'indisponibilités persistent (hors créneaux SIGTERM) → passer à Phase 2 (durcissement pool + décalage top3, ou worker service dédié).

---

## Références

- Code : `packages/api/app/workers/scheduler.py:96-125,192-200`
- Config : `railway.json`
- Origine : `docs/bugs/bug-infinite-load-requests.md` (à vérifier ; pas sur `main` au moment de la rédaction mais référencé dans le code)
- Plan complet agent : `/Users/laurinboujon/.claude/plans/system-instruction-you-are-working-lovely-lake.md`
