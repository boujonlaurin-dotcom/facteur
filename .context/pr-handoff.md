# PR1 — Lettres du Facteur (backend) · Story 19.1

## Summary

PR1 sur 3 pour la feature « Lettres du Facteur » (soft onboarding gamifié, anti-FOMO).

- Nouvelle table `user_letter_progress` (Alembic `lf01`) — stocke uniquement la progression utilisateur.
- 3 lettres en constantes Python (`app/services/letters/catalog.py`) : L0 « Bienvenue » (archivée par défaut), L1 « Tes premières sources » (4 actions auto-détectées), L2 « Ton rythme idéal » (upcoming, débloquée au classement de L1).
- 2 endpoints :
  - `GET /api/letters` → état complet, idempotent (init silencieux pour new user).
  - `POST /api/letters/{letter_id}/refresh-status` → recalcule auto-détection + chaînage.
- Auto-détection serveur des 4 actions de L1 :
  - `define_editorial_line` → `count(user_topic_profiles)` ≥ 3.
  - `add_5_sources` → `count(user_sources)` ≥ 5.
  - `add_2_personal_sources` → `count(user_sources WHERE is_custom)` ≥ 2.
  - `first_perspectives_open` → ≥1 `analytics_events` `event_type='perspectives_opened'` (event ajouté de manière non-bloquante dans `routers/contents.py:get_perspectives`).

## Décisions architecturales

- **FK** : `user_profiles.user_id` (cohérent avec `veille_configs`), pas `auth.users(id)`.
- **RLS** : non activée — scoping par FastAPI auth (cohérent avec les autres tables user-scoped).
- **Lettres = constantes** : V1 = 3 lettres en dur, rotation = redeploy. Pas de surface d'admin pour V1.
- **Migration** : Alembic + apply manuel Supabase. **Application Supabase TODO** : `mcp__supabase__apply_migration` est en read-only mode dans cet environnement. À exécuter manuellement via Supabase SQL Editor (le SQL est dans le commit + dans `docs/stories/core/19.1.lettres-facteur.md`).

## Test plan

- [x] `pytest tests/routers/test_letters_routes.py -v` — 11/11 PASSED (init, 4 détecteurs, chaînage, idempotence x2, cross-tenant, 404).
- [x] Suite complète `pytest -v --ignore=tests/routers/test_notification_preferences.py` — 934 passed, 13 skipped.
- [x] `ruff format --check` + `ruff check` — verts sur tous les fichiers touchés.
- [x] `bash docs/qa/scripts/verify_letters.sh` — pytest pass + smoke routes wired.
- [x] `alembic heads` → 1 head unique (`lf01`).
- [ ] **Manuel post-merge** : appliquer la migration `lf01_create_user_letter_progress` sur Supabase via SQL Editor (MCP read-only en local).

### Test ignoré

`tests/routers/test_notification_preferences.py::test_patch_increments_refusal_count` est en échec **pré-existant** (TZ-dépendant Paris été : assertion sur string `2026-04-28T12:00:00` qui matche pas `2026-04-28T14:00:00+02:00`). Pas de lien avec cette PR — confirmé en stashant les changements.

## Suite — PR2 et PR3

Cette PR ne touche **pas** au mobile. Suivi dans `docs/stories/core/19.1.lettres-facteur.md`.

- PR2 = data layer mobile (modèles Dart + provider + RingAvatar + ProfileAvatarButton).
- PR3 = UI mobile (7 widgets, 2 screens, route, banner feed, /validate-feature).

## Forme JSON `GET /api/letters` (pour PR2)

```json
[
  {"id":"letter_0","num":"00","title":"Bienvenue chez Facteur","message":"...","signature":"Le Facteur","actions":[],"status":"archived","completed_actions":[],"progress":1.0,"started_at":null,"archived_at":"2026-05-02T..."},
  {"id":"letter_1","num":"01","title":"Tes premières sources","message":"Bienvenue. Avant de t'emmener plus loin...","signature":"Le Facteur","actions":[{"id":"define_editorial_line","label":"...","help":"..."}, ...],"status":"active","completed_actions":["define_editorial_line"],"progress":0.25,"started_at":"2026-05-02T...","archived_at":null},
  {"id":"letter_2","num":"02","title":"Ton rythme idéal","message":"...","signature":"Le Facteur","actions":[{"id":"set_frequency","label":"...","help":"..."}],"status":"upcoming","completed_actions":[],"progress":0.0,"started_at":null,"archived_at":null}
]
```
