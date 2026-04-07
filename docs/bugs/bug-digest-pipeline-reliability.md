# Bug: Digest Pipeline — Reliability & Performance

**Type:** Bug
**Branche:** `boujonlaurin-dotcom/fix-digest-post-e2e`
**Date:** 2026-04-06

---

## Symptômes

1. **Chargement lent (20-30s)** à la première connexion pour tous les utilisateurs — la pipeline éditoriale (6+ appels LLM) tourne on-demand au lieu d'être pré-générée.
2. **Jours sautés** — certains matins, aucun digest n'est généré, sans erreur visible.

## Causes racines

### C1 — APScheduler in-process, fragile sur Railway
Le cron 8h00 tourne dans le même process que l'API (`scheduler.py`). Chaque redémarrage Railway (deploy, memory pressure, scaling) reset le scheduler. `misfire_grace_time=3600` ne couvre qu'1h ; si le container est down de 8h00 à 9h01, le job est silencieusement droppé.

### C2 — Catch-up startup trop grossier
`main.py:181-186` vérifie si **un seul** digest existe pour aujourd'hui (`LIMIT 1`). Si la génération précédente a crashé après 1 user sur 50, le catch-up considère que tout est fait.

### C3 — Aucun retry / watchdog
Si `run_digest_generation()` échoue (timeout LLM, erreur DB), rien ne relance. Le digest du jour est perdu.

## Plan technique

### A. Scheduler — génération plus tôt + watchdog
- **Fichier:** `packages/api/app/workers/scheduler.py`
- Avancer le cron digest de 8h00 → **6h00**
- Ajouter un **job watchdog à 7h30** qui vérifie la couverture et relance si < 90%
- Augmenter `misfire_grace_time` de 3600 → **14400** (4h)

### B. Fix catch-up startup
- **Fichier:** `packages/api/app/main.py`
- Compter le ratio users actifs / digests générés
- Relancer si couverture < 90%

### C. Retry dans le job de génération
- **Fichier:** `packages/api/app/jobs/digest_generation_job.py`
- Retry des users en échec (max 2 tentatives, backoff exponentiel)

## Fichiers modifiés

- [x] `packages/api/app/workers/scheduler.py` — cron 6h, watchdog 7h30, misfire 4h
- [x] `packages/api/app/main.py` — catch-up coverage-based (< 90%)
- [x] `packages/api/app/jobs/digest_generation_job.py` — retry DB-based (2 tentatives, backoff)
- [x] `packages/api/tests/workers/test_scheduler.py` — tests mis à jour (6h + watchdog)

## Tests

- [x] Syntax check — tous les fichiers OK
- [ ] `pytest -v` — suite complète backend (pas de venv local, à valider en CI)
- [ ] Vérifier les logs structurés (watchdog, retry, catch-up)
