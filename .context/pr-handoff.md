# PR — Story 10.27 : Cartes éditoriales (badges sémantiques, ArticlePairView, Pépite/Coup de cœur)

## Quoi
Implémentation de la couche visuelle éditorialisée pour les digests `editorial_v1`. Les cartes affichent maintenant des badges sémantiques (actu/pas_de_recul/pépite/coup de cœur) au lieu du badge reason algorithmique, le rank badge circulaire est masqué en mode éditorial, et deux nouveaux blocs encadrent pépite et coup de cœur.

## Pourquoi
Story 10.26 avait posé le layout éditorial (header, introText, transitionText, dots). Il manquait l'éditorialisation des cartes elles-mêmes. Le backend ne peuple pas encore le champ `badge` — tout est implémenté avec fallback `null` (rétrocompatibilité totale).

## Fichiers modifiés
**Mobile :**
- `digest/widgets/digest_card.dart` — D4 (badge sémantique) + D5 (rank badge conditionnel)
- `digest/widgets/topic_section.dart` — N3 (editorialMode : DigestCard au lieu de FeedCard, header simplifié)
- `digest/widgets/digest_briefing_section.dart` — N5c (editorial layout method, nouveaux params pepite/coupDeCoeur)
- `digest/screens/digest_screen.dart` — N5d (wiring usesEditorial/pepite/coupDeCoeur)

**Nouveaux fichiers :**
- `digest/widgets/pepite_block.dart` — N5a
- `digest/widgets/coup_de_coeur_block.dart` — N5b

## Zones à risque
- **`digest_card.dart`** : le conditionnel `if (item.badge == null)` sur le rank badge — s'assurer que les formats `flat_v1` et `topics_v1` n'ont pas de `badge` peuplé côté backend (sinon le rank badge disparaît)
- **`topic_section.dart`** : `_editorialBodyFooterHeight = 210.0` est une estimation pour le calcul de hauteur du PageView. Si DigestCard est plus haute qu'estimé, les cartes seront tronquées en bas. À valider visuellement.
- **`_handleDigestCardAction`** dans `topic_section.dart` : mapping des action strings vers les callbacks. Le case `'read'` appelle `onArticleTap` — vérifier que c'est cohérent avec `ArticleActionBar`.

## Points d'attention pour le reviewer
1. **Rétrocompatibilité** : `flat_v1` et `topics_v1` ne passent jamais par `_buildEditorialLayout()` (guard `widget.usesEditorial && _usesTopics`). `DigestCard` avec `item.badge == null` se comporte exactement comme avant.
2. **Conversion PepiteResponse/CoupDeCoeurResponse → DigestItem** : les helpers dans `pepite_block.dart` et `coup_de_coeur_block.dart` passent uniquement les champs disponibles. Le `reason` de DigestItem a un `@Default('')` donc pas de crash, mais le fallback reason badge affichera "" → "Environnement" — non visible car `badge` est toujours non-null pour ces items.
3. **`_withEditorialBadge`** dans `topic_section.dart` : assign badge par index (0 = actu, 1+ = pas_de_recul) uniquement si `article.badge == null`. Quand le backend peuplera ce champ, l'assignation par index sera skippée automatiquement.
4. **Mode serein** : la logique emoji est dans `DigestCard._buildBadge()`. La valeur `isSerene` est passée via chain de params (digest_screen → DigestBriefingSection → TopicSection → DigestCard), pas via provider.

## Ce qui N'A PAS changé (mais pourrait sembler affecté)
- `_buildTopicsLayout()` dans `digest_briefing_section.dart` : inchangé, `editorialMode: false` implicite
- Le dismiss flow (DismissBanner, SwipeToOpenCard) : conservé en editorial mode dans `_buildSingleArticle`
- `ArticleActionBar` : non modifié, toujours appelé via `onAction` dans DigestCard
- Aucun test widget ne couvre ces widgets dans le repo — pas de risque de régression test

## Comment tester
1. **flat_v1 / topics_v1 inchangés** :
   - Ouvrir un digest non-éditorial → vérifier rank badge visible, reason badge présent
2. **editorial_v1 badges** :
   - `editorial_enabled: true` dans `packages/api/config/editorial_config.yaml` (déjà activé en dev local)
   - Badge "🔴 L'actu du jour" sur première carte de chaque topic
   - Badge "🔭 Le pas de recul" sur deuxième carte (si deep article présent)
   - Absence du cercle rank (#1, #2) en top-left des cartes
3. **Mode serein** : switcher en mode Serein → badges actu/pas_de_recul sans emoji
4. **Pépite & Coup de cœur** : blocs visibles uniquement si le backend renvoie `pepite`/`coup_de_coeur` dans la réponse `editorial_v1` — à connecter quand le backend peuplera ces champs
5. `flutter analyze` — 0 nouvelles erreurs (vérifié)
