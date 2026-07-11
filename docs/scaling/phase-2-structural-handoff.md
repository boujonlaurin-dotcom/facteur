# Hand-off — Phase 2 : premières actions structurelles de scalabilité

> **À copier comme prompt de lancement d'un agent dédié.** Auto-portant : tout le contexte nécessaire est ici ou lié.
> **Prérequis lecture** : [`scaling-investigation-200-users.md`](scaling-investigation-200-users.md) (briefs WP-A→E), [`baseline-2026-06-04.md`](baseline-2026-06-04.md) (chiffres), [`../maintenance/maintenance-observabilite-scaling.md`](../maintenance/maintenance-observabilite-scaling.md) (phase A = instrumentation).

---

## 0. Mission

Mettre en place les **premières actions structurelles à impact** pour rendre la scalabilité de l'app **robuste** vers 200 users (et avec de la marge au-delà). Pas une refonte : **2 à 3 PRs fondatrices, data-gated, sûres et réversibles**, qui suppriment les fragilités identifiées et posent les fondations de capacité. Tu mesures d'abord, tu remédies ensuite, tu re-mesures.

**Cadre mental (ne pas l'oublier)** : la phase 1 a montré qu'à 200 users *mécaniquement presque rien ne casse* — la marge est large (digest ~20 s sur une fenêtre de 45 min, `user_content_status` négligeable, pool jamais saturé en conditions normales). Donc « robuste » ici = **enlever les signaux de fragilité** (idle-in-transaction en prod, process unique, coût Mistral non gouverné, fenêtre RSS au bord) et **établir la fondation capacité**, pas sur-ingénierer pour 10k. Right-size chaque action à l'évidence.

---

## 1. État au démarrage

**Phase 1 (cadrage)** : livrée — baseline réel + 5 work-packages auto-portants. Rappels des **corrections de cadrage** mesurées (lire le §0 du baseline) : 89 users (pas 50) · **278 sources actives** (pas 50, RSS déjà à 5,5×) · `user_content_status` = `O(interactions)` ~3,3k lignes (table « explosive » inexistante) · **serene ~50 %** (pas 10 %) → `mistral-large` sur ~moitié du FR · caps Mistral/Brave **en mémoire, veille seule** → classif+éditorial non gouvernés · digest **~20 s/89 users** (pas le hot spot) · vrai vecteur disque = **`daily_digest` TOAST 126 MB** · signal pool prod = **`IdleInTransactionSessionTimeout`** + N+1 (Sentry projet `python`).

**Phase A (instrumentation, WP-E)** : code écrit et vérifié en local (table `api_usage_events`, recorder best-effort sur les 6 call sites Mistral/Brave, résumé run digest, sonde pool périodique + métrique idle-tx). Migration `au01_api_usage_events` (down_revision `gr02_grille_featured_article`).

> ⚠️ **PRÉCONDITION BLOQUANTE** : à l'écriture de ce hand-off, **`api_usage_events` n'existe PAS dans la base prod** (`ykuadtelnzavrqzbfdve`) → la PR phase A **n'est pas encore mergée/déployée** sur l'env qui sert cette base. **Sans elle, pas de données live pour gouverner WP-A/WP-D.** Donc :

---

## 2. Étape 0 — Faire atterrir la donnée (gate de tout le reste)

1. **Merger + déployer phase A** (PR « Observabilité scaling ») sur l'env cible. Attention au split env (`main` = staging continu, `production` = branche hebdo — cf. mémoire env split) : l'instrumentation doit tourner là où tu veux mesurer. Vérifie que `alembic upgrade head` au boot Railway crée bien `api_usage_events` (le `Dockerfile` rejoue la chaîne).
2. **Laisser collecter** (≥ 48 h idéalement, dont ≥ 1 cycle digest + ≥ 1 weekend si possible) avant de décider.
3. **Vérifier le flux** : `SELECT provider, model, count(*) FROM api_usage_events GROUP BY 1,2;` doit renvoyer des lignes (Mistral 4 call_sites système + veille, Brave). Confirme aussi que `digest_run_summary` apparaît dans les logs et que la sonde pool émet.

> Si pour une raison X phase A ne peut pas être déployée maintenant, tu **retombes sur le baseline read-only** (2026-06-04) + une nouvelle passe `execute_sql` ; mais alors WP-D (coût Mistral réel) reste estimé, pas mesuré — signale-le explicitement.

---

## 3. Étape 1 — Confirmer les goulots structurels avec la donnée

Avant toute remédiation, **chiffre** les 3 hypothèses structurelles avec les sources désormais disponibles. Ne code rien tant que le goulot n'est pas confirmé.

| Hypothèse structurelle | Évidence à produire | Sources |
|------------------------|---------------------|---------|
| **G1 — Connexions DB fragiles** : pool 20 + pooler 60, contention cron↔API, idle-in-tx | Pic `checked_out`/`overflow` (sonde pool phase A) pendant 07:30–08:15 vs reste de journée ; fréquence/volume `IdleInTransactionSessionTimeout` + sessions tuées par le sweeper ; N+1 chauds | sonde pool (logs/Sentry), Sentry projet `python`, `pg_stat_activity` |
| **G2 — Process unique sature** : API + APScheduler + worker classif dans 1 `uvicorn` | Corrélation latence API ↔ fenêtres cron/worker (CPU/pool) ; durée run digest vs charge ; les 2 runs à ~46 min du baseline | Railway métriques, `digest_run_summary`, `digest_generation_state` |
| **G3 — Coût Mistral non gouverné** : classif+éditorial hors cap, serene ~50 % | `api_usage_events` : appels/jour par provider/model/call_site → projeter ×2,25 (200 users) + croissance contenu ; mois où ça croise le plan tarifaire | `api_usage_events` (phase A) |

Annexe rapide (déjà connue, à re-confirmer) : **G4 RSS** 278 sources vs fenêtre 30 min (worst case ~28 min) ; **G5 stockage** `daily_digest` TOAST `O(users×jours)`, `classification_queue` 26 MB d'index, index mort `ix_user_content_status_exclusion`.

---

## 4. Étape 2 — Slate structurel priorisé (livrer 2-3 PRs fondatrices)

Chaque PR = brief autonome. **Ordre recommandé** (mais ré-arbitre selon ce que la donnée montre — la plus forte évidence passe devant). Préférence PO : **PRs cohérentes peu nombreuses**, réutiliser l'existant.

### PR-S1 — Robustesse des connexions DB *(fondation #1, dépend de G1)*
- **But** : garantir que le pool ne s'épuise jamais sous charge cron+API à 200, et éliminer les idle-in-transaction.
- **Actions candidates** (choisir selon évidence, du moins au plus risqué) : (a) **corriger la cause racine des idle-in-tx** (sessions long-vécues / commit manquant sur un chemin worker — le sweeper n'est qu'un pansement) ; (b) right-size `pool_size`/`max_overflow` (`database.py:45-50`) avec marge mesurée ; (c) évaluer le **mode pooler Supabase transaction (PgBouncer)** pour les chemins background afin de ne pas concurrencer le pool requête ; (d) traiter les N+1 chauds.
- **Impact** : élevé, fondamental (toute montée en charge dépend du pool). **Risque** : zone Infra/DB → lire les safety guardrails, tester `/api/health/pool` avant/après, rollback = revert config (pas de DDL si possible).
- **Acceptation** : zéro `IdleInTransactionSessionTimeout` sur 48 h post-deploy ; pic `usage_pct` pool < seuil d'alerte pendant le cron ; marge connexions chiffrée à 200/1k.

### PR-S2 — Découpler le worker/scheduler du process API *(fondation #2, dépend de G2)*
- **But** : sortir APScheduler + worker classification du `uvicorn` qui sert les requêtes (`Procfile` = 1 process aujourd'hui) → supprime la contention CPU/pool requête↔background et permet un scaling indépendant.
- **Actions candidates** : séparer en un **second service Railway** (ou un process worker dédié) ; commencer minimal (déplacer d'abord le worker classification, le plus gourmand `O(articles)`), garder le scheduler digest là où la fenêtre est sûre. Attention idempotence (un seul scheduler actif — pas de double-cron).
- **Impact** : élevé structurellement. **Risque** : Infra (Railway topology, cf. mémoire `project_railway_topology`), déploiement, double-exécution cron. Staging d'abord.
- **Acceptation** : background et API sur des process distincts ; aucune double-génération digest ; latence API décorrélée des fenêtres cron/worker.

### PR-S3 — Gouvernance coût/quota Mistral *(fort impact, dépend de G3 + phase A)*
- **But** : empêcher que ×2,25 users (+ croissance contenu, serene ~50 %) ne fasse exploser silencieusement le coût/quota Mistral (classif+éditorial aujourd'hui **non plafonnés**).
- **Actions candidates** : budget mensuel **persistant** (dérivé de `api_usage_events`, pas un compteur mémoire) + **backpressure** gracieux (dégrader pass 2 good_news avant pass 1, ou throttler) quand on approche le plan ; remplacer les globals `_brave/_mistral_calls_month` (`smart_source_search.py:40-41`) par la source persistée — c'était **explicitement reporté** par la PR phase A.
- **Impact** : élevé sur la robustesse *coût*. **Risque** : changement de comportement (dégradation) → gate par flag, mesurer l'impact qualité.
- **Acceptation** : conso projetée à 200 chiffrée ; backpressure testé ; plus aucun chemin Mistral non compté.

### Fast-follows (si la donnée les priorise, sinon phase 3)
- **G4 RSS headroom** : mesurer la latence réelle/feed ; ajuster `Semaphore(5)`/intervalle/timeout (`sync_service.py`) ou sharder ; health par feed.
- **G5 maîtrise stockage** : trim/compression du jsonb `daily_digest.items` ou raccourcir la rétention refs 90 j ; purge `classification_queue` (lignes `completed`) ; **DROP `ix_user_content_status_exclusion`** (le planner ne l'utilise pas — cf. EXPLAIN baseline §3). Migrations additives/non destructives, 1 head, testées DB vide.

---

## 5. Contraintes non négociables (CLAUDE.md)
- PR **toujours `--base main`** (staging déprécié, hook bloquant). Une story/maintenance doc par PR avant de coder ; **STOP pour GO** sur le plan.
- **Alembic** = seule source du schéma : `--autogenerate`, exactement **1 head**, test `upgrade`+`downgrade` sur **DB vide** (le `Dockerfile` rejoue la chaîne au boot → migration cassée = déploiement planté). Zéro SQL manuel Supabase.
- Zones **Auth/Router/DB/Infra** → lire les safety guardrails **avant** modif. PR-S1/S2 touchent DB/Infra : prudence maximale, staging d'abord, rollback prêt.
- Python 3.12, types natifs (`list[]`/`X | None`), pas d'em-dash dans la copy user-facing.
- Conclure chaque PR par **`/go`** (VERIFY → simplify → PR vers `main`, STOP à « PR #XX prête »). Pas de `--no-verify`, pas de force-push sur main.
- **Une seule action structurelle par PR**, mesurée isolément ; re-mesurer après deploy avant d'enchaîner la suivante.

## 6. Definition of done (phase 2)
- [ ] Phase A déployée, `api_usage_events` alimentée, données minées (§2-3).
- [ ] G1/G2/G3 confirmés ou infirmés avec chiffres (pas d'action sur une hypothèse non confirmée).
- [ ] 2-3 PRs structurelles livrées, chacune data-gated, sûre, réversible, re-mesurée post-deploy.
- [ ] Baseline mis à jour (`baseline-<date>.md`) montrant la tendance avant/après.
- [ ] Restitution PO : ce qui a été rendu robuste, marge gagnée à 200/1k, et ce qui reste pour phase 3.

## 7. Références
Baseline · Master investigation (WP-A→E) · Maintenance observabilité (phase A) · Mémoires : env split staging/prod, Railway topology, backend test DB local, CI backend-only.
