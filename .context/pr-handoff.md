# PR — feat: système d'intérêts unifié (22.1) + Flux Continu V1.8/V2.0 + couplage favoris (21.1)

> **PR finale unique** regroupant la story 22.1 (système d'intérêts) ET la
> story 21.1 (Flux Continu V1.8/V2.0 + couplage favoris) — l'absence de
> staging impose ce ship groupé.
>
> Commits (depuis `origin/main`) :
> 1. `ae59c924` — backend interest state + favorites tables + endpoints (22.1.1)
> 2. `2dee657a` — écrans intérêts/sources sur le moteur 4-états (22.1.2)
> 3. `0db30ad4` — backfill favoris legacy + sync mobile one-shot (22.1.3)
> 4. Commits Flux Continu V1.8 + V2.0 (Story 21.1, ~13 commits cherry-pickés)
> 5. `90fe4b7a` — WIP V10 : amorce couplage favoris (recovery du stash pré-pivot)
> 6. `<HEAD>` — refacto SectionKind string-keyed + couplage favoris finalisé
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

## Changements (commit 6 — couplage Flux Continu ↔ favoris finalisé)

> Cette PR finalise ce que le WIP V10 (`90fe4b7a`) avait amorcé. Le couplage
> est désormais complet, sans dette technique reportée.

### Refacto `SectionKind` en clés string-based

- `apps/mobile/lib/features/flux_continu/models/flux_continu_models.dart` :
  - `enum SectionKind { essentiel, bonnes, theme }` (un seul `theme`,
    plus de `theme1`/`theme2`).
  - `FeedThemeSection` gagne `String? customTopicId` (XOR avec `themeSlug`)
    pour distinguer Thème vs Sujet favori.
  - Top-level helper `String sectionKey(FluxSection s)` : retourne
    `'essentiel'` / `'bonnes'` / `'theme:<slug>'` / `'topic:<uuid>'`.
  - `Map<SectionKind, bool>` → `Map<String, bool>` pour `folded`/`moreOpen`.
    Helpers `isOpen(FluxSection)`/`isFolded(FluxSection)` (la dérivation de
    clé reste dans le modèle).

### Provider piloté par les favoris (`flux_continu_provider.dart`)

- `_themes` devient une `List<FeedThemeSection>` dynamique (0..3) au lieu
  de deux variables `_theme1`/`_theme2`.
- `_pickFavorites()` lit `userInterestsProvider.favorites` en priorité ;
  fallback `top-themes` legacy puis padding canonique `[tech, environment,
  science]` pour les comptes encore sans favori (filet pour
  pré-backfill 22.1.3).
- Pour chaque `FavoriteRef` :
  - `ThemeFavoriteRef(slug)` → `getFeed(theme: slug, ...)`
  - `CustomTopicFavoriteRef(id)` → `getFeed(topic: id, ...)` (l'endpoint
    backend `_resolve_topic_param` accepte slug OU UUID stringified
    scoped user — pas de cross-user leak).
- `ref.listen(userInterestsProvider, ...)` : sur changement de `favorites`,
  appelle `_refetchThemesOnly()` qui rejoue uniquement les `getFeed(theme/
  topic)` (économise digest + feed continu).
- Hydration SharedPreferences tolérante : `_isLiveFoldedKey` ignore
  silencieusement les anciennes clés `theme1`/`theme2` (purge journalier
  les nettoie dans <24h).

### Adaptations écran + widgets

- `flux_continu_screen.dart` : `_isFavoriteKind` → `_isFavoriteSection`,
  `_markSectionsAboveAsScrolledPast(FluxSection? fromSection)` (compare
  via `sectionKey`).
- `widgets/section_block.dart` : callback `onTapArticle(article,
  FluxSection)` au lieu de `(article, SectionKind)`.
- `widgets/my_interests_sheet.dart` : lit directement
  `userInterestsProvider.favorites` (au lieu de
  `fluxContinuProvider.sections.whereType<FeedThemeSection>()`), affiche
  `N/3 FAVORIS`, résout label/accent via `themeMap` (Theme) ou
  `customTopics` (Sujet).

### Tests

- `test/features/flux_continu/models/flux_continu_models_test.dart` :
  +4 tests `sectionKey` (digest/theme/topic/slug-less), Maps réécrits en
  string-keys.
- `test/features/flux_continu/providers/flux_continu_provider_test.dart` :
  +5 tests favoris-driven (0 favori → 3 canoniques fetched, 1 Theme,
  1 Sujet → `getFeed(topic:)`, cap 3, hydration tolère `theme1`/`theme2`).
- `test/features/flux_continu/widgets/my_interests_sheet_test.dart` :
  refait sur stub `UserInterestsNotifier`, couvre custom topic + empty
  hint.

Total mobile flux_continu : **49 tests verts** (vs 6 avant).

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
- [x] `flutter test test/features/flux_continu/` : 49/49 verts (5 nouveaux
      tests couplage favoris finalisé + 1 hydration tolerance)
- [x] `flutter test` complet : 639 tests, 36 échecs **tous pré-existants**
      (digest stubs « Test not implemented », topic_chip icon finder, auth/
      notification/feed scenarios — zéro régression dans `flux_continu` ou
      `my_interests`)
- [x] `flutter analyze` flux_continu/my_interests/tests : 0 erreur
      (9 infos `withOpacity`/`activeColor` pré-existantes)
- [x] `alembic heads` local → 1 ligne (`22a1_interest_state_favorites`)
- [x] Head Alembic prod vérifié = `ad01_add_is_ad_to_contents` (matche
      `down_revision` de la nouvelle migration — pas de drift)
- [x] Audit prod : 39 doublons `(user_id, interest_slug)` confirmés
      (gérés par le dedupe défensif de la migration)
- [x] Audit prod : enum `interest_state` / table `user_favorite_interests` /
      colonne `user_interests.state` tous absents → migration tournera
      cleanly sans collision
- [x] `rg "SectionKind\\.(theme1|theme2)" apps/mobile/` → 0 résultat
- [ ] `/validate-feature` (Chrome 390x844) APPROVED : 9 scénarios A. 22.1 +
      9 scénarios B. 21.1 + 7 scénarios C. couplage (9a→9g) du
      `.context/qa-handoff.md`
- [ ] Smoke tests F1-F8 ci-dessus à T+10min post-déploiement Railway
- [ ] Vérification PostHog `interest_state_changed` à T+1h
