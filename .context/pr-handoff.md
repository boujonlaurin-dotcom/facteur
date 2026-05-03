# PR — Veille V1 personalization (PR A : fondations DB + presets)

## Summary

Première brique de la refonte V1 « Ma veille ». Pose les colonnes DB pour
capturer purpose / editorial_brief / preset_id (PR B câblera la persistance via
le router `/config`) et expose un endpoint public `GET /api/veille/presets`
qui alimente la nouvelle section « Inspirations » du Step 1 + le nouvel écran
Step 1.5 « preset preview » côté mobile.

## What

### Backend

- **Migration `vp01`** (heads `ls01` → `vp01`) :
  - 4 colonnes nullables sur `veille_configs` (`purpose`, `purpose_other`,
    `editorial_brief`, `preset_id`).
  - `notif_veille_enabled BOOLEAN NOT NULL DEFAULT false` sur
    `user_notification_preferences` (toggle pour la modal opt-in PR C).
- **`GET /api/veille/presets`** (public, no-auth) — retourne les presets V1
  avec leurs sources curées (résolution runtime via
  `Source.theme + is_curated + is_active`, ordre `name`, limite 6).
- Données : `app/data/veille_presets.py`.
- Schemas : `VeillePresetResponse` + adjacents.

### Mobile

- Nouvel écran `step1_5_preset_preview_screen.dart` (preview du preset entre
  Step 1 thème et Step 2 topics).
- `veille_presets_provider.dart` (Async list provider, GET `/presets`).
- Step 1 thème enrichi : section « Inspirations » avec preset cards.
- `veille_config_provider.dart` étendu (purpose, editorialBrief, presetId).
- Modèles + serializers `VeilleConfig` étendus.
- Tests : presets model/provider + screens
  (`step1_5_preset_preview_screen_test.dart`) + widgets
  (`preset_card_test.dart`).

## How ça a été vérifié

- [ ] `pytest -v` (backend complet, incl. `test_veille_presets` +
      `test_veille_personalization_columns`)
- [ ] `ruff format --check && ruff check` (lint Python)
- [ ] `alembic heads` → 1 head (`vp01`) ; `alembic upgrade head` OK local
- [ ] `flutter test && flutter analyze`
- [ ] `curl GET /api/veille/presets` → 200 sans auth, body non vide
- [ ] Playwright MCP : Step 1 → preset card → Step 1.5 preview → Step 2
- [ ] `/simplify` passé

## Hors scope (PR B / PR C)

- PR B : câblage persistance des champs `purpose / editorial_brief / preset_id`
  dans POST `/api/veille/config` (router).
- PR C : modal opt-in notif veille (toggle `notif_veille_enabled`).

## Zones à risque

- **Migration** : ajout colonnes nullable + 1 NOT NULL avec
  `server_default('false')` → safe sur table existante, compatible rolling
  deploy. Pas d'index ajouté.
- **Endpoint `/presets` no-auth** : OK (lecture seule, pas de PII, pas de
  rate-limit dédié — la donnée est statique côté serveur).
