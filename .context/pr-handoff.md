# feat(tournee): suggestions garanties + quota visible + CTA carte + instrumentation (story 22.6)

Story 22.6 (PR 2), base `main`. Rend la Tournée « vivante » : un accent quotidien
de 4-5 sections « Choisie pour vous » **garanti pour tous** (même 8+ favoris), un
quota de 3 suggestions visibles sous le cap pour les comptes personnalisés, un CTA
direct sur la carte, et l'instrumentation PostHog. **Aucune migration** (additif,
expand-safe, 1 head Alembic). Invariant 22.3 conservé (jamais hors univers suivi).

> PR 1 (`promoteSuggestion` fiabilisé) vit dans un autre workspace ; cette PR
> suppose la même signature `promoteSuggestion(section)` et ajoute seulement un
> `origin` **optionnel** (défaut `card`) → rebase non cassante.

## A. Backend — plancher de suggestions

- `scoring_config.py` : `TOURNEE_SUGGEST_FLOOR = 4` ; `TOURNEE_SUGGEST_SUBCAP` 8 → 5.
- `routers/users.py` `_arrange_tournee` : `sub_cap = min(SUBCAP, max(remaining, FLOOR))` ;
  suppression de l'early-return `remaining <= 0` (gate `_smart_arrangement_enabled` conservé).
  Effet : 0 favori → 5, 7 favoris → 4, 8+ favoris → 4. Pool pauvre → sert moins, jamais d'invention.

## B. Mobile — quota visible ≥3 sous le cap

- `flux_continu_provider.dart` `_orderedTourneeKeys` : insertion additive à la frontière du cap ;
  `quota = min(kTourneeSuggestQuota=3, suggestions visibles)`, favoris tronqués à `cap - quota`
  **sans permutation**, puis les `quota` premières suggestions en queue. No-op non-personnalisé.

## C. Mobile — CTA « Ajouter à mon Essentiel »

- `section_block.dart` : `onPromoteSuggestion` + `_PromoteSuggestionButton` (spinner, anti
  double-tap, SnackBar « Ajouté à ton Essentiel »). Banner (badge + info-tap → sheet) inchangé.
- `flux_continu_screen.dart` : câble `promoteSuggestion(section, origin: 'card')` ; la sheet
  passe `origin: 'sheet'`.

## D. Instrumentation PostHog

- `analytics_service.dart` : `trackSuggestionImpression` / `Promoted` / `Dismissed`.
- Impressions dédupliquées **1/section/jour, persistées** (SharedPreferences `suggestion_impressions_v1`,
  purge des jours passés). Émission au premier build de la section suggérée.

## Vérification

- Backend : `pytest` — 37 tests top-themes/suggester/users OK ; 1 head Alembic (`181c618da382`).
- Mobile : `flutter test` — 453 tests flux_continu OK, 29 section_block, 14 analytics ;
  `flutter analyze` 0 erreur (5 warnings pré-existants `dio.post` hors périmètre).
- Changelog in-app : entrée « Ma Tournée » ajoutée (impact visible).

Story : `docs/stories/core/22.6.tournee-suggestions-garanties-cta.md`.
QA handoff : `.context/qa-handoff.md`.
