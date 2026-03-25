# Handoff: Digest Carousel Card Sizing & Spacing Fix

## Branch: `boujonlaurin-dotcom/digest-carousel-fix`

## Contexte
L'utilisateur veut que le carrousel digest ait des cartes de taille uniforme (hauteur = celle d'une carte avec image) et zéro espace mort entre le bas du carrousel et les page indicator dots.

## État actuel — ce qui a déjà été fait (partiellement)
1. `topic_section.dart:117` — `imageHeight` est toujours calculé (même sans images) ✅
2. `feed_card.dart:73` — `Stack(fit: StackFit.expand)` quand `expandContent = true` ✅
3. `feed_card.dart:404-468` — `_buildBody` affiche description + Spacer quand `expandContent = true` ✅
4. `onboarding_screen.dart:70` — bouton skip toujours visible ✅

## 3 problèmes restants (avec root causes identifiées)

### Problème 1 — Carte sans description visible (alors qu'elle en a une)
**Symptôme** : Capture 1 montre une carte "La guerre en Iran ne fait pas les affaires du luxe" avec juste le titre + footer. Aucune description. La carte est courte.

**Root cause** : Le check `hasImage` dans `topic_section.dart:388-389` est :
```dart
final hasImage = article.thumbnailUrl != null && article.thumbnailUrl!.isNotEmpty;
```
Si l'article a un `thumbnailUrl` non-null (ex: URL cassée ou image 404), `hasImage = true` → `expandContent = false` → pas de description affichée. Puis `FacteurThumbnail` (`facteur_thumbnail.dart:43-44`) détecte l'erreur de chargement et retourne `SizedBox.shrink()`. Résultat : la carte est minuscule, sans image ET sans description.

**Fix requis** : `expandContent` doit TOUJOURS être `true` dans le contexte du digest carousel. Toutes les cartes doivent remplir la hauteur uniforme. L'image (si présente) occupe le haut ; la description remplit l'espace restant. Concrètement :
- Dans `_buildPageView` et `_buildSingleArticleFixedHeight` de `topic_section.dart`, passer `expandContent: true` pour TOUTES les cartes (supprimer le conditionnel `!hasImage`)
- Dans `FeedCard._buildBody` (`feed_card.dart:406`), la condition `showDescription` pour `expandContent = true` est déjà correcte (affiche si description non null)

### Problème 2 — Grand bloc vide sous la description dans la carte
**Symptôme** : Capture 2 montre la carte "Guerre d'Iran : la démission de l'Europe" avec description visible, mais un énorme espace vide entre la description et le footer.

**Root cause** : Dans `feed_card.dart:444`, il y a un `Spacer()` inconditionnel quand `expandContent = true` :
```dart
if (expandContent) const Spacer(),
```
Ce Spacer pousse le footer (metadata row avec icône type + durée) tout en bas du body Expanded, créant un vide visuel énorme entre la description et les métadonnées.

**Fix requis** : Supprimer le `Spacer()` (`feed_card.dart:444`). Sans le Spacer, le body content (titre + description + meta) s'aligne naturellement en haut de l'Expanded widget. Le footer bar (source + actions) reste en bas de la carte grâce à la Column parent avec `mainAxisSize: max`. Résultat visuel : titre → description → meta → espace vide → footer bar avec border-top. C'est visuellement correct.

### Problème 3 — Espace entre le bas du carrousel et les page indicator dots
**Symptôme** : Grand gap vertical entre le bas de la carte la plus basse et les dots de pagination.

**Root cause** : Le `SizedBox(height: computedHeight)` dans `topic_section.dart:122-123` réserve la hauteur max (image + body + footer ≈ 360px). Si les cartes ne remplissent pas cette hauteur (car expandContent ne fonctionne pas — Problème 1), il reste un espace vide DANS le SizedBox. Puis 8px de `SizedBox(height: 8)` avant les dots (`topic_section.dart:135`).

**Fix requis** : Une fois les Problèmes 1 et 2 résolus (toutes les cartes remplissent la hauteur via `StackFit.expand` + `expandContent: true`), ce problème se résoudra largement. Les cartes occuperont tout le `computedHeight`. L'espace résiduel sera juste les 8px de séparateur. Si l'utilisateur veut encore moins d'espace, réduire le `SizedBox(height: 8)` à `SizedBox(height: 4)` (`topic_section.dart:135`).

## Fichiers à modifier

| Fichier | Lignes | Modification |
|---------|--------|-------------|
| `apps/mobile/lib/features/digest/widgets/topic_section.dart` | 388-393 | `expandContent: true` dans `_buildPageView` (supprimer `!hasImage`) |
| `apps/mobile/lib/features/digest/widgets/topic_section.dart` | 312 | `expandContent: true` dans `_buildSingleArticleFixedHeight` (supprimer `!hasImage`) |
| `apps/mobile/lib/features/feed/widgets/feed_card.dart` | 444 | Supprimer `if (expandContent) const Spacer()` |
| `apps/mobile/lib/features/digest/widgets/topic_section.dart` | 135 | Optionnel : réduire SizedBox(height: 8) → 4 |

## Détails d'implémentation : FeedCard avec expandContent=true + image présente

Quand `expandContent = true` ET que l'image existe (FacteurThumbnail rend l'AspectRatio) :
- L'image occupe sa hauteur naturelle (cardWidth / 16×9)
- Le body (Expanded) prend le reste : titre + description (courte, 2-3 lignes max vu l'espace réduit) + meta
- Le footer bar est en bas de la carte

Quand `expandContent = true` ET PAS d'image (FacteurThumbnail → SizedBox.shrink) :
- Tout l'espace va au body : titre complet + description longue (8 lignes max) + meta
- Le footer bar est en bas de la carte
- Le `StackFit.expand` (déjà en place dans `feed_card.dart:73`) assure que la carte remplit la hauteur parent

## Points d'attention pour le prochain agent

1. **Ne PAS modifier FacteurThumbnail** — son comportement collapse-on-error est correct pour le feed standard
2. **Le `Align(alignment: Alignment.topCenter)` pour les cartes avec image** (`topic_section.dart:415-416`) peut rester ou être retiré — avec `expandContent: true` partout et `StackFit.expand`, toutes les cartes rempliront la hauteur quoi qu'il arrive
3. **Tester avec des articles variés** : image OK, image cassée (thumbnailUrl non-null mais 404), pas d'image, description longue, description courte, pas de description
4. **Le `_bodyFooterHeight = 175.0`** (`topic_section.dart:81`) est calibré pour les cartes avec image. Pour les cartes texte-seul, cette valeur est suffisante car le titre + description + meta remplissent l'espace disponible grâce à Expanded

## Comment tester
```bash
cd apps/mobile
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080/api/
```
- Le bouton X en haut à droite de l'onboarding permet de le skip
- Vérifier que TOUTES les cartes du carrousel font la même hauteur
- Vérifier que les cartes sans image affichent la description
- Vérifier que l'espace entre le bas du carrousel et les dots est minimal (~4-8px)
- Vérifier que les cartes avec image ne sont pas coupées/cassées

## Captures de référence (disponibles dans /tmp/attachments/)
- `image-v36.png` — Carte 1 sans description (bug)
- `image-v38.png` — Carte 2 avec espace vide sous description (bug)
- `image-v39.png` — Carte avec image, gap avec les dots (bug)
