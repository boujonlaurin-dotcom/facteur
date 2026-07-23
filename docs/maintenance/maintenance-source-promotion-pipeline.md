# Maintenance — Débloquer le pipeline de promotion des sources (WS1)

> PR A du plan « Enrichir le pool de sources par thème ». Débloque le backlog de
> sources évaluées bloquées en Tier 3 et empêche le backlog de se reformer.

## Contexte

Le footer « Étoffer [thème] » ne pousse que des sources `is_curated=true`. La
promotion vers ce catalogue passe par `scripts/retag_and_promote_sources.py`,
mais ce script ne tournait **qu'au lancement manuel** → un backlog de ~160
sources actives + évaluées (biais connu, fiabilité medium/high) restait
invisible à la reco. Diagnostic complet : plan `sources-theme-coverage`.

## Décision PO (2026-07-22) — garde-fou image de marque

La promotion automatique ne peut pas juger la valeur éditoriale d'une source ;
on a donc resserré le gate **avant** de vider le backlog :

1. **Exclusion `alternative`** — le gate de promotion n'excluait que `unknown`,
   alors que le gate de recommandation (`source_recommendation_gate`) exclut
   `alternative` ET `unknown`. Une source `alternative` pouvait donc être
   stampée `is_curated=true` (catalogue, admin, CSV master) sans jamais remonter
   dans « Étoffer ». Corrigé : `PROMO_EXCLUDED_BIAS = {unknown, alternative}`,
   miroir de `QUALITY_CATALOG_EXCLUDED_BIAS` (test de garde `test_excluded_bias_
   mirrors_reco_gate`). Sort **Élucid** automatiquement. `specialized`
   (sport/tech/science) reste promouvable : c'est un biais thématique.

2. **Denylist éditoriale** (`PROMO_DENYLIST`, 12 URLs) — sources qui passent le
   gate automatique mais dont la promotion se discute : blogs corpo/vendor
   (Hugging Face, The Stack/Humanloop), newsletters/agrégateurs (TLDR, Lenny's,
   Latent Space, Towards Data Science, Korben), hyper-niche (Reggae.fr,
   H2-mobile, Vertige Media), data aggregator (Statista), ONG militante
   (Amnesty). Réversible : retirer la ligne du dict.

**Résultat : 51 sources promues** (64 candidates au seuil ≥20 art/30j − 1
`alternative` − 12 denylist). Liste gelée : `.context/promotion-confirmed-list.md`.

## Changements

- `scripts/retag_and_promote_sources.py`
  - `PROMO_EXCLUDED_BIAS`, `PROMO_DENYLIST[_RAW]`, `_norm_url` remonté.
  - `is_promotable` / `compute_plan` : exclusion biais + denylist (paramétrables).
  - `write_promotions` extrait de `write_plan` (promotions seules, réutilisable).
- `app/jobs/promote_sources_job.py` — `promote_evaluated_sources()` : read →
  `compute_plan` → `write_promotions`. **Promotions seules** (ne touche pas
  `granular_topics`, réservé au run manuel + revue CSV). Idempotent, best-effort.
- `app/workers/scheduler.py` — job hebdo dimanche 04h00 Paris (après le recalcul
  de couverture 03h45). Empêche le backlog de se reformer.

## Sécurité migrations / DB partagée

Aucun DDL → pas de migration Alembic. La promotion est **additive**
(`is_curated` false→true), sûre pour le backend prod (ancien code) qui lit la
même colonne via son propre gate de reco. Le job n'est planifié que dans `main` ;
`production` l'obtiendra à la prochaine release hebdo, déjà avec le gate corrigé.

## Vérification

- `pytest tests/scripts/test_retag_and_promote_sources.py` (29 tests, dont
  `alternative` exclu, `specialized` gardé, denylist, garde miroir reco-gate).
- Import scheduler + job OK.
- Liste finale des 51 produite en lecture seule contre la DB prod.

## Appliquer le backlog en prod (post-merge)

Le job hebdo videra le backlog dimanche ; pour l'appliquer immédiatement :

```bash
cd packages/api
DATABASE_URL=<prod> python3 scripts/retag_and_promote_sources.py            # dry-run
DATABASE_URL=<prod> python3 scripts/retag_and_promote_sources.py --apply --allow-prod
```

Backup JSON écrit dans `.context/` avant mutation (rollback : `is_curated=false`
sur les IDs listés).

## Suivi (hors périmètre PR A)

- **WS1b — seuil adaptatif thèmes maigres** (science/sport/politics, ~22
  spécialistes 5–19 art/30j) : reporté, **exige une revue de liste PO** (promeut
  des sources non revues).
- **WS2** — colonne pondérée `coverage_theme_weights` + tri des suggestions.
- Corriger le `theme` mal étiqueté de plusieurs sources (L'Humanité→tech,
  Basket USA→tech, Science & Vie→tech…) pour le tri par thème de WS2.
