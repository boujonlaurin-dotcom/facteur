# Hand-off — Phase 3 : Launch readiness (release stores ~J-14)

> **À copier comme prompt de lancement d'un agent dédié.** Auto-portant.
> **Prérequis lecture** : [`scaling-investigation-200-users.md`](scaling-investigation-200-users.md), [`baseline-2026-06-04.md`](baseline-2026-06-04.md), [`phase-2-structural-handoff.md`](phase-2-structural-handoff.md), [`../maintenance/maintenance-observabilite-scaling.md`](../maintenance/maintenance-observabilite-scaling.md).

---

## 0. Mission

L'app **sort sur les stores dans ~2 semaines**. Objectif : garantir que **tout fonctionne parfaitement le jour J et les jours suivants**, sous la vague d'utilisateurs du lancement, **sans faire exploser les coûts (Mistral en premier lieu)**.

Ce n'est plus de l'investigation ni du structurel : c'est de la **préparation opérationnelle de lancement** (load validation, plafonds de coût, runbook, kill-switches, game-day). Programme **time-boxé J-14 → J-0 → J+7**. Tu valides par la mesure et la répétition, pas par l'extrapolation.

---

## 1. État au démarrage (mesuré le 2026-06-26)

Phases 1 (cadrage), A (instrumentation) et 2 (structurel : robustesse pool, découplage worker, gouvernance coût Mistral) **livrées et en prod depuis ~2 semaines**. Données live disponibles dans `api_usage_events`.

- **107 users** actifs (89 il y a 3 semaines) · **309 sources actives** (278) · **~2 400 articles/jour**.
- `api_usage_events` alimentée (13 j de données réelles) → la gouvernance coût est mesurable.

---

## 2. ⭐ La vérité coût Mistral (donnée réelle — à mettre au centre)

> **Mesure 13 jours (2026-06-13 → 06-26), 107 users.** Le coût Mistral est **`O(contenu)`, PAS `O(users)`.**

| call_site | modèle | ~appels/jour | couplage |
|-----------|--------|-------------:|----------|
| `classification_pass1` | mistral-small | **~2 250** | `O(articles)` |
| `good_news_pass2` | **mistral-large** | **~315** | `O(articles serene)` (~50 % du FR) |
| `editorial` | mistral-large | ~71 | `O(1)/jour` (global) |
| `editorial` | mistral-small | ~58 | `O(1)/jour` |
| `editorial` | mistral-medium | ~37 (arrêté après 06-21) | `O(1)/jour` |
| `veille_suggester` | mistral-medium | ~0–4 | `O(actions user)` |
| `smart_search_brave` (Brave) | — | ~1 | `O(actions user)` |

**Total ≈ 2 637 appels/jour (~79 000/mois), dont ~372 large/jour.**

**Conséquences directes pour le lancement (à exploiter dans le plan) :**
1. **Une vague d'users ne fait PAS exploser le coût Mistral.** Sur la fenêtre, users **+20 % (89→107)** mais Mistral **plat** (~2 637/j) → le coût suit le **volume de contenu**, pas le nombre d'users. Les call_sites couplés aux users (`veille`, `smart_search`) sont **négligeables** (~1–4/jour).
2. **Le vrai levier coût au lancement = croissance contenu/sources** (si les nouveaux users ajoutent des sources → plus d'articles → plus de classif) **+ le pass `good_news` large** (~50 % du FR). C'est là qu'il faut un plafond et un frein.
3. **Gaspillage identifié** : `editorial` mistral-**large** a **28 % d'erreurs (267/942)** → coût brûlé + qualité digest dégradée. À corriger avant J.
4. **Trou de données** : `api_usage_events` compte les **appels**, pas les **tokens** → le **coût € exact** nécessite le dashboard de facturation Mistral. Le croiser est un prérequis du modèle de coût (LR-1).
5. **Brave** : ~1 appel/jour, marge totale, non sujet.

---

## 3. Work-packages launch readiness

> Préférence PO : **PRs cohérentes peu nombreuses**, réutiliser l'existant (instrumentation phase A, sonde pool, kill-switch `usage_tracking_enabled`). Chaque WP = brief autonome. `/go` pour conclure toute PR, `--base main`.

### LR-1 — Plafond de coût & protection anti-emballement (Mistral) *(priorité #1, c'est l'angoisse PO)*
- **But** : rendre **impossible** un dépassement de budget Mistral au lancement, avec **dégradation gracieuse** plutôt que panne ou facture.
- **Actions** : (a) **vérifier que la gouvernance coût de phase 2 (PR-S3) plafonne réellement** classif+éditorial (pas seulement la veille) ; (b) **plafond mensuel € dur** dérivé de `api_usage_events` × tarif Mistral (croiser le dashboard facturation pour le €/appel par modèle) ; (c) **awareness du rate-limit *par minute*** Mistral, pas que mensuel (un burst de classif peut throttler) ; (d) **ordre de dégradation** défini et testé : couper `good_news_pass2` (large) puis `editorial` **avant** `classification_pass1` ; **ne JAMAIS** faire échouer l'onboarding ni la génération digest ; (e) **corriger les 28 % d'erreurs `editorial`-large** (retries/backoff/timeout) ; (f) **frein sur l'onboarding de sources user** pour borner la croissance contenu (le vrai levier coût).
- **Acceptation** : simuler l'atteinte du cap → l'app **dégrade, ne casse pas** ; coût projeté du mois de lancement < budget PO ; erreurs editorial < 5 %.

### LR-2 — Validation de charge (valider, ne plus extrapoler)
- **But** : prouver que les correctifs structurels de phase 2 (pool, découplage worker) **tiennent réellement** la concurrence du lancement — phase 1 n'a fait qu'extrapoler.
- **Actions** : test de charge synthétique sur **staging** (= `main`, cf. env split) aux concurrences cibles J-day, sur les **vrais hot paths du lancement** : (1) **flood onboarding** (signup → 1er digest → smart-source-search) ; (2) **cold-open** de l'app (cf. correctif +10 s déjà livré — vérifier qu'il tient sous charge) ; (3) **tempête de refresh JWT** ; (4) `feed`/`digest`/`perspectives` en concurrence ; (5) **cron digest** pendant un pic de trafic API (contention pool).
- **Acceptation** : latence pNN < cible à Nx concurrence ; **pool jamais saturé**, **zéro `IdleInTransactionSessionTimeout`** sous charge ; le cron digest ne dégrade pas l'API.

### LR-3 — Pré-provisionnement quotas & capacité externe
- **But** : aucune limite externe atteinte par surprise le jour J.
- **Actions** : confirmer/relever avant J-0 — **plan Mistral** (quota mensuel **+ rate/min**), **pooler Supabase** (limite connexions, mode transaction), **Railway** (taille instance, scaling du/des service(s) après découplage worker, cf. topologie prod = service WEB `facteur-production`), **quota d'events Sentry/PostHog** (la vague va multiplier les events → risque de drop/coût), **token GitHub backend** (l'`/app/update` renvoie 502 si le token est expiré → MAJ Android invisibles : **rotation avant lancement**).
- **Acceptation** : chaque dépendance externe a une marge chiffrée > pic projeté ; secrets/quotas validés par healthcheck.

### LR-4 — Runbook jour J & war-room
- **But** : exécution sereine le jour J avec leviers prêts.
- **Actions** : (a) **dashboards à surveiller** : coût/volume Mistral (`api_usage_events`), pool `usage_pct`, couverture digest (`digest_run_summary`), taux d'erreur (Sentry), DAU/onboarding (PostHog) ; (b) **inventaire des kill-switches** et leur effet : `usage_tracking_enabled`, fallback Mistral smart-search, throttle classification, désactivation editorial, nudges (`app_config.nudges_enabled`) ; (c) **leviers de rollback** (revert config sans redeploy schéma, `alembic downgrade`, weekly-release prod) ; (d) **gate Go/No-Go** (§5) ; (e) **coordination client/stores** : version gate (`app_config` iOS + In-App Updates Android), timing de publication store, capacité à pousser un kill-switch **sans** release binaire.
- **Acceptation** : runbook 1 page, chaque alerte → action + owner ; tous les kill-switches testés en staging.

### LR-5 — Modes de défaillance & game-day
- **But** : connaître et répéter le comportement sous panne **avant** le jour J.
- **Actions** : **répétition game-day en staging** des scénarios : Mistral rate-limited / cap budget atteint en plein lancement ; pool DB saturé ; un feed RSS qui flood ; pic d'onboarding x10. Vérifier : onboarding **ne hard-fail jamais** ; digest **génère sans editorial LLM** (fallback scoring) ; messages user gracieux (pas d'em-dash dans la copy user-facing).
- **Acceptation** : chaque scénario a un comportement observé documenté + dégradation gracieuse confirmée.

### LR-6 — Veille J+1 → J+7 (charge soutenue, pas que le pic)
- **But** : tenir dans la durée, pas seulement au pic d'install.
- **Actions** : suivre la **vague de rétention** (digest quotidien à user-count croissant), la **tendance coût** Mistral (croît-elle avec le contenu ?), la **croissance stockage** (`daily_digest` TOAST `O(users×jours)`), le **backlog** `classification_queue`. Mettre à jour `baseline-<date>.md` (avant/après lancement).
- **Acceptation** : aucune dérive non détectée sur 7 j ; coût et latence dans les cibles.

---

## 4. Timeline indicative

| Fenêtre | Focus |
|---------|-------|
| **J-14 → J-9** | LR-1 (plafond coût + fix editorial 28 %), LR-3 (quotas externes) |
| **J-9 → J-5** | LR-2 (load test staging), LR-5 (game-day) |
| **J-5 → J-2** | LR-4 (runbook + kill-switches testés), gel des changements risqués |
| **J-2 → J-0** | Gate Go/No-Go, rotation secrets, version gate prêt |
| **J-0 → J+7** | War-room puis LR-6 (veille soutenue) |

## 5. Gate Go / No-Go (jour J)
- [ ] Plafond coût Mistral **dur + dégradation gracieuse** prouvés (LR-1) ; erreurs editorial < 5 %.
- [ ] Load test passé aux concurrences cibles ; pool stable, zéro idle-in-tx (LR-2).
- [ ] Quotas externes (Mistral rate/min + mensuel, Supabase, Railway, Sentry/PostHog, token GitHub) avec marge (LR-3).
- [ ] Runbook + kill-switches testés ; rollback prêt ; version gate opérationnel (LR-4).
- [ ] Game-day rejoué : onboarding/digest dégradent sans casser (LR-5).
- [ ] Baseline pré-lancement figée pour comparaison.

## 6. Contraintes (CLAUDE.md) & philosophie
- **`--base main`** toujours, Alembic 1-head + test DB vide, safety guardrails (DB/Infra). `/go` pour conclure.
- **Réversibilité d'abord** : tout levier de lancement doit s'activer **sans redeploy binaire** (kill-switch config / `app_config`), car un binaire store met des jours à se propager.
- **Right-size** : viser la robustesse au pic de lancement réaliste, pas 10k. Mesurer, ne pas deviner.

## 7. Références & mémoires utiles
Baseline · Master investigation · Phase 2 structurel · Mémoires : cold-open +10 s, token GitHub MAJ Android (502), version gate iOS/Android, Railway topology (prod = WEB `facteur-production`), env split staging/prod, digest quasi-global cluster-gated, CI backend-only, test DB local, pas d'em-dash copy user.
