 # Bug: header immersif lecture article

## Contexte

La page de lecture d'article doit afficher un header immersif avec une
transparence progressive et se superposer au haut du contenu.

## Probleme

- Le contenu est decale vers le bas, ce qui supprime l'effet d'overlay.
- Le degrade du header est trop abrupt, la transition manque de progressivite.

## Attendu

- Header opaque en haut, presque transparent en bas.
- Le header se superpose sur le haut de l'article pour masquer l'espace mort.

## Pistes techniques

- Ajuster le padding top dans `ContentDetailScreen`.
- Ajouter plusieurs stops de gradient pour une transition plus douce.

## Verification

- Ouvrir un article in-app et verifier l'effet de transparence progressive.
