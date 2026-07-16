# Bug — L'appartenance à l'Essentiel (sources + thèmes) se perd

## Symptôme (PO)

> « L'enregistrement des sources dans l'Essentiel de la Tournée du jour se perd
> très régulièrement. Info trop importante pour être perdue. »

## Cause racine — persistance en *split-brain*

- Le **favori** d'une source / d'un thème *est* persisté en DB
  (`user_sources.state`, `user_interests.state`). ✓
- Mais **le mode de placement** — « Chaque jour dans l'Essentiel » vs « Flâner » —
  ne vivait **que dans `SharedPreferences`** :
  - source Essentiel ⟺ clé `source:<id>` dans `tournee_order_v1` ;
  - thème Flâner ⟺ clé `theme:<slug>` dans `pinned_tabs_order_v1` (défaut = Essentiel).
  Rien côté backend ne distinguait Essentiel de Flâner. ✗

⇒ à la **réinstallation / nouveau device / purge du stockage**, le favori survit
en DB mais son placement Essentiel disparaît silencieusement → la source « tombe »
de l'Essentiel. De plus les écritures de prefs sont *best-effort* (erreurs
avalées), d'où la dérive « régulière ».

## Correctif — la DB devient la source de vérité durable

Colonne **`essentiel_mode BOOLEAN NULL`** ajoutée à `user_sources` et
`user_interests` (`true`=Essentiel, `false`=Flâner, `NULL`=jamais placé / legacy).
Migration additive pure `es01_essentiel_placement` (expand-contract, sûre sur la
DB partagée staging/prod). Les prefs locales restent le cache de rendu.

### Backend
- Modèles `UserSource` / `UserInterest` : `essentiel_mode: bool | None`.
- Schémas : champ optionnel sur `SetSourceStateRequest` / `SetInterestStateRequest`
  (écriture) et exposé sur `SourceStateResponse` / `ThemeInterestResponse` (lecture).
- Services `set_state` : écrivent `essentiel_mode` **quand fourni**, le
  **préservent** quand `None` (jamais de `NULL` écrasant un placement connu ;
  injecté dans les deux branches de l'upsert thème).
- Routers : passent `body.essentiel_mode` au service.

### Mobile
- Repo / notifiers / modèles : param + champ `essentielMode` propagés jusqu'au
  `PATCH` (omis quand `null`).
- Écriture immédiate à chaque **ajout / déplacement** de mode
  (`manage_favorites_sheet`, `promoteSuggestion`).
- **Réconciliation au cold-boot** (`essentiel_placement_sync.dart`, hookée dans le
  bootstrap de la Tournée) :
  1. **Backfill local → DB** (one-shot, flag `essentiel_placement_reconciled_v1`) :
     capture le placement device actuel des favoris encore `NULL` en DB.
  2. **Hydratation DB → local** (chaque cold-boot, idempotente) : restaure les
     prefs à partir du placement DB connu → **répare la perte à la réinstallation**.
  La règle de rendu (`sourceIsEssentiel`) est inchangée : elle lit les prefs,
  désormais rendues durables par l'hydratation.

### Asymétrie source/thème (préservée)
- **Source** : Essentiel ⟺ clé dans `tournee_order_v1` (défaut = Flâner).
- **Thème** : Flâner ⟺ clé dans `pinned_tabs_order_v1` (défaut = Essentiel).
La réconciliation encode `essentiel_mode` sémantiquement et traduit par type.

## Vérification
- Alembic : 1 head ; upgrade/downgrade/re-upgrade round-trip OK sur DB vierge.
- Backend : `pytest` routers sources + interests (persiste quand fourni, préserve
  quand `None`, `false` distinct de `NULL`).
- Mobile : test du réconciliateur (backfill Essentiel/Flâner, one-shot gardé,
  hydratation source/thème — dont la répro « clé ré-ajoutée à `tournee_order` »).
- `flutter analyze` : 0 erreur ; suites `my_interests` + `flux_continu` vertes.

## Fichiers
- Migration : `packages/api/alembic/versions/es01_essentiel_placement.py`
- Backend : `models/source.py`, `models/user.py`, `schemas/user_interests.py`,
  `services/user_interests_service.py`, `routers/user_sources_state.py`,
  `routers/user_interests.py`
- Mobile : `user_interests_repository.dart`, `user_sources_state_provider.dart`,
  `user_interests_provider.dart`, `user_sources_state.dart`,
  `user_interests_state.dart`, `manage_favorites_sheet.dart`,
  `flux_continu_provider.dart`, **nouveau** `essentiel_placement_sync.dart`
