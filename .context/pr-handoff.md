# PR — Article Reader Layout Rework (story 5.9)

## Quoi

Refonte de la mise en page de l'écran de lecture in-app :
- Nouveau footer animé (slide comme le header) qui remplace les FABs flottants une fois que l'utilisateur atteint la section Perspectives ou la fin de l'article
- Section Perspectives embarquée inline dans le scroll view (nouveau widget `PerspectivesInlineSection`) avec filtre par biais cliquable et header sticky
- Barre de progression limitée à la longueur de l'article (exclut la section Perspectives)
- Utilitaire `cutHtmlAtPreview()` dans `html_utils.dart` pour couper du HTML à N mots

## Pourquoi

Les FABs flottants masquaient le contenu et offraient une mauvaise ergonomie en fin d'article. L'objectif est d'avoir un footer persistant et contextuel qui apparaît naturellement quand l'utilisateur a terminé sa lecture, et d'intégrer les Perspectives directement dans le flux de lecture plutôt qu'en bottom sheet.

## Fichiers modifiés

- **Mobile — core :**
  - `apps/mobile/lib/core/utils/html_utils.dart` — ajout de `cutHtmlAtPreview()` + `_findPositionAfterNWords()`

- **Mobile — detail :**
  - `apps/mobile/lib/features/detail/screens/content_detail_screen.dart` — footer animé, sticky header Perspectives, mesure de l'extent article, state Perspectives lifté au niveau écran
  - `apps/mobile/lib/features/detail/widgets/article_reader_widget.dart` — suppression du `SizedBox(height: 64)` superflu en fin de widget

- **Mobile — feed :**
  - `apps/mobile/lib/features/feed/widgets/perspectives_bottom_sheet.dart` — enum `PerspectivesAnalysisState` passé public, nouveau `PerspectivesInlineSection`, `PerspectivesTrianglePainter` public, filtre biais dans le bottom sheet

- **Mobile — onboarding :**
  - `digest_mode_question.dart`, `intro_screen.dart`, `media_concentration_screen.dart` — fix lint `const` sur les listes `TextSpan`

- **Docs :**
  - `docs/stories/core/5.9.article-reader-layout-rework.md` — story technique

## Zones à risque

- **`content_detail_screen.dart`** — fichier le plus critique et le plus large du projet mobile (~1 400 lignes). Deux `ScrollController` coexistent maintenant (`_scrollController` pour le mode scroll-to-site, `_inAppScrollController` pour le reader in-app). S'assurer qu'ils ne sont pas mélangés.
- **`_measureArticleExtent()`** — utilise `RenderBox.localToGlobal` post-frame. Si l'article n'est pas encore rendu (images lazy-loaded), l'extent peut être sous-estimé. Ce n'est pas bloquant (fallback sur `maxScrollExtent`) mais peut affecter la barre de progression.
- **`_footerAutoController`** — vérifier que `dispose()` l'inclut bien (memory leak sinon).
- **Renommage `_AnalysisState` → `PerspectivesAnalysisState`** — l'enum est maintenant public et partagé entre le bottom sheet et `content_detail_screen`. Casser ce contrat affecterait les deux.

## Points d'attention pour le reviewer

1. **Footer permanent** : `_footerPermanent = true` se déclenche dans deux endroits — `_checkIsShortArticle()` et `_checkAtPerspectivesSection()`. Vérifier absence de double-trigger ou race condition.
2. **Sticky header Perspectives** : calculé à chaque événement scroll via `_checkAtPerspectivesSection()`. L'algo utilise `_headerOffset.value` pour calculer la position réelle du header — vérifier que l'offset est cohérent avec la valeur animée courante.
3. **`PerspectivesInlineSection` — mode contrôlé vs autonome** : le widget supporte deux modes. En mode contrôlé (via `onSegmentTap`), le parent est propriétaire du filtre. L'écran de détail utilise ce mode pour synchroniser le sticky header — vérifier que `_onPerspectivesSegmentTap` dans le screen reflète la même logique que `_onSegmentTapInternal` dans le widget.
4. **Barre de progression** : `_articleContentExtent` est mesuré via `_measureArticleExtent()` après rendu. Si null, fallback sur `maxScrollExtent`. Vérifier que `_articleEndKey` est bien positionné dans le widget tree juste avant la section Perspectives.

## Ce qui N'A PAS changé (mais pourrait sembler affecté)

- **Mode scroll-to-site et WebView** : `_showWebView`, `_isWebViewActive`, `_scrollController` et `_webViewController` ne sont pas modifiés fonctionnellement. Le seul changement est `bool _showWebView = false` → `final bool _showWebView = false` (lint fix).
- **`PerspectivesBottomSheet`** (modal) : le comportement du bottom sheet existant est préservé. Le filtre biais a été ajouté mais ne change pas l'API publique du widget.
- **Onboarding** : les 3 fichiers ont uniquement un fix de lint (`const` hissé au niveau de la liste), aucun comportement ne change.

## Comment tester

1. **Footer slide** : ouvrir un article long en mode in-app → scroller jusqu'au bas → vérifier que le footer apparaît progressivement. Remonter → le footer suit le header (se cache en scrollant vers le bas, réapparaît vers le haut).
2. **Footer permanent** : scroller jusqu'à la section Perspectives → le footer doit rester visible même en remontant.
3. **Filtre biais inline** : tapper sur un segment de la barre de biais → seuls les articles du groupe sélectionné s'affichent. Tapper à nouveau → reset. Vérifier que le sticky header reflète le filtre actif.
4. **Sticky header Perspectives** : scroller au-delà du titre "Voir tous les points de vue" → un mini-header doit apparaître dans l'app header. Rescroller vers le haut → il disparaît.
5. **Barre de progression** : vérifier que la barre atteint 100% à la fin de l'article, pas en milieu de la section Perspectives.
6. **Article court** : le footer doit être immédiatement visible (sans nécessiter de scroll).
7. `flutter analyze` doit passer sans nouveaux warnings.
