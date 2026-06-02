# QA Handoff — Allègement Couverture médiatique

## Feature développée

Allègement visuel de la section inline « Couverture médiatique » dans le reader
article : état vide plus discret, badge de polarisation, explication du
surlignage derrière un bouton info, analyse remontée, disclaimer Mistral Large,
suppression du bloc « CET ARTICLE », et wash du pivot sur le titre de l'article.

## PR associée

Non créée.

## Écrans impactés

| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Reader article | Détail contenu interne | Modifié |
| Reader article alternatif | Second path de rendu détail contenu | Modifié |
| Bottom sheet perspectives | Couverture médiatique | Modifié via zone analyse partagée |

## Scénarios de test

### Scénario 1 : État vide
**Parcours** :
1. Ouvrir un article dont l'API perspectives ne renvoie aucune autre source.
2. Observer la section « Couverture médiatique (0) ».
**Résultat attendu** : le placeholder est discret, sans dividers pleine largeur
au-dessus/en dessous, avec texte plus petit et atténué, sans caret ni spectrum.

### Scénario 2 : Section ouverte avec perspectives
**Parcours** :
1. Ouvrir un article avec plusieurs perspectives.
2. Déplier « Couverture médiatique ».
3. Observer le haut de la section.
**Résultat attendu** : la balise polarisation apparaît si niveau `medium` ou
`high`, le bouton info ouvre le texte de surlignage, l'analyse est au-dessus des
titres variants, et le bloc « CET ARTICLE » n'apparaît plus.

### Scénario 3 : Analyse Facteur
**Parcours** :
1. Dans une section ouverte, lancer ou afficher l'analyse Facteur.
2. Lire la mention sous l'analyse.
**Résultat attendu** : la mention affiche « Analyse générée par Mistral Large ·
l'IA peut faire des erreurs. ».

### Scénario 4 : Wash pivot titre reader
**Parcours** :
1. Ouvrir un article avec `reference_pivot`.
2. Déplier la section « Couverture médiatique ».
**Résultat attendu** : le pivot du titre de l'article reçoit un wash gris léger à
l'ouverture, sans ajouter de bloc référence dans la section.

## Critères d'acceptation

- [ ] État vide nettement moins chargé.
- [ ] Section ouverte hiérarchisée : badge/info puis analyse puis variantes.
- [ ] Disclaimer IA visible sous l'analyse.
- [ ] Aucun rendu « CET ARTICLE ».
- [ ] Wash pivot visible sur le titre du reader à l'ouverture.
- [ ] Console sans erreur et pas de 4xx/5xx perspectives inattendus.

## Zones de risque

- Les deux chemins de rendu du reader doivent rester cohérents.
- Le bouton info doit rester tappable en viewport mobile 390x844.
- Le titre reader ne doit pas changer de hauteur de façon visible au moment du
  wash.

## Dépendances

Pas de changement backend. Le wash dépend du champ API existant
`reference_pivot`.
