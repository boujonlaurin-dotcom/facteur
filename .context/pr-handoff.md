# feat(recherche): recherche universelle — sources · sujets · thèmes · articles (story 30.1)

Story 30.1, base `main`. La loupe du 2ᵉ onglet ne savait chercher qu'une chose : un
mot dans un titre d'article, parmi les seules sources suivies. Elle devient un **point
d'entrée de navigation** : trouver une source, un sujet, un thème ou un article — et,
quand ce qu'on cherche n'existe pas encore dans le compte, enchaîner sans friction sur
l'**ajout de source**. **Aucun changement backend, aucune migration.**

## Ce qui n'allait pas (constaté dans le code)

| Constat | Fichier |
|---|---|
| La sheet n'affichait **rien pendant la frappe** (`if (!hasQuery)` gardait tout le contenu) | `search_filter_sheet.dart` |
| La recherche ne renvoyait **que des articles** — `title ILIKE %q%` | `filter_presets.py:368` |
| Aucune recherche de source / sujet / thème, alors que les 3 filtres existaient déjà | `feed_provider.dart` |
| **Zéro résultat → écran blanc.** `EmptyFilterState` existait mais n'était jamais monté | `empty_filter_state.dart` |
| `CompactSearchChip` : code mort, aucune référence | `compact_search_chip.dart` |
| `includeUnfollowed` n'était activable que depuis une chip « sujet du moment » | `feed_filter_bar.dart` |
| Aucun événement analytics sur la recherche | `analytics_service.dart` |

## A. Recherche multi-entités (100 % locale)

- `utils/search_matcher.dart` — primitives pures : `foldForSearch` (casse + accents FR,
  longueur préservée), `matchQuality` (exact > prefix > wordPrefix > contains),
  `rankMatches` (tri déterministe : qualité, puis libellé le plus court, puis alpha),
  `looksLikeSourceQuery` (URL / domaine collé).
- `utils/search_results_builder.dart` — `buildSearchSections` compose 5 sections à partir
  de données **déjà en mémoire** (`userSourcesProvider` porte tout le catalogue avec les
  drapeaux `isTrusted` / `isMuted`) : `Articles`, `Tes sources`, `Sujets suivis`, `Thèmes`,
  `Ajouter une source`. **Aucun appel réseau pendant la frappe** (debounce 180 ms).
- **Ordre adaptatif** : un match exact sur une source, ou un domaine saisi, remonte les
  sections source devant `Articles` — taper « Mediapart » est une intention source, pas une
  intention mot-clé.
- `models/search_result.dart` — sealed class des 5 natures de résultat ; chacune mappe sur
  un geste déjà supporté par `FeedNotifier`.

## B. Le pont vers l'ajout de source

- **Source du catalogue non suivie** → bouton **Ajouter** inline : `trustSource()` puis
  filtre immédiat sur la source, sans quitter la sheet ni écran intermédiaire. Les sources
  en **sourdine** sont exclues (les re-proposer contredirait un choix explicite).
- **Source inconnue** → `AddSourceScreen` avec la recherche intelligente **déjà lancée** :
  nouveau paramètre `initialQuery` sur `SourceAddPanel`, propagé par l'écran et lu depuis
  `state.extra` dans `routes.dart`. Pas de re-saisie.

## C. L'état vide de Flâner

`EmptyFilterState` (code mort) est ressuscité, doté d'une variante mot-clé et **monté** dans
`flaner_screen.dart` quand la liste est vide et qu'un filtre est actif. Rattrapages, du moins
au plus engageant : élargir · ajouter la source · suivre le sujet · revenir au feed. La carte
`FollowKeywordSuggestionCard` est masquée dans ce cas (doublon avec « suivre ce sujet »).

## D. Élargir la recherche

- Bandeau « N résultats dans tes sources → **Élargir** » quand un mot-clé ramène 1 à 4
  articles.
- `includeUnfollowed` **déplacé dans `FeedFilterSelection`** : `setKeyword(q,
  includeUnfollowed: true)` avec le même mot-clé ne changeait pas la sélection, donc l'UI ne
  se redessinait pas (`==` ignorait le périmètre). `_restoreFiltersFromSelection` le restaure
  désormais au lieu de le remettre à `false` — ce qui rétrécissait silencieusement une
  recherche élargie après un rebuild du notifier.
- La pill de la barre de filtres affiche « mot-clé · toutes sources » quand le périmètre est
  élargi.

## E. Découvrabilité (décision PO : header partagé)

- Loupe 40 px dans `_SharedTopHeader` (`main_shell.dart`), à gauche de l'avatar : présente
  sur les **deux** onglets, hors de la zone filtre. Teinte accent quand une recherche est
  active.
- Depuis L'Essentiel, valider une recherche **bascule sur Flâner** avec le filtre appliqué.
- Le trigger de la barre de filtres est rétrogradé en **affichage d'état** : la pill
  « 🔍 mot-clé ✕ » quand une recherche est active, **rien** sinon (au lieu d'occuper 34 px en
  permanence pour une loupe redondante).
- Suppression de `compact_search_chip.dart` (code mort).

## F. Instrumentation

`search_opened` · `search_result_selected` (type + rang) · `search_submitted_empty` ·
`search_add_source_bridged` · `search_broadened`. Le funnel visé : ouverture → sélection
(succès) vs impasse → rattrapage. `search_submitted_empty` est dédupliqué par signature
`mot-clé|périmètre` (l'état vide est reconstruit à chaque rebuild du sliver).

## Vérification

- `flutter analyze` : **0 erreur**, aucun nouveau warning sur les fichiers touchés.
- **47 nouveaux tests, tous verts** : 17 matcher · 13 builder · 5 état vide · 9 sheet ·
  3 pont ajout de source.
- Suite complète : **1740 passants / 33 échecs, tous préexistants** — vérifié en rejouant les
  mêmes fichiers sur `main` sans le diff (mêmes 33 : stubs `fail('Test not implemented')` de
  `feed_sources_test.dart`, goldens `ring_avatar`, `widget_test.dart`…).
- Pas d'E2E Playwright : le build web n'a pas été exercé dans cet environnement.
  QA handoff prêt dans `.context/qa-handoff.md` (10 scénarios) pour `/validate-feature`.
