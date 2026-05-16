# QA Handoff — Story 22.1 (PR finale 22.1.1 + 22.1.2 + 22.1.3) : Système d'intérêts unifié 4-états + favoris + backfill legacy

> Empile **backend (22.1.1)** + **mobile (22.1.2)** + **backfill legacy + sync mobile (22.1.3)** sur la branche `22.1.1-backend-interests`. 3 commits, 1 PR finale vers `main`.

## Feature développée

Refonte du système d'intérêts mobile autour d'un modèle 4-états unique (`hidden` / `unfollowed` / `followed` / `favorite`) appliqué à Thèmes, Sujets et Sources. Cap dur de 3 favoris (séparé entre intérêts et sources). Ordre canonique éditable par drag. Le slider 1→3 (`TopicPrioritySlider`) et la SharedPreferences `theme_priority_*` disparaissent. Un seul provider `userInterestsProvider` alimente l'écran « Mes intérêts », la sheet filtre du feed et les onglets favoris du feed.

## PR associée

À créer via `/go` après ce QA. Cible : `--base main`.

## Écrans impactés

| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Mes intérêts | `/settings/interests` | **Nouveau** (déplacé de `features/custom_topics/` → `features/my_interests/`, refondu) |
| Mes sources | `/settings/sources` | **Modifié** (section Favoris ajoutée en haut + icône étoile par source) |
| Sheet « Filtrer parmi vos intérêts » | depuis le feed, bouton filtre | **Modifié** (« VOS FAVORIS » lit `userInterestsProvider.favorites`) |
| Onglets favoris du feed | top du Feed | **Modifié** (consume `userInterestsProvider.favorites` au lieu des SharedPrefs) |
| TopicExplorer / ArticleSheet | `/topic-explorer` + sheet | Inchangés visuellement (juste `TopicPrioritySlider` → `PrioritySlider` direct) |

## Scénarios de test

### Scénario 1 : 0 favori — état initial
**Parcours** :
1. Compte vierge → ouvrir `/settings/interests`.
2. Observer la section « Favoris (0/3) » en haut.

**Résultat attendu** : section présente avec hint « Aucun favori — étoile un Thème ou un Sujet pour le retrouver ici. ».

### Scénario 2 : Promotion Thème → Favori
**Parcours** :
1. Sur l'écran Mes intérêts, identifier le bloc « 💻 Technologie ».
2. Tap sur le chip d'état à droite du titre (Neutre/Suivi/Masqué) → bottom sheet picker.
3. Tap sur « Favori ».

**Résultat attendu** :
- Le picker se ferme.
- Tech apparaît en section Favoris (position 0).
- Compteur passe à « Favoris (1/3) ».
- Persistance : revenir sur l'écran → toujours présent.

### Scénario 3 : Cap atteint
**Parcours** :
1. Atteindre 3 favoris (3 Thèmes ou mélange).
2. Tap sur le chip d'un 4ᵉ Thème → picker.

**Résultat attendu** :
- L'option « Favori » est grisée + texte « Limite atteinte (3) — retirez-en un d'abord ».
- Si l'utilisateur insiste (tap quand même), aucun état n'est muté, snackbar « Tu as déjà 3 favoris. Retire-en un d'abord. ».

### Scénario 4 : Drag-reorder
**Parcours** :
1. Avoir ≥ 2 favoris.
2. Drag-handle (icône `dotsSixVertical`) à droite d'un favori → déplacer position 0 → 2.
3. Fermer puis rouvrir l'écran.

**Résultat attendu** : nouvel ordre persisté côté backend (`POST /api/user/interests/reorder` dans la Network tab).

### Scénario 5 : Masquer un Thème ou Sujet
**Parcours** :
1. Chip d'état → picker → « Masquer ».

**Résultat attendu** :
- L'item disparaît de la section principale.
- Apparaît dans l'ExpansionTile « Masqués (n) » en bas (replié par défaut, ouvrir pour vérifier).
- Tap sur « Modifier » → repicker → « Suivi » → l'item revient en section principale.

### Scénario 6 : Sources symétrique
**Parcours** : refaire 1-5 sur `/settings/sources`.
- Section Favoris en haut (vide → hint « Aucune source favorite — étoile une source… »).
- Tap sur l'icône étoile à droite de n'importe quelle source → picker → Favori.
- Cap = 3 (séparé du cap intérêts).
- Drag-reorder fonctionnel.

### Scénario 7 : Sheet feed reconnectée
**Parcours** :
1. Ouvrir le Feed → tap sur le bouton « Filtrer » (icône funnel) → sheet `interest_filter_sheet`.
2. Section « VOS FAVORIS ».

**Résultat attendu** :
- Affiche EXACTEMENT les favoris (Thèmes + Sujets confondus) dans l'ordre canonique du provider (drag user-controlled), pas la dérivation legacy `priorityMultiplier >= 2.0`.
- Si 0 favori → message « Définir mes thèmes favoris » avec CTA vers `/settings/interests`.

### Scénario 8a : Backfill legacy — compte avec slider Thème à 3/3 + Sujet à priority 2.0

> Validable via Supabase SQL editor avant/après MeP, ou en local via `make db-reset && alembic upgrade head`.

**Parcours** :
1. État pré-MeP : user a 1 `user_topic_profiles.priority_multiplier = 2.0` et 1 `user_interests.weight = 2.5` sur slug `culture`.
2. Lancer la migration `22a1_interest_state_favorites`.
3. Ouvrir l'app → écran « Mes intérêts ».

**Résultat attendu** :
- `user_favorite_interests` contient 2 lignes pour ce user (pos 0 = Sujet, pos 1 = culture).
- L'écran affiche « Favoris (2/3) » avec le Sujet en haut, culture en dessous.
- `state='favorite'` sur le Sujet et sur la row culture de `user_interests`.

### Scénario 8b : Backfill — compte vierge sans aucun signal

**Parcours** :
1. User existant `user_profiles` sans aucune row `user_interests` ni `user_topic_profiles`.
2. Lancer la migration.

**Résultat attendu** :
- 2 favoris automatiquement créés (positions 0 = tech, 1 = science) — premiers slugs de `CANONICAL_THEME_SLUGS`.
- 2 rows `user_interests` créées à `weight=0.5, state='favorite'`.
- Slot 3 reste libre pour un favori user ou pour le sync mobile.

### Scénario 8c : Backfill — cap respecté à 3

**Parcours** :
1. User avec 5 Sujets à `priority_multiplier=2.0`.
2. Lancer la migration.

**Résultat attendu** :
- Exactement 3 favoris en table (`COUNT(*) FROM user_favorite_interests WHERE user_id = X` = 3).
- Aucune erreur Postgres (`CHECK position BETWEEN 0 AND 2` respecté).
- Les 2 Sujets non promus restent en `state='followed'` (ou `'hidden'` si `priority=0.2`).

### Scénario 8d : Sync mobile post-MeP — purge SharedPrefs

**Parcours** :
1. Pré-MeP : SharedPrefs mobile contiennent `theme_priority_Technologie=2.0`, `theme_priority_Sport=3.0`, `theme_priority_Économie=1.0`.
2. MeP backend.
3. Lancer l'app mobile (peu importe l'écran ouvert ; auth requise).
4. Observer Network tab.

**Résultat attendu** :
- 2 `PATCH /api/user/interests` envoyés (tech, sport — pas economy car < 2.0).
- Réponse 200 sur les 2 (ou 422 silencieux si cap déjà atteint par le backfill).
- `theme_priority_*` purgées des SharedPrefs (vérifiable via DevTools).
- Flag `interests_v2_legacy_synced=true` écrit.
- Au 2e lancement : aucun call réseau pour cette feature (idempotence).

### Scénario 9 : Mode Serein préservé
**Parcours** :
1. Toggle Mode Serein ON.
2. Section Favoris cachée (par design — Serein gère un axe orthogonal).
3. Checkbox par sujet → toggle `excludedFromSerein` via `customTopicsProvider`.

**Résultat attendu** : les chips 4-états restent visibles uniquement en mode normal ; en mode Serein la checkbox classique persiste comme avant.

## Critères d'acceptation

- [ ] `rg topic_priority_slider apps/mobile/lib` → 0 résultat
- [ ] `rg themePriorityProvider apps/mobile/lib` → 0 résultat
- [ ] Endpoints `/api/user/interests` et `/api/user/sources` consommés (cf. DevTools Network)
- [ ] 422 `favorite_cap_reached` déclenche le snackbar exactement comme scénario 3
- [ ] Drag-reorder émet `POST /api/user/interests/reorder`
- [ ] `flutter test` vert (12+5 nouveaux tests + suite legacy)
- [ ] `pytest -v tests/alembic/test_interest_state_migration.py` vert (3 existants + 5 backfill)
- [ ] `flutter analyze` 0 issue actionnable (les `withOpacity` info pré-existants restent)
- [ ] **Post-MeP** : `SELECT COUNT(*) FROM user_profiles up WHERE NOT EXISTS (SELECT 1 FROM user_favorite_interests ufi WHERE ufi.user_id=up.user_id)` = 0
- [ ] **Post-MeP** : aucun user n'a > 3 favoris (cap respecté)
- [ ] **Post-MeP** : `state='favorite'` cohérent sur `user_interests` / `user_topic_profiles` pour chaque row dans `user_favorite_interests`

## Zones de risque

1. **Mode Serein** : la nouvelle UI ne re-implémente PAS le tri-state checkbox cascadant theme→topics (présent dans l'ancien `ThemeSection`). En mode Serein, chaque sujet a son propre checkbox indépendant. La fonctionnalité « masquer un thème entier en mode Serein » nécessite un tap par sujet. ⚠️ À tester si c'est acceptable produit ou si le tri-state doit être restauré.

2. **Suggestions de thèmes** : la suggestion-block existante (« Suggestions de sujets » par macro-thème, depuis `topicSuggestionsProvider`) est supprimée de l'écran refondu. Pour ajouter un sujet, l'utilisateur passe par le FAB « Sujet personnalisé » ou TopicExplorer. ⚠️ Confirmer que cette régression UX est OK pour 22.1.2 (le hand-off ne mentionnait pas explicitement les suggestions).

3. **Cohérence avec personalizationProvider** : la mise à state=hidden d'un Thème via le nouveau endpoint ne met PAS à jour `personalizationProvider.mutedThemes` (les deux mécanismes coexistent). Si une régression apparaît sur le filtrage du feed côté backend, vérifier `pertinence.py:~293` qui doit déjà router sur `state=hidden`.

4. **Backend pytest** : non re-vérifié en local par cet agent (Postgres local pas démarré sur port 54322). Le code backend a été produit dans un commit antérieur supposé vert. **À re-tester avant merge avec `supabase start` + `pytest -v tests/routers/test_user_interests.py tests/routers/test_user_sources_state.py`.**

## Dépendances

- Backend endpoints (déjà en working tree, à committer avec ce PR) :
  - `GET / PATCH /api/user/interests`
  - `POST /api/user/interests/reorder`
  - `GET / PATCH /api/user/sources`
  - `POST /api/user/sources/reorder`
- Migration Alembic `22a1_interest_state_favorites` (tables `user_favorite_interests`, `user_favorite_sources` + enum `interest_state` + colonne `state` sur `user_interests`/`user_topic_profiles`/`user_sources`).
- Aucune dépendance externe ajoutée (`pubspec.yaml` inchangé côté mobile).
