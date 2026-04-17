# CTO — Journal d'arbitrage 2026-04-17

> Journal traçable des décisions CTO prises aujourd'hui. Un bullet = une
> décision, ancrée sur un artefact. Les arbitrages détaillés sont dans les
> 3 livrables référencés.

## Livrables (relire dans cet ordre)

1. `.context/perf-watch/2026-04-17-cto-h1-quickwins.md` — tickets infra J+1.
2. `.context/perf-watch/2026-04-17-cto-h2-pool.md` — tickets pool DB J+7 + go/no-go sunset.
3. `.context/perf-watch/2026-04-17-cto-h3-cpo-note.md` — note CPO (tradeoffs).

## Décisions actées

- **Rapport perf-watch 2026-04-17 absent** du filesystem. Point de départ du
  handoff manquant. Cause confirmée : `.claude-hooks/session-start.sh:22`
  imprime `[session-start] railway installé.` dès que `curl` réussit,
  indépendamment du fait que `railway` atterrisse dans `$PATH`. Testé live :
  `which railway` → vide ; `which sentry-cli` → vide.
- **Sortie du deadlock "pas de 24h clean"** : on arrête de dépendre du
  trafic réel pour valider les fixes pool. Ticket T2-1 pose un test de
  charge synthétique k6 reproductible comme gate-keeper de PR backend.
- **Pool size inchangé** (guardrail perf-watch §0 respecté). Aucun changement
  `pool_size`/`max_overflow`/`pool_timeout`/`pool_recycle` n'est recommandé
  ni dans H1 ni dans H2.
- **`_scheduled_restart` maintenu** tant que N (jours consécutifs sans
  `QueuePool limit` ni `PendingRollbackError`) < 7. Compteur démarre au plus
  tôt 2026-04-17 00:00 UTC si 24h post-R4 propres (à confirmer par
  l'agent perf-watch, prérequis : H1 complété).
- **BackgroundTasks onboarding validé** tactiquement (PR #422, `0d318d6`).
  Seuil de migration vers queue dédiée formalisé en T2-4 : 20 onboardings/h
  soutenu sur 1h, OU > 50 rate-limits/jour, OU pertes > 5/restart.
- **Priorité CPO** : un endpoint `/api/bootstrap` pour sortir du pattern
  "6 requêtes parallèles à l'ouverture web". C'est l'ajustement produit qui
  a le meilleur ROI scalabilité des 4 tradeoffs analysés (H3 Tradeoff 1).

## Hypothèses à valider (taggées, non actées)

- **[à valider]** R4 (PR #417, `/api/feed/` 3→2 sessions) suffit à tenir
  la charge actuelle. **Expérience** : T2-1 (load test k6) contre staging
  R4. **Signal pass** : p95 < 5s, 0 `QueuePool limit`, pool usage < 70%.
- **[à valider]** Le burst web est le facteur limitant résiduel (vs un site
  code encore non identifié). **Expérience** : 24h de snapshots
  `/api/health/pool` + corrélation avec les heures de pic d'ouverture app
  web (à voir dans Amplitude/analytics côté produit si dispo).
- **[à valider]** Les pertes BackgroundTasks au `_scheduled_restart` sont
  effectivement rares. **Expérience** : compter les `onboarding_saved`
  **sans** `digest_background_regen_completed` associé dans les 5 min
  suivantes, sur 7 jours. Alimente T2-4.

## Ce que je ne fais PAS (explicite)

- Pas de modification de code applicatif dans cette session.
- Pas de `git commit` hors `.context/perf-watch/`.
- Pas de PR créée.
- Pas de retrait `_scheduled_restart`.
- Pas de changement pool.
- Pas de spécification d'implémentation détaillée sur H3 options (c'est au
  CPO + dev lead de trancher, je propose).

## Prochaine décision attendue

- **De Laurin** : approbation des 4 quickwins H1 pour dispatch à un subagent
  infra dès ce matin (coût estimé ≤ ½ journée).
- **Du CPO** : go/no-go sur endpoint `/api/bootstrap` (Tradeoff 1) et sur la
  politique retry mobile (Tradeoff 2). Les deux autres tradeoffs ne
  nécessitent pas de décision produit immédiate.

## Références SHA traçables (2026-04-17)

- Branche courante : `claude/cto-backlog-planning-aVTiw` (cette session).
- Tête `main` au moment de l'arbitrage : `b307995` (fix feed pull-to-refresh,
  PR #426).
- Derniers rounds pool : `cf882aa` (R1) → `e353ec7` (R2) → `0a7aa27` (R3) →
  `cabc627` (R4).
- Mitigation active : `_scheduled_restart` ajouté par `b50869d` (PR #401,
  2026-04-12), toujours actif dans `scheduler.py:192-200`.
