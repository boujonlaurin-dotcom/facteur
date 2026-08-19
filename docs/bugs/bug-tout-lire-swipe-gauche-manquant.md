# Bug — Pages « Tout lire » : le swipe gauche (masquer) ne marche pas

## Symptôme (rapporté par le PO)

Dans l'onglet **L'Essentiel**, un clic sur **« Tout lire »** ouvre la page dédiée
d'une section avec la liste complète de ses articles. Sur cette page, l'utilisateur
peut **swiper à droite pour lire**, mais **pas swiper à gauche pour masquer** —
alors que le geste existe partout ailleurs (Tournée, Flâner) et fait partie de la
grammaire d'interaction de Facteur.

## Cause racine

Le geste bidirectionnel vit dans `SwipeToOpenCard`
(`apps/mobile/lib/features/feed/widgets/swipe_to_open_card.dart`) : le swipe
gauche n'est **actif que si `onSwipeDismiss != null`** (choix rétro-compatible
d'origine). `FluxContinuArticleCard` se contente de relayer ce callback.

- Tournée (`flux_continu_screen` → `SectionBlock`) et Flâner (`flaner_screen`)
  câblent `onSwipeDismiss` **et** toute la mécanique de feedback inline
  (`pendingFeedbackIds` → bandeau `FeedbackInline` en remplacement de la carte,
  `markHiddenRemote` / `confirmDismiss` / `undoHide`).
- Les pages dédiées « Tout lire » — `DigestSectionScreen`, `ThemeSectionScreen`,
  `SourceSectionScreen` — rendaient `FluxContinuArticleCard` **sans**
  `onSwipeDismiss`. Le swipe gauche y était donc simplement inerte.

## Correctif

Nouveau widget auto-porté
`apps/mobile/lib/features/flux_continu/widgets/dismissible_article_card.dart` :
`DismissibleArticleCard` enveloppe `FluxContinuArticleCard` et gère localement le
cycle **carte → bandeau `FeedbackInline` → carte retirée**, en réutilisant les
méthodes existantes de `FluxContinuNotifier` (`markHiddenRemote`,
`confirmDismiss`, `undoHide`) et le même bandeau que la Tournée / Flâner. Aucun
nouveau composant visuel, aucun nouveau token (design-system-first).

Pourquoi un widget auto-porté plutôt que le câblage `pendingFeedbackIds` remonté
à l'écran (pattern `SectionBlock`) : les trois pages rendent leurs listes depuis
trois sources différentes (feed du jour résolu, section paginée, curation d'une
source chargée localement). Un état local par carte donne le même comportement
sur les trois sans faire porter à chaque écran la mécanique pending/resolve.

Écrans câblés :

| Écran | Liste | `origin` analytics |
|---|---|---|
| `DigestSectionScreen` | leads des sujets (Actus du jour / Bonnes Nouvelles) | `section_digest` |
| `ThemeSectionScreen` | feed du thème | `section_theme` |
| `ThemeSectionScreen` (veille) | lignes veille | `section_veille` |
| `ThemeSectionScreen` (découverte) | « Explorer de nouvelles sources » | `section_theme_discovery` |
| `SourceSectionScreen` | curation complète de la source | `section_source` |

Chaque carte porte une `Key` dérivée du `contentId` : sans elle, l'état de
masquage se réaffecterait à l'article voisin quand la liste se resserre.

Hors scope (comportement inchangé) : les carrousels horizontaux (le swipe
horizontal y sert à la traversée) et la fiche source en modal.

Aucun changement backend → pas de migration Alembic.

## Tests

`apps/mobile/test/features/flux_continu/widgets/dismissible_article_card_test.dart`
— swipe droit ouvre, swipe gauche masque + affiche le bandeau, « Annuler »
restaure la carte, fermeture du bandeau purge l'article.

`flutter analyze` : aucun problème sur les fichiers touchés. Suite `flutter test`
complète : mêmes 33 échecs qu'avant le changement (pré-existants sur `main`,
goldens et écrans non liés), aucun nouveau.
