# Maintenance — Gouvernance coût Mistral/Brave (scaling phase 2, PR-S3)

## Contexte
Phase 2 scaling (cf. `docs/scaling/scaling-investigation-200-users.md`, G3). À 89 users, serene ~50 % → `mistral-large` sur la moitié du FR ; les caps Mistral/Brave n'existaient qu'en **mémoire** (`smart_source_search._brave_calls_month`/`_mistral_calls_month`) et **uniquement pour la veille**. Classification + éditorial = non plafonnés.

## Bug corrigé (cause de fond)
Les compteurs en mémoire sont remis à zéro à **chaque restart de process** → chaque déploiement Railway les efface. Avec des déploiements fréquents, les caps mensuels Brave (1800) / Mistral search (2000) n'étaient **en pratique jamais atteints**. Reporté explicitement par la PR phase A (#818).

## Changements (data-gated, sûrs, réversibles)
1. **Budget persistant** : `app/services/observability/cost_budget.py` lit la conso du mois calendaire courant depuis `api_usage_events` (déjà alimentée par `usage_recorder` sur les 6 call sites), avec cache process-local TTL `cost_budget_cache_ttl_s` (120 s) pour ne pas requêter à chaque recherche. Survit aux restarts.
2. **Remplacement des compteurs mémoire** : `smart_source_search` utilise `is_over_cap(provider, cap, call_site=...)` au lieu des globals supprimés. Aucun incrément manuel : enregistrer l'événement (via `track_api_call`, déjà en place) **est** l'incrément. Le cap est **scopé sur le call site** (`smart_search_brave` / `smart_search_mistral`) — préserve la sémantique d'origine : le provider `mistral` couvre aussi classif/éditorial/veille (volume bien plus élevé), qui ne doivent pas consommer le budget du fallback recherche.
3. **Projection G3 automatisée** : job scheduler quotidien (05:00 Paris) `log_budget_projection` → log `cost_budget_projection` = conso réelle par provider/call_site + projection ×2.25 (89→200 users). Évidence G3 sans requête manuelle.

## Hors périmètre (follow-up flag-gated, dépend de la donnée)
Le **plafonnement effectif des chemins système** (classification pass1, good_news pass2, éditorial) est volontairement **non livré ici** : sans ≥ 48 h de données `api_usage_events`, fixer un cap sur la classification risquerait de dégrader silencieusement la qualité du feed (articles non classifiés). Une fois la projection quotidienne confirmée (≥ 1 cycle digest), une PR de suivi ajoutera la backpressure (dégrader pass 2 avant pass 1) derrière un flag, mesurée isolément.

## Tests
- [ ] `cost_budget` : count + cache + force_refresh + never-raises + `is_over_cap` (seuil, cap≤0) + projection.
- [ ] `smart_source_search` : suite existante verte (caps lus depuis le service).
- [ ] `pytest -v` complet.

## Acceptation post-deploy
Log `cost_budget_projection` présent quotidiennement ; cap Brave effectivement respecté à travers les restarts (la conso ne « repart pas de zéro » après un déploiement) ; projection ×2.25 < plan tarifaire Mistral/Brave, sinon prioriser la backpressure.
