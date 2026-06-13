# Bug — Mode minimaliste : 1 seule carte par section dans l'Essentiel

## Symptôme

En mode d'affichage **Minimaliste**, chaque section du feed Essentiel (Flux
Continu) n'affiche plus qu'**un seul article**, au lieu du compte nominal
(3, voire plus puisque le minimaliste peut monter jusqu'à son plafond de 6).

## Cause racine

Le nombre de cartes par section est décidé uniquement par `_capSectionToFit`
(`flux_continu_provider.dart`) via `fitVisibleCount` (`section_fit.dart`), à
partir de la hauteur utile mesurée (`usableViewportHeightProvider`).

L'arithmétique du fit ne peut faire afficher au minimaliste **que ≥** ce
qu'affiche le mode normal à viewport égal (carte estimée 126px contre 146,
plafond plus haut). Un « 1 par section » n'est donc possible que si la hauteur
utile transmise à l'estimateur est **anormalement petite** (≤ ~240px) : à cette
valeur, `fitVisibleCount` plancher chaque section à 1 (cf. le test existant
`minimalFit(300) == 1`).

Une telle hauteur provient d'une **mesure transitoire / aberrante** : render box
détachée ou recompose hors-écran déclenchée par le changement de mode
d'affichage (le provider lit `usableViewportHeightProvider` au moment du
preview/commit, avant qu'une mesure fiable du nouveau layout n'arrive).

## Correctif

1. `_publishUsableHeight` ignore désormais toute hauteur utile sous un
   **plancher de plausibilité** (`kMinPlausibleUsableHeight = 360`, bien en
   dessous des ~480px utiles du plus petit téléphone). Une mesure transitoire
   n'écrase donc plus la dernière mesure fiable.
2. Si aucune mesure fiable n'est encore disponible, `_capSectionsToFit`
   applique un cap **dépendant du mode** sur une hauteur de référence
   (`kReferenceUsableHeight = 640`) au lieu de retomber sur le compte nominal
   backend : Normal 3, Minimaliste 4, Lisible 2.
3. Le fit impose un plancher dur de 2 articles dès qu'au moins 2 sont
   disponibles, afin qu'une section ne retombe jamais à une seule carte.

Le fit réel reprend dès qu'une hauteur plausible est publiée.

## Tests

- `flux_continu_provider_test.dart` : hauteur nulle ou implausible → fallback
  mode-aware sur 640 ; petit écran → jamais moins de 2 articles.
- `makeFitContainer` override désormais `displayModeSpecProvider` (la box Hive
  `settings` n'est pas ouverte dans la suite) pour tester chaque mode sans
  dépendance à Hive.
