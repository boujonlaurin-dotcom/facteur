# Bug: 500 ForeignKeyViolation sur `PATCH /api/user/sources` (favori sans `user_profiles`)

**Status**: Fix implémenté
**Branch**: `boujonlaurin-dotcom/fix-favorite-source-missing-profile`
**Severity**: 500 handled — 3 occurrences / 1 user en prod (release `fae905c`, première vue 2026-08-07 14:16 UTC)

---

## Symptômes

Mettre une source en favori renvoie un 500. Sentry :

```
ForeignKeyViolation: insert or update on table "user_favorite_sources"
violates foreign key constraint "user_favorite_sources_user_id_fkey"
DETAIL: Key (user_id)=(<uuid>) is not present in table "user_profiles".
```

Chemin : `PATCH /api/user/sources` → `set_source_state`
(`packages/api/app/routers/user_sources_state.py:51`) → `UserSourcesStateService.set_state`
(`app/services/user_interests_service.py`) → `_sync_favorite_source` →
`db.add(UserFavoriteSource(...))` → échec au `commit()`.

## Root Cause

`user_favorite_sources.user_id` porte une FK vers `user_profiles.user_id`
(`app/models/user_favorites.py:84`), mais **aucun middleware ni dépendance FastAPI ne garantit
l'existence du profil** : chaque chemin d'écriture doit appeler explicitement
`UserService.get_or_create_profile` (cf. `push_devices.py`, `personalization.py`,
`notification_preferences.py`…). Ce chemin ne le faisait pas.

L'insertion dans `user_sources` passe, elle, sans profil (`user_sources.user_id` n'a pas de FK,
`app/models/source.py:201`) — d'où un échec localisé au seul insert du favori.

Le même angle mort avait déjà été corrigé ponctuellement dans ce fichier pour le mute
(`_sync_muted_source`, garde avant l'upsert `user_personalization`), sans généraliser.

**Symétrique non signalé mais identique** : `UserInterestsService.set_state` écrit dans
`user_interests` (FK, `app/models/user.py:110`) puis `user_favorite_interests` (FK,
`user_favorites.py:46`) sans garde → `PATCH /api/user/interests` 500 de la même façon pour le
même compte. Corrigé dans la même passe.

## Fix

Fichier unique : `packages/api/app/services/user_interests_service.py`.

- `UserSourcesStateService.set_state` — `await UserService(self.db).get_or_create_profile(str(user_id))`
  en tête, avant le `select(UserSource)`. Couvre `_sync_favorite_source` **et** `_sync_muted_source`.
- `UserInterestsService.set_state` — même garde en tête, avant la branche `kind == "theme"`.
- `_sync_muted_source` — garde locale retirée (redondante ; le helper n'a qu'un appelant), commentaire
  conservé pour pointer la garde hoistée.
- `from app.services.user_service import UserService` remonté en import module-level (pas de cycle :
  `user_service` n'importe pas `user_interests_service`).

`get_or_create_profile` (`app/services/user_service.py:96`) est réutilisé tel quel : idempotent,
race-safe (savepoint `begin_nested` + rattrapage `IntegrityError`, Sentry PYTHON-5R) et **sans
commit**, donc composable dans la transaction du service — le `commit()` final reste le seul point
de validation. Il crée aussi le `user_streaks` manquant via `_ensure_streak_exists`.

Pas de migration Alembic (aucun DDL), pas de changement mobile ni de contrat API.

## Tests

`packages/api/tests/test_interest_state_profile_guard.py` (nouveau) :

1. `test_favorite_source_without_profile_creates_it` — FAVORITE sur un user sans `user_profiles` :
   profil créé, favori enregistré à la position 0.
2. `test_favorite_theme_without_profile_creates_it` — même chose côté Thèmes.
3. `test_existing_profile_is_not_duplicated` — profil existant : ni doublon de profil/streak, ni
   `onboarding_completed` écrasé ; le retour à FOLLOWED supprime bien le favori.
4. `test_patch_sources_returns_200_without_profile` — le chemin Sentry bout-en-bout via la stack
   HTTP (`PATCH /api/user/sources` → 200). Les tests router existants sèment tous un `UserProfile`
   dans leur fixture : aucun ne rejouait le 500, alors que le `commit()` du endpoint est le point
   d'échec d'origine.

Vérifié que les 4 tests **échouent** avec la garde neutralisée (FK `IntegrityError`), et passent
avec.

Non-régression : `tests/test_source_state_mute_sync.py` (retrait de la garde locale) et
`tests/routers/test_user_sources_state.py` verts.

Suite complète : **3067 passed, 21 skipped, 2 xfailed** (93 s). `ruff check` + `ruff format --check`
verts (0.15.14, version épinglée en CI). Boot `uvicorn` OK — l'import module-level de `UserService`
n'introduit pas de cycle ; `PATCH /api/user/sources` et `/api/user/interests` répondent 403 sans
auth et 401 sur token invalide (happy path non curl-able en local : JWT Supabase ES256 via JWKS).

## Chemins voisins audités (pas de garde ajoutée)

`UserInterestsService.reorder_favorites` et `UserSourcesStateService.reorder_favorites` écrivent
aussi dans des tables à FK, mais sont inatteignables sans profil : elles lèvent `TargetNotFavorite`
tant qu'il n'existe pas de row `user_interests`/`user_sources` en state FAVORITE (créée par
`set_state`, désormais gardé), et la branche `veille` valide un `VeilleConfig` ACTIVE dont le
`user_id` porte lui-même une FK vers `user_profiles` (`app/models/veille.py:66`).

## Suivi post-merge

Marquer l'issue Sentry comme résolue après déploiement staging et absence de nouvelle occurrence.
