
# Plan d'implementation - Header immersif lecture article

## Objectif

Retablir le header immersif dans la page de lecture avec une transparence
progressive et une superposition reelle sur le haut du contenu.

## Hypotheses

- Le padding top fixe (80) sur le contenu empêche la superposition du header.
- Le degrade actuel est binaire (opaque -> transparent) et trop abrupt.

## Etapes

1. **UI**: Ajuster le padding top du contenu pour permettre l'overlay.
2. **UI**: Raffiner le degrade du header avec plusieurs stops et une
   transparence "presque" nulle en bas.
3. **Validation**: Verifier la lisibilite du header et la reduction de
   l'espace mort sur un article.
4. **Documentation**: Ajouter un bug doc et un script de verification.

## Test rapide

- Ouvrir un article in-app et verifier l'effet de superposition du header.
