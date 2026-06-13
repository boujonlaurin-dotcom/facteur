# Investigation scaling — passage 50 → 200 utilisateurs

> **Phase 1 (cadrage)** — squelette d'investigation + hand-off briefs exploitables.
> Statut : **read-only**, aucune modif code / config / migration. Pas de PR à ce stade.
> Snapshot données : [`baseline-2026-06-04.md`](baseline-2026-06-04.md).
> Horizon principal : **200 users (×4)**. Points de rupture notés au-delà (1k / 10k) par composant.

---

## 1. Contexte

L'app (Flutter + FastAPI + PostgreSQL/Supabase + Railway) vise un passage **50 → 200 users** (×4). État mesuré au 2026-06-04 : **89 users** en DB (déjà au-delà des « 50 » supposés), **DAU 2–7**, faible concurrence, **aucune saturation signalée**. Aucun capacity planning n'existait.

Deux axes :
1. **Capacité infra / database** à 200 users.
2. **Distinguer ce qui scale de ce qui scale moins** — notamment ingestion RSS et classification.

Ce document est **auto-portant par track** : un agent dédié lit sa section (§4) et l'exécute sans relire tout le code. Chaque brief = `Question / Hypothèse / Outils / Mesures / Point de rupture / Sortie attendue / Critères d'acceptation`.

> ⚠️ **Lire d'abord le §0 du baseline** ([écarts vs hypothèses](baseline-2026-06-04.md#0-tldr--écarts-vs-hypothèses-du-plan-de-cadrage)) : 7 hypothèses du cadrage initial ont été infirmées par les mesures. Les briefs ci-dessous intègrent ces corrections.

---

## 2. Synthèse « scale bien / scale moins » (ancrée code)

### ✅ Ce qui scale bien — découplé du nombre d'users

- **Ingestion RSS** — `O(sources)`, pas `O(users)`. `Semaphore(5)` (`sync_service.py:111`), intervalle 30 min (`RSS_SYNC_INTERVAL_MINUTES`, `config.py:76`), 50 entries max/feed (`sync_service.py:200`), timeout 30 s/feed (`sync_service.py:49`). **278 sources actives** aujourd'hui (≠ 50 supposées). ×4 users n'y touche pas — **mais** la marge sur la fenêtre 30 min dépend du nombre de sources (voir WP-C, point de rupture déjà proche).
- **Classification** — `O(articles)`, pas `O(users)`. `classification_worker.py:32` (batch 5), file `classification_queue` en `SELECT … FOR UPDATE SKIP LOCKED` (`classification_queue_service.py:63`), 2 passes Mistral : `mistral-small` topics (`classification_service.py`) puis `mistral-large` good_news (`good_news_classifier.py:29`) déclenché sur serene + source FR + non-anglais (`classification_worker.py:265-274`). **Backlog actuel = 0**, le worker suit l'ingestion (~2 000/jour). Plafonné par le débit worker et le quota Mistral (voir WP-C/D).
- **Génération digest (couche scoring)** — mesurée **~0.33 s/user**, run complet **~20 s** pour 89 users. L'éditorial LLM est **global/caché `O(1)/jour`** (le coût par user est du scoring, pas un appel LLM). ~99 % de marge sur la fenêtre 45 min.

### ⚠️ Ce qui scale moins — couplé au nombre d'users `O(users)`

- **Scoring + matching éditorial par user** — `O(users)`, dans `digest_generation_job.py` (batch 100 / concurrence 10, `digest_generation_job.py:68-69`) × 2 variantes (`digest_generation_job.py:700`, normal + serein). Linéaire et rapide aujourd'hui ; le risque n'est pas la durée mais la **contention pool** pendant le run (voir WP-A/B).
- **`daily_digest` (stockage)** — `O(users × jours × rétention)`. **126 MB de TOAST** (jsonb `items`) pour 9.5k lignes (~13.5 KB/digest). **C'est le vrai vecteur de croissance disque** (et non `user_content_status`, cf. correction baseline #3/#7). Index `uq_daily_digest_user_date_serene` (user_id, target_date, is_serene).
- **`user_content_status`** — `O(interactions user)`, **pas** un produit cartésien users×articles. 3 261 lignes (~37/user) aujourd'hui ; requête d'exclusion = anti-join `NOT EXISTS` (`digest_selector.py:811-821`). À 200 users ≈ **7–15k lignes** (négligeable), pas 2M.
- **Quotas API externes (veille)** — `O(actions user)`. Brave + Mistral fallback dans `smart_source_search.py`, plafonds `brave_monthly_cap`/`mistral_monthly_cap` (`config.py:119-120`).

### 🧱 Plafonds infra structurels

- **Process Railway unique** (`Procfile` = 1 `uvicorn`) : API + APScheduler + worker classification **dans le même process**. Pas de worker séparé, pas de scaling horizontal de la cron.
- **Pool DB** : 10 + 10 overflow = **20 max** (`database.py:45-50`), pooler Supabase 60 partagés (`database.py:64`). Point chaud = cron digest (concurrence 10) en contention avec API + worker classification + RSS sync sur le même pool. **Signal prod réel** : `IdleInTransactionSessionTimeout` (Sentry PYTHON-57/58) → transactions ouvertes monopolisant des slots.
- **Caps API non fiables** : compteurs `_brave_calls_month`/`_mistral_calls_month` en **mémoire process** (`smart_source_search.py:40-41`), remis à 0 à chaque redéploiement, et **n'encadrant que la veille** — classification + éditorial Mistral **non plafonnés, non métrés**.
- **Rétention** : articles 20 j (`RSS_RETENTION_DAYS`, `config.py:80`), cleanup cron 03:00 Paris (`scheduler.py:216-218`), protection refs digest 90 j (`storage_cleanup.py:23`).

---

## 3. Table baseline (synthèse — détail dans [baseline-2026-06-04.md](baseline-2026-06-04.md))

| Dimension | @89 users (mesuré) | Projection @200 (×2.25) | Marge / plafond |
|-----------|--------------------|--------------------------|-----------------|
| Users DB | 89 | 200 | — |
| Sources actives | 278 | indépendant des users | fenêtre RSS 30 min (WP-C) |
| `contents` | 54 590 lignes / 339 MB | ~idem (O(sources×temps)) | rétention 20 j |
| `user_content_status` | 3 261 / 1.8 MB | ~7–15k / ~4 MB | négligeable |
| `daily_digest` | 9 573 / **133 MB** (126 MB TOAST) | ~21k / ~300 MB+ | **vecteur stockage** |
| `classification_queue` | 52 839 (0 backlog) / 32 MB | idem (O(articles)) | débit worker / cap Mistral |
| Run digest | ~20 s (job 0.33 s) | ~45 s | fenêtre 45 min → ~98 % marge |
| Exclusion EXPLAIN (user lourd) | 347 ms / cache | linéaire/user | planner ignore l'index dédié |
| Pool DB | 20 (+60 pooler) | inchangé | contention cron (WP-A) |
| Brave (veille) | ~96/30 j | ∝ users actifs veille | cap 1800 (5 % utilisé) |
| Mistral classif | ~3 000/jour (non métré) | ∝ articles, pas users | **non plafonné** (WP-D) |

---

## 4. Tracks d'investigation (work-packages auto-portants)

### WP-A — Capacité DB & connexions  *(axe 1)*

- **Question** : le pool (20 + 60 pooler) et la DB tiennent-ils 200 users / >5 concurrents, en particulier pendant le cron digest ?
- **Hypothèse** : la concurrence brute est OK à ×4 ; le risque réel = **contention pool pendant le run digest** (concurrence 10) cumulée à API + worker + RSS sync, aggravée par des **transactions idle** (`IdleInTransactionSessionTimeout` déjà observé en prod).
- **Outils** : Supabase MCP `execute_sql` (`claude_analytics_ro`) ; `/api/health/pool` (`main.py:613-648`) ; `database.py:45-64` ; métriques Railway ; Sentry projet `python` (filtrer `IdleInTransaction`, `N+1`).
- **Mesures** : pic de connexions (`pg_stat_activity` par `state`), connexions consommées par le run digest, `pg_stat_activity` `idle in transaction` pendant 07:30–08:15, EXPLAIN d'exclusion (déjà fait : 347 ms cas lourd, **planner ignore `ix_user_content_status_exclusion`**), revue des N+1 Sentry.
- **Point de rupture** : (a) à quel nombre d'users le run cron (concurrence 10 × {normal,serein}) sature les 20 slots + déborde sur le pooler 60 ; (b) à quel volume `user_content_status` l'anti-join dégrade (aujourd'hui 347 ms tout en cache — tester à froid) ; (c) impact des transactions idle sur la disponibilité du pool. Chiffrer @200 / 1k / 10k.
- **Sortie attendue** : table de marge connexions (actuel → 200 → 1k), palier de bascule (worker séparé / pooler dédié / `pool_size`↑), recommandation sur l'index d'exclusion mort.
- **Acceptation** : marge pool chiffrée à 200/1k ; cause des `IdleInTransactionSessionTimeout` identifiée ; verdict go/no-go sur `ix_user_content_status_exclusion`.

### WP-B — Fenêtre de génération du digest  *(axe 2, supposé hot spot)*

- **Question** : la fenêtre 07:30→08:15 (45 min) tient-elle à ×4 et au-delà ?
- **Hypothèse (corrigée)** : **non bloquant à 200** — run mesuré ~20 s pour 89 users, job/user 0.33 s, éditorial LLM global/caché. Le vrai sujet = comprendre les **2 jours à ~46 min** (06-02, 05-28) et les **retries systématiques** (`max_attempts` 8–12/jour).
- **Outils** : `digest_generation_state` (timing par job) ; logs Railway (`digest_generation`) ; structlog ; Sentry ; `digest_generation_job.py`, `digest_selector.py`, watchdog `scheduler.py:98,206-207` (seuil couverture 0.90).
- **Mesures** : durée run (fait : ~16–20 s nominal, ~2 750 s les jours anormaux), temps scoring/user (0.33 s avg / ~1 s p95), % couverture watchdog, confirmer que l'éditorial LLM est bien `O(1)/jour` (pas par user), cause des retries.
- **Point de rupture** : extrapolation linéaire `O(users)` → à 0.33 s/job × 2 variantes / concurrence 10, **10k users ≈ 11 min** ⇒ la fenêtre tient jusqu'à ~10k côté calcul. Identifier ce qui casse **avant** : contention pool (WP-A) ou un appel LLM caché par user.
- **Sortie attendue** : durée extrapolée 200/1k/10k + marge vs fenêtre ; explication des runs à 46 min ; recommandation sur les retries.
- **Acceptation** : durée @200/1k/10k chiffrée ; mécanisme des 2 runs lents élucidé ; confirmation éditorial global vs per-user.

### WP-C — RSS + classification  *(axe 2, « ce qui scale moins » explicite)*

- **Question** : RSS sync (`O(sources)`) et classification (`O(articles)`, cap Mistral) tiennent-ils, sachant que **×4 users n'y touche presque pas** ?
- **Hypothèse** : découplé des users ; le risque vient de la **croissance des sources/contenu**, pas des users. La marge RSS est **déjà étroite** : 278 sources / `Semaphore(5)`, worst case 30 s/feed ⇒ `278/5 × 30 ≈ 28 min` vs fenêtre 30 min.
- **Outils** : `execute_sql` ; `sync_service.py:49,111,200` ; `classification_worker.py:32,265-274` ; `classification_queue_service.py:63` ; `good_news_classifier.py`.
- **Mesures** (baseline fait) : 278 sources actives ; ~2 000 articles/jour ingérés & classifiés ; backlog `classification_queue` = 0 ; part serene ~50 % (≠ 10 % supposé) → pass 2 `mistral-large` fire sur ~moitié du FR.
- **Point de rupture** : (a) RSS — nombre de sources où `Semaphore(5)` + fenêtre 30 min ne suit plus (estimé **~proche du palier actuel** en worst case lent ; mesurer la latence réelle/feed) ; (b) classification — volume articles/jour où le débit worker (batch 5, ~10 s/batch) accumule un backlog permanent ou crève le cap Mistral.
- **Sortie attendue** : table de caractérisation `O()` RSS vs classif + runway quota ; recommandation `Semaphore`/intervalle si sources↑.
- **Acceptation** : palier sources (RSS) et palier articles/jour (classif) chiffrés ; latence réelle/feed mesurée pour valider la marge 30 min.

### WP-D — Quotas & coûts API externes

- **Question** : quel plafond API tombe en premier en montant à 200 users + croissance contenu ?
- **Hypothèse** : Brave (veille) a une marge énorme (~5 % utilisé) ; le **risque réel = Mistral classification/éditorial, qui n'est ni plafonné ni mesuré** dans le code.
- **Outils** : `config.py:119-120` ; `smart_source_search.py:40-41,459,537` ; absence de table de tracking (confirmer dans `app_config` + schéma) ; facturation Mistral/Brave (hors DB).
- **Mesures** : agréger tous les consommateurs — classif `O(content)` (~2 000 small + ~1 000 large/jour), éditorial `O(1)/jour`, veille `O(actions)` (~96 Brave/30 j). Projeter à 200 users + croissance contenu.
- **Point de rupture** : (a) mois où l'usage projeté croise les caps 2000 (Mistral) / 1800 (Brave) — **sachant que ces caps n'encadrent que la veille** ; (b) consommation Mistral classification réelle vs plan tarifaire (le vrai risque, non gouverné par `mistral_monthly_cap`).
- **Sortie attendue** : modèle quota/coût par consommateur + 1er plafond atteint ; recommandation d'un tracking persistant (cf. WP-E).
- **Acceptation** : conso Mistral totale (classif+éditorial+veille) chiffrée et projetée ; 1er plafond identifié ; gap « caps en mémoire / veille seule » documenté.

### WP-E — Observabilité & instrumentation manquante  *(enabler)*

- **Question** : que faut-il instrumenter au minimum pour rendre A–D mesurables et détecter les ruptures **avant** l'incident ?
- **Trous identifiés en phase 1** : pas de quantiles de latence par endpoint ; pas de métrique de durée digest exposée (reconstruite via `digest_generation_state`) ; **pas de tracking d'usage Mistral/Brave persistant** ; caps en mémoire non fiables (reset au redéploiement) ; pas d'alerte saturation pool ; pas de health des feeds RSS ; `ix_user_content_status_exclusion` non utilisé par le planner.
- **Outils / existant** : PostHog (events `app_open`, `feed_load_timing`, `digest_opened`…) ; Sentry (traces 10 %, déjà : `IdleInTransaction`, `N+1`) ; structlog ; `/api/health/pool`.
- **Sortie attendue** : liste priorisée de métriques à ajouter + emplacement + ce qui est **déjà couvert** par PostHog/Sentry/structlog. Minimum vital : (1) compteur Mistral/Brave **persisté** (table) ; (2) durée+couverture digest en métrique ; (3) alerte `pool usage_pct` + `idle in transaction` ; (4) health/latence feeds RSS ; (5) latence p95 exclusion à froid.
- **Acceptation** : chaque métrique mappée à un besoin A–D ; distinction clair « déjà couvert » vs « à ajouter » ; quick-wins (ex. table tracking Mistral) identifiés.

---

## 5. Hors scope (phase 1)
- Analyse chiffrée approfondie par track + recommandations de remédiation (= phases suivantes, via ces briefs).
- Tout changement de code, migration, ou config infra.

## 6. Vérification de la phase 1
- [x] 5 tracks auto-portants (Q / hypothèse / outils / mesures / point de rupture / sortie / acceptation).
- [x] Baseline avec chiffres réels (counts, tailles heap/TOAST/index, EXPLAIN, timing digest, conso Brave, serene %) — pas de placeholders.
- [x] Synthèse « scale bien / scale moins » ancrée sur file_path réels.
- [x] Points de rupture 200/1k/10k chiffrés ou marqués « à mesurer ».
- [x] Aucune modif code/config/migration — investigation 100 % read-only.
