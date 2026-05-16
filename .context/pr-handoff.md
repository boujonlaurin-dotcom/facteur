# PR — feat(interests): système 4-états unifié + favoris + backfill legacy (Story 22.1)

> **PR finale unique** regroupant les 3 commits de la story 22.1 :
> 1. `ae59c924` — backend interest state + favorites tables + endpoints
> 2. `2dee657a` — écrans intérêts/sources sur le moteur 4-états
> 3. `<HEAD>` — backfill favoris legacy + sync mobile one-shot
>
> Cible : `--base main` (staging déprécié).

## Summary

- **Refonte complète du système d'intérêts** autour d'un unique modèle 4-états (`hidden` / `unfollowed` / `followed` / `favorite`) appliqué aux Thèmes, Sujets et Sources. Cap dur à 3 favoris par catégorie (intérêts vs sources, séparés). Ordre canonique éditable par drag.
- **Backend** : enum `interest_state`, 2 nouvelles tables (`user_favorite_interests`, `user_favorite_sources`), 6 nouveaux endpoints, câblage `state` dans la Pertinence (`hidden`=0 ; `favorite`=floor 1.5).
- **Mobile** : suppression du slider 1→3 + SharedPrefs `theme_priority_*`, nouveau `userInterestsProvider` (source de vérité unique), écrans Mes intérêts/Mes sources refondus, sheet feed reconnectée sur `favorites`.
- **Backfill + sync legacy (commit 3)** : la migration peuple `user_favorite_interests` pour 100 % des users existants (cible ≥ 2 favoris, cap 3) ; au 1er lancement mobile post-MeP, un service silencieux promeut les Thèmes 3/3 hérités vers les favoris backend puis purge les SharedPrefs.

## Changements (commit 3 — détail)

### Backend

- `app/constants.py` : ajout `MIN_BACKFILL_FAVORITES=2` et `CANONICAL_THEME_SLUGS` (9 macro-thèmes).
- `alembic/versions/22a1_interest_state_favorites.py` : extension `upgrade()` avec CTE backfill SQL pur (idempotent via `ON CONFLICT DO NOTHING`) qui construit jusqu'à 3 favoris/user dans cet ordre :
  1. Sujets custom à `priority_multiplier=2.0`
  2. Top weight ML Thèmes (skip ceux passés `hidden` à l'étape précédente)
  3. Fallback `tech` + `science` pour les users sans aucun signal
  - Ensuite `UPDATE state='favorite'` sur les rows sources + `INSERT user_interests` pour les fallback themes.
- `tests/alembic/test_interest_state_migration.py` : 5 nouveaux tests (promo Sujet 2.0, complétion à min 2, fallback canonical, cap 3, idempotence re-run).

### Mobile

- `apps/mobile/lib/features/my_interests/services/interests_sync_service.dart` : service one-shot lit les `SharedPreferences.theme_priority_<MacroLabel>` (legacy), promeut chaque thème à `multiplier >= 2.0` en favori via `setInterestState`, absorbe `FavoriteCapReachedException` silencieusement, purge toutes les clés legacy + pose le flag `interests_v2_legacy_synced`.
- `apps/mobile/lib/app.dart` : `ref.watch(interestsSyncProvider)` dans `FacteurApp.build()` (pattern miroir d'`onboardingSyncProvider`).
- `test/features/my_interests/services/interests_sync_service_test.dart` : 5 tests (promo, idempotence, cap absorption, purge prefs, macro-label inconnu).

## Mobile rétrocompat & sécurité du staged rollout

Les endpoints legacy (`PUT /api/personalization/topics/{id}`, `PUT /api/sources/{id}/weight`, `GET /api/users/top-themes`) **restent intacts** : un client mobile pré-22.1.2 continue de fonctionner sans cassure pendant la fenêtre de roll-out. Le sync mobile s'exécute uniquement après auth, fire-and-forget, et est silencieux sur toute erreur (404, 422, 5xx).

## Migration impact (rappel)

- **Tables touchées** : `user_interests` (+ `state` + UNIQUE `(user_id, interest_slug)`), `user_topic_profiles` (+ `state`), `user_sources` (+ `state`).
- **Tables créées** : `user_favorite_interests`, `user_favorite_sources`.
- **Type créé** : `interest_state` (ENUM 4 valeurs).
- **Dedupe défensif** : 39 doublons `(user_id, interest_slug)` purgés (garde la row de plus grand weight).
- **Migration de données** : `weight ≤ 0.5` → `hidden` ; `priority_multiplier = 0.2` → `hidden` ; **backfill** des favoris pour tous les users existants.
- **Downgrade** : `DROP TABLE` cascade tout, round-trip testé.

## Plan rollback exécutable

1. **Si la migration plante au boot Railway** :
   - Revert la PR sur GitHub → redéploie le commit précédent (chaîne pointe sur `ad01`).
   - Cas extrême : SSH pod prod + `alembic downgrade -1` manuel.
2. **Si la migration passe mais comportement cassé** :
   - Revert la PR. Les endpoints legacy intacts maintiennent les anciens clients mobile.
   - Le nouveau mobile (publié après la PR) gère gracieusement les 5xx via caches existants.
   - Les favoris backfillés sont droppés en cascade par le downgrade (table détruite).
3. **Intégrité post-rollback** :
   ```sql
   SELECT COUNT(*) FROM user_interests;        -- doit matcher baseline pre-MeP (à part les 39 doublons dédupés)
   SELECT COUNT(*) FROM information_schema.tables WHERE table_name LIKE 'user_favorite_%';  -- = 0
   SELECT COUNT(*) FROM pg_type WHERE typname='interest_state';  -- = 0
   ```

## Smoke tests post-MeP (à T+10min après déploiement Railway)

```bash
# 1. Healthcheck
curl https://api.facteur.app/health  # 200

# 2. Backfill effectif : aucun user à 0 favori
psql $DATABASE_URL -c "
  SELECT COUNT(*) FROM user_profiles up
  WHERE NOT EXISTS (
    SELECT 1 FROM user_favorite_interests ufi WHERE ufi.user_id = up.user_id
  );
"  # → 0 (ou très petit nombre d'edge cases acceptables)

# 3. Distribution des favoris par user
psql $DATABASE_URL -c "
  SELECT cnt, COUNT(*) FROM (
    SELECT user_id, COUNT(*) AS cnt
    FROM user_favorite_interests GROUP BY user_id
  ) s GROUP BY cnt ORDER BY cnt;
"  # → majorité à 2 ou 3, aucun > 3

# 4. Cap respecté
psql $DATABASE_URL -c "
  SELECT COUNT(*) FROM (
    SELECT user_id FROM user_favorite_interests GROUP BY user_id HAVING COUNT(*) > 3
  ) s;
"  # → 0

# 5. state='favorite' cohérent
psql $DATABASE_URL -c "
  SELECT COUNT(*) FROM user_favorite_interests ufi
  LEFT JOIN user_interests ui ON ui.user_id = ufi.user_id AND ui.interest_slug = ufi.interest_slug
  WHERE ufi.interest_slug IS NOT NULL AND (ui.state != 'favorite' OR ui.state IS NULL);
"  # → 0

# 6. GET interests sur compte de test
curl -H "Authorization: Bearer $JWT_TEST" https://api.facteur.app/api/user/interests \
  | jq '{count: .favorite_count, cap: .favorite_cap, favorites: .favorites}'
# → favorite_count >= 2, cap = 3

# 7. PATCH au-delà du cap → 422
# (après avoir 3 favoris)
curl -X PATCH https://api.facteur.app/api/user/interests \
  -H "Authorization: Bearer $JWT_TEST" \
  -d '{"kind":"theme","target_id":"sport","state":"favorite"}'  # → 422

# 8. PostHog (à T+1h)
# Dashboard PostHog : événements `interest_state_changed` doivent arriver
# dans l'heure suivant la MeP (sync mobile des Thèmes 3/3 legacy).
```

## PostHog events

Hérités de PR 22.1.1 (convention flat snake_case) :
- `interest_state_changed` (kind, target_id, new_state, prev_state)
- `interest_favorite_reordered` (favorite_count, kind)
- `interest_cap_blocked` (kind, target_id, current_count)

Le sync mobile post-MeP émet `interest_state_changed` une fois par Thème legacy promu — métrique idéale pour mesurer le taux de couverture sync sur 30j.

## Test plan

- [x] `pytest -v` complet : 1121+5 passed, 0 failures (+ tests backfill)
- [x] `flutter test` complet : 0 failure (+ 5 tests sync mobile)
- [x] `flutter analyze` 0 issue actionnable
- [x] `alembic heads` → 1 ligne (`22a1_interest_state_favorites`)
- [x] `alembic upgrade head` sur DB vide OK + round-trip downgrade/upgrade OK
- [ ] Smoke tests F1-F8 ci-dessus à T+10min post-déploiement Railway
- [ ] Vérification PostHog `interest_state_changed` à T+1h
