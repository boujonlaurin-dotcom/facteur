# PR — fix: custom_topic→favori interdit + 3 régressions pipeline Essentiel

## Summary

Deux corrections indépendantes regroupées :

**1. Story 23.3 — custom_topic ne peut plus être épinglé favori**

Un sujet personnalisé (« Plongée », « Elon Musk »…) ne peut plus passer à l'état `favorite`. La pipeline Mistral classe les articles sur 51 slugs figés ; un custom_topic mappe toujours sur son `slug_parent` (ex. « Plongée » → `sport`), donc filtrer via favori custom_topic remontait tout le sport, pas la plongée. Décision PO : seuls les thèmes et les veilles peuvent être favoris.

- **Backend** : nouvelle exception `CustomTopicFavoriteForbidden` levée dans `set_state()` et `reorder_favorites()` si `kind=="custom_topic"` + `state==FAVORITE`. Router mappe → 422 `{"error": "custom_topic_favorite_forbidden"}`.
- **Mobile** : `InterestStatePickerSheet` accepte un flag `allowFavorite` (default `true`). Le `_pickState` passe `allowFavorite: refTarget is! CustomTopicFavoriteRef`. Un bouton inline `_AddTopicInlineButton` est réintroduit en bas de chaque `_ThemeBlock` (remplace le FAB global pour les thèmes déjà suivis).
- **Migration** `23a3_downgrade_custom_topic_favorites` : downgrade silencieux — `user_topic_profiles.state` favorite→followed + DELETE des rows `user_favorite_interests` avec `custom_topic_id IS NOT NULL`.

**2. Fix pipeline "Essentiel du jour" (3 régressions)**

Cause racine commune : `_schedule_background_regen` n'avait aucune garde horaire et générait le digest à 00h Paris, avant les Unes du matin, puis bloquait le cron 07h30 via `digest_background_regen_skipped_good_format`.

- **Fix 1 — garde horaire** : refuse de spawner pour `target_date == today` avant `DIGEST_CRON_HOUR_PARIS:DIGEST_CRON_MINUTE_PARIS` (07:30 Paris).
- **Fix 1bis — clone yesterday ephemeral** : nouvel user inscrit la nuit → rendu éphémère du digest editorial_v1 de la veille d'un autre user (`is_stale_fallback=True`, jamais persisté).
- **Fix 2 — drop subject sans `actu_article`** : `pipeline.py:343` passe de `actu is None AND deep is None` à `actu is None` — un sujet deep-only va sur le rail "Prendre du recul".
- **Fix 3 — filtre multi-source avant LLM** : `curation.py:218-243` pré-filtre le pool à `source_count >= 2` avant LLM, fallback à `available` si pool < count.

## Test plan

- [x] `pytest tests/routers/test_user_interests.py` (107 cases, 422 sur custom_topic+favorite)
- [x] `pytest tests/test_digest_service.py` (23 passed)
- [x] `pytest tests/test_digest_readonly_hotpath.py` (11 passed)
- [x] `pytest tests/editorial/test_pipeline.py` (12 passed)
- [x] `pytest tests/editorial/test_curation.py` (13 passed)
- [x] `flutter test test/features/my_interests/` (11 passed, dont Story 23.3 `allowFavorite=false`)
- [x] `flutter analyze` — 0 erreurs
- [x] Alembic 1 head : `23a3_downgrade_custom_topic_favorites`
- [ ] Post-deploy : `SELECT state, COUNT(*) FROM user_topic_profiles WHERE kind='custom_topic' AND state='favorite'` → 0 rows.
- [ ] Post-deploy : `SELECT MIN(generated_at AT TIME ZONE 'Europe/Paris') FROM daily_digest WHERE target_date = CURRENT_DATE` → ≥ 07:30.
- [ ] Post-deploy : `source_count` du rang 1 ≥ 3, aucun subject avec `actu_article = null`.

## Zones à risque

- `user_interests_service.py` / `routers/user_interests.py` : mutation path favoris
- `digest_service.py` : hotpath lecture digest (step 3b)
- `alembic/versions/23a3_*` : migration one-shot destructive (pas de downgrade)
