# QA Handoff — PR finale unifiée : Système d'intérêts 22.1 + Flux Continu 21.1 V1.8/V2.0

> Reconvergence des deux workstreams (`22.1.x-backend-interests` + `flux-continu-v18-refonte` + WIP V10) sur la branche `22.1.1-backend-interests`. UNE PR vers `main`.

## Vue d'ensemble

Deux features shippées ensemble :

1. **Système d'intérêts 4-états unifié + favoris + backfill (Story 22.1)** — Backend (migration + endpoints + services), mobile screens, sync mobile one-shot.
2. **Flux Continu V1.8 + finitions V2.0 (Story 21.1)** — Home Flux Continu, hero Explorer, sticky bascule tab bar ↔ filter bar, fold différé entre sessions.

Les deux features sont **indépendantes au runtime** mais le WIP V10 du Flux Continu **consomme** la table `user_favorite_interests` peuplée par la migration 22.1. C'est la raison principale du ship groupé.

## PR associée

À créer via `/go` après ce QA. Cible : `--base main`. Remplace de facto PR #614 (à fermer ou rebaser après merge).

---

# A. Système d'intérêts 22.1 — détail

## Feature développée

Refonte du système d'intérêts mobile autour d'un modèle 4-états unique (`hidden` / `unfollowed` / `followed` / `favorite`) appliqué à Thèmes, Sujets et Sources. Cap dur de 3 favoris (séparé entre intérêts et sources). Ordre canonique éditable par drag. Le slider 1→3 (`TopicPrioritySlider`) et la SharedPreferences `theme_priority_*` disparaissent. Un seul provider `userInterestsProvider` alimente l'écran « Mes intérêts », la sheet filtre du feed et les onglets favoris du feed.

## Écrans impactés (22.1)

| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Mes intérêts | `/settings/interests` | **Nouveau** (déplacé de `features/custom_topics/` → `features/my_interests/`, refondu) |
| Mes sources | `/settings/sources` | **Modifié** (section Favoris ajoutée en haut + icône étoile par source) |
| Sheet « Filtrer parmi vos intérêts » | depuis le feed, bouton filtre | **Modifié** (« VOS FAVORIS » lit `userInterestsProvider.favorites`) |
| Onglets favoris du feed | top du Feed | **Modifié** (consume `userInterestsProvider.favorites` au lieu des SharedPrefs) |
| TopicExplorer / ArticleSheet | `/topic-explorer` + sheet | Inchangés visuellement (juste `TopicPrioritySlider` → `PrioritySlider` direct) |

## Scénarios de test (22.1)

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

## Critères d'acceptation (22.1)

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

## Zones de risque (22.1)

1. **Mode Serein** : la nouvelle UI ne re-implémente PAS le tri-state checkbox cascadant theme→topics. En mode Serein, chaque sujet a son propre checkbox indépendant. ⚠️ À tester si acceptable produit.

2. **Suggestions de thèmes** : la suggestion-block existante (« Suggestions de sujets » par macro-thème, depuis `topicSuggestionsProvider`) est supprimée de l'écran refondu. Pour ajouter un sujet, l'utilisateur passe par le FAB « Sujet personnalisé » ou TopicExplorer.

3. **Cohérence avec personalizationProvider** : la mise à state=hidden d'un Thème via le nouveau endpoint ne met PAS à jour `personalizationProvider.mutedThemes` (les deux mécanismes coexistent).

4. **Backend pytest** : à re-tester avant merge avec `supabase start` + `pytest -v tests/routers/test_user_interests.py tests/routers/test_user_sources_state.py`.

## Dépendances (22.1)

- Backend endpoints : `GET/PATCH /api/user/interests`, `POST /api/user/interests/reorder`, `GET/PATCH /api/user/sources`, `POST /api/user/sources/reorder`
- Migration Alembic `22a1_interest_state_favorites` (tables `user_favorite_interests`, `user_favorite_sources` + enum `interest_state` + colonne `state` sur 3 tables)
- Aucune dépendance externe ajoutée (`pubspec.yaml` inchangé côté mobile)

---

# B. Flux Continu 21.1 V1.8/V2.0 — détail

## ⚠️ Décision UX 2026-05-14 — fold différé entre sessions (V2.0)

PO Laurin a signalé : « En scroll-down continu, des "sauts" apparaissent toujours en arrivant à la fin d'une section. » Quatre approches in-session ont échoué (trigger naïf, `userScrollDirection`, `correctBy` post-frame, `SliverList` natif) — toutes laissaient un décalage visible parce qu'un resize de sliver dans un `CustomScrollView` impose mécaniquement de réaligner le contenu en dessous.

**Pivot UX** : abandonner le fold pendant la session active. Le scroll-past est désormais **détecté mais persisté en silence** — la section reste expanded à l'écran jusqu'à ce que le user quitte/relance l'app. Au prochain cold launch, les sections "consommées" lors de la session précédente apparaissent déjà en `FoldedSectionCard` (la transition fold→expanded n'est plus visible parce qu'elle est portée par l'initial layout, pas par un changement en cours de session).

**Critères d'acceptation V2.0** :
1. Pendant une session active, **aucune section ne se replie automatiquement au scroll** — le user voit toujours le hero plein-format, même après l'avoir scrollé.
2. Aucun saut visuel, aucun stutter pendant le scroll continu (puisqu'il n'y a plus aucun resize).
3. Cold-launch d'une nouvelle session (kill + relaunch) → les sections scrollées past lors de la session précédente apparaissent déjà en `FoldedSectionCard` au top du flux.
4. Tap sur folded card → ré-expansion locale (state-only, non persistée, comme avant).
5. La closing card « Vous êtes à jour » suit la même logique.

## Feature développée (21.1)

Six ajustements de la home Flux Continu V1.8 : auto-fold des sections scrollées en cartes-titre compactes (persisté par jour), hero « Explorer » qui sépare la zone éditoriale du feed continu, bascule sticky tab bar ↔ filter bar au passage du hero Explorer, Bonnes Nouvelles en dernière position (non-serein) ou en tête (serein), refinements visuels des heros (texte plus large, illustration plus discrète).

## Écrans impactés (21.1)

| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Flux Continu (home) | `/flux-continu` | Modifié |
| Feed (legacy) | `/feed` | **Non modifié** — vérifier non-régression |

## Scénarios de test (21.1)

### Scénario 1 : Scroll-past sans fold visible (V2.0)
**Parcours** :
1. Aller sur `/flux-continu` (cold launch — état initial)
2. **Scroll-down continu** rapide, puis un autre lent
3. Observer chaque hero éditorial au moment où il sort par le haut du viewport
4. Une fois en bas (closing card), scroller vers le haut pour revoir les heros

**Résultat attendu** :
- **AUCUN saut visuel**, aucun stutter pendant le scroll — il n'y a plus aucun resize en session
- Chaque hero **reste en taille plein-format** pendant toute la session (pas de fold automatique)
- En remontant vers le haut, les heros sont toujours expanded — pas de transition

### Scénario 1bis : Fold différé visible au prochain cold launch
**Parcours** :
1. Sur `/flux-continu`, scroll-down jusqu'à la closing card (toutes les sections passées au-dessus du viewport)
2. **Kill l'app** (ou hard refresh sur web)
3. Relancer / recharger
4. Observer l'état initial

**Résultat attendu** :
- Au top du flux, les sections scrollées-past lors de la session précédente apparaissent **directement en `FoldedSectionCard`** (~28 px chacune)
- La closing card scrollée-past apparaît également dismissée (cachée) si elle a été scrollée past
- DevTools localStorage : clé `flutter.flux_continu_folded_${YYYY-MM-DD}` contient la liste des sections persistées
- Tap sur une folded card → ré-expansion locale (session-only)

### Scénario 2 : Tap sur folded card = ré-expansion locale
**Parcours** :
1. Après scénario 1, scroll vers le haut pour revoir les folded cards
2. Tap sur une carte foldée (ex. Essentiel)

**Résultat attendu** :
- La carte se ré-expanse en hero complet (banner + cards + Plus de…)
- Pas de persistance : recharger la page (F5) la laisse foldée à nouveau

### Scénario 3 : Persistance par jour
**Parcours** :
1. Scroll past toutes les sections jusqu'à `flux_continu_folded` peuplé pour le jour
2. Recharger l'app (F5 / cold reload)
3. Observer l'état initial

**Résultat attendu** :
- Les sections scrollées avant le reload restent foldées
- DevTools localStorage : clé `flutter.flux_continu_folded_${YYYY-MM-DD}` contient une liste des noms des sections (`["essentiel", "theme1", ...]`)

### Scénario 4 : Hero Explorer
**Parcours** :
1. Aller sur `/flux-continu`, scroller jusqu'après la closing card « FIN DE TOURNÉE »
2. Observer le 5ᵉ hero « Explorer »

**Résultat attendu** :
- Banner plein-format, accent brun parchemin `#5D4037`
- Titre « Explorer », blurb « Tout ce qui est sorti aujourd'hui sur tes sources et tes sujets — à toi de fouiller, à ton rythme. »
- Illustration `facteur_bike.png` à droite (opacity 0.88, fadée à gauche)
- Pas d'onglet « Explorer » dans le sticky tab bar

### Scénario 5 : Bascule sticky tab bar ↔ filter bar
**Parcours** :
1. Sur `/flux-continu`, scroll progressif depuis le haut
2. Observer le sticky en haut au passage de chaque zone

**Résultat attendu** :
- En zone éditoriale (4 heros) : `StickyTabBar` visible avec 4 onglets + progress fill multi-stop
- Au moment où le hero Explorer atteint le top : cross-fade 120 ms vers `FeedFilterBar` (chips source + chips thème + bouton recherche)
- Aucune secousse, pas de blink, pas de bar qui disparaît
- Le backdrop parchemin reste cohérent (même teinte + blur)

### Scénario 6 : Bonnes Nouvelles en dernière position
**Parcours** :
1. Toggle serein OFF (état non-serein, par défaut)
2. Observer l'ordre des sections : Essentiel → Theme1 → Theme2 → **Bonnes Nouvelles**
3. Vérifier ordre des onglets dans `StickyTabBar` (même ordre)
4. Toggle serein ON
5. Observer l'ordre : **Bonnes Nouvelles** → Theme1 → Theme2 → Essentiel

**Résultat attendu** : ordre cohérent dans les sections **et** dans les tabs sticky.

### Scénario 7 : Refinements visuels heros
**Parcours** :
1. Aller sur `/flux-continu`
2. Comparer chaque hero (Essentiel, Bonnes, Theme1, Theme2) à la version précédente

**Résultat attendu** :
- Texte titre/blurb un peu plus large (factor 0.64 vs 0.58)
- Illustration plus petite (120 px vs 136 px) et plus discrète (opacity 0.88)
- Fade gauche plus net (stop 0.62 vs 0.55) — l'illustration sent moins « centrale »

### Scénario 8 : Non-régression FeedScreen
**Parcours** :
1. Aller sur `/feed`
2. Vérifier filter bar complète (search + chips + FavoriteTopicTabs)
3. Sélectionner un thème, taper une recherche

**Résultat attendu** : comportement identique à avant — la filter bar legacy n'a pas été touchée.

### Scénario 9 : Couplage Flux Continu ↔ favoris (finalisé)

> Refacto post-WIP V10 : `SectionKind` est string-keyed (`essentiel` / `bonnes` /
> `theme:<slug>` / `topic:<uuid>`), cap = 3 favoris, le provider écoute
> `userInterestsProvider` et ne refetch que les sections thèmes au reorder.

**9a — 0 favori (compte vierge sans backfill)**
1. SQL : vider `user_favorite_interests` pour le user de test.
2. Cold launch `/flux-continu`.

**Résultat attendu** :
- Sections : `[Essentiel, theme:tech, theme:environment, theme:science, Bonnes]`
  (3 thèmes canoniques de fallback, hors-backfill).
- `MyInterestsIntro` affiche « TES 3 THÈMES FAVORIS » + bouton GÉRER.

**9b — 1 favori « Tech »**
1. SQL : 1 row dans `user_favorite_interests` (interest_slug='tech', position=0).
2. Cold launch `/flux-continu`.

**Résultat attendu** :
- Sections : `[Essentiel, MyInterestsIntro("TON THÈME FAVORI"), theme:tech, Bonnes]`.
- Une seule section thème.

**9c — 3 favoris**
1. SQL : 3 rows dans `user_favorite_interests` (ex. tech / culture / climat).
2. Cold launch `/flux-continu`.

**Résultat attendu** :
- 3 sections thème consécutives dans l'ordre canonique du provider.
- Intro : « TES 3 THÈMES FAVORIS ».

**9d — 1 favori Sujet (custom topic)**
1. SQL : 1 row dans `user_favorite_interests` (custom_topic_id=<uuid d'un sujet user>).
2. Cold launch `/flux-continu`.

**Résultat attendu** :
- Une section thème dont le titre est le `topic_name` du sujet
  (ex. « IA & éducation »).
- Network : appel `GET /api/feed?topic=<uuid>&...` (PAS `theme=`).
- La section contient au moins 1 article filtré sur le slug_parent du sujet.

**9e — Reorder de favoris depuis MyInterestsScreen → flux continu refetch
sans tout réinitialiser**
1. État initial 3 favoris [tech, culture, climat]. Flux continu visible.
2. Sans quitter l'écran flux continu, ouvrir la sheet `MyInterestsSheet`,
   puis taper « Gérer mes intérêts » → push MyInterestsScreen.
3. Drag-reorder en [culture, tech, climat]. Pop retour flux continu.

**Résultat attendu** :
- Network : 3 appels `GET /api/feed?theme=<slug>` rejoués (un par favori),
  AUCUN appel `getBothDigests` ni `GET /api/feed?page=1&limit=20` (feed continu)
  → c'est le path `_refetchThemesOnly`.
- Les sections apparaissent dans le nouvel ordre [culture, tech, climat]
  sans réinitialisation du digest ni du feed continu.

**9f — SharedPreferences au format string-key**
1. Scroll past quelques sections.
2. DevTools → Application → Local Storage.

**Résultat attendu** :
- Clé `flutter.flux_continu_folded_<YYYY-MM-DD>` contient des entries
  format `["essentiel", "theme:tech", "topic:abc-uuid", "bonnes"]`.
- AUCUNE entrée `theme1` ou `theme2`.

**9g — Tolérance aux clés legacy au cold launch**
1. Injecter manuellement dans localStorage la clé
   `flutter.flux_continu_folded_<aujourd'hui>` avec valeur
   `["essentiel", "theme1", "theme2"]`.
2. Cold launch.

**Résultat attendu** :
- Pas de crash, pas d'erreur console.
- Seule `essentiel` est appliquée (les `theme1`/`theme2` sont silencieusement
  ignorées). Le purge journalier nettoiera la clé dans <24h.

## Critères d'acceptation (21.1)

- [ ] Sections **NE se foldent PAS** pendant la session active (V2.0 : fold différé)
- [ ] Tap sur folded card ré-expanse en local (state-only, non persistée)
- [ ] Cold launch nouveau jour : sections re-dépliées (clé `flux_continu_folded_<date>` purgée)
- [ ] Cold launch même jour après scroll-past : sections apparaissent déjà foldées
- [ ] Hero « Explorer » inséré entre closing et feed continu avec illustration bike
- [ ] Sticky cross-fade entre tab bar et filter bar au passage d'Explorer
- [ ] Mode non-serein : ordre `[Essentiel, themes…, Bonnes]` (0..3 sections thème)
- [ ] Mode serein : ordre `[Bonnes, themes…, Essentiel]`
- [ ] Refinements banner (text width, illustration size, opacity, fade stops)
- [ ] `flutter test test/features/flux_continu/` vert (49+ tests)
- [ ] `flutter analyze` sur fichiers touchés sans erreur
- [ ] `rg "SectionKind\\.(theme1|theme2)" apps/mobile/` → 0 résultat
- [ ] FeedScreen `/feed` fonctionne identique à avant
- [ ] Couplage Flux Continu ↔ favoris : sections lisent `userInterestsProvider.favorites`
- [ ] Favori Sujet (custom topic) déclenche `GET /api/feed?topic=<uuid>`
- [ ] Reorder favoris → seuls les `getFeed(theme/topic)` sont rejoués (économie digest + feed continu)
- [ ] SharedPreferences format string-key (`theme:slug` / `topic:uuid`), tolère silencieusement les clés legacy `theme1`/`theme2`

## Zones de risque (21.1)

- **Auto-fold idempotence** : `markScrolledPast` doit être idempotent (ne pas spammer SharedPreferences à chaque tick de scroll). Validé par la garde `if (current.folded[kind] == true) return`.
- **Sticky bascule** : si le user scroll vite, l'`AnimatedSwitcher` doit cross-fader proprement.
- **Filter bar dans FluxContinu** : `FeedFilterBar` drive `feedProvider` global. Les changements de filtre n'affectent **pas** le `feedContinu` rendu. Limitation connue, à valider en QA.
- **Persistance SharedPreferences (web)** : sur Flutter web, `SharedPreferences` est backé par `localStorage`. La clé apparaît avec un préfixe `flutter.`.
- **Couplage sections ↔ favoris** : si l'user a 0 favori (cas edge post-backfill), le provider tombe sur le fallback canonique `[tech, environment, science]` pour garantir une tournée non-vide.
- **Refacto SectionKind string-keyed** : les maps internes `folded` / `moreOpen` passent de `Map<SectionKind, bool>` à `Map<String, bool>` (clés `essentiel` / `bonnes` / `theme:<slug>` / `topic:<uuid>`). Hydratation tolérante aux anciennes clés `theme1`/`theme2` (ignorées au parse, purgées sous 24h par le purge journalier).

## Dépendances (21.1)

- Backend : aucun changement (`/api/digest/both`, `/api/users/top-themes`, `/api/feed` inchangés au strict). Le WIP V10 lit `user_favorite_interests` via les endpoints 22.1.
- Asset : `apps/mobile/assets/notifications/facteur_bike.png` + `facteur_veille.png` (présents dans les commits cherry-pickés)
- Package : `shared_preferences ^2.5.4` (déjà déclaré)
