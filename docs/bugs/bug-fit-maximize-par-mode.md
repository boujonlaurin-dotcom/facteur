# Bug — Le nombre d'articles par section ne maximise pas l'écran selon le mode

## Symptôme

Sur **L'Essentiel** (Flux Continu), chaque section devrait remplir tout l'espace
vertical disponible **sans le dépasser** (pour rester « snap-able » carte par
carte). En pratique :

- **Normal** restait bloqué au compte nominal backend (≈3) même quand 4 cartes
  tenaient → de l'espace vide en bas de section.
- **Lisible** (ludique) n'affichait souvent qu'**1 carte** par section, loin de
  la cible 2-3.
- Seul **Minimaliste** grandissait (plafond 7).

Le nombre d'articles n'était donc **pas différencié** selon le mode comme voulu :
Minimaliste 4-6, Normal 3-4, Lisible 2-3.

## Cause racine

`_capSectionToFit` (`flux_continu_provider.dart`) bornait le fit avec
`maxCount` :

```dart
final ceiling = spec.sectionFitCeiling;
final maxCount = ceiling == null
    ? s.coreVisibleCount                       // Normal & Lisible : nominal
    : math.max(s.coreVisibleCount, math.min(ceiling, s.totalCount));
```

- Normal & Lisible avaient `sectionFitCeiling == null` ⇒ plafond = nominal
  backend ⇒ ces modes ne pouvaient que **rétrécir**, jamais grandir.
- Même avec un plafond, le `max(nominal, …)` empêchait de **descendre** sous le
  nominal (problématique pour Lisible qui doit capper à 3).

Côté physique, la carte Lisible faisait ~312px (image fixe **170px** en haut) :
sur un téléphone normal (~600px utiles sous le bandeau) une seule carte tenait.

## Correctif

1. **Chaque mode porte son plafond** (`DisplayModeSpec.sectionFitCeiling`) :
   Normal `4`, Minimaliste `6` (était 7), Lisible `3`.
2. **`maxCount` découplé du nominal backend** — le fit peut monter **ou**
   descendre jusqu'à `min(ceiling, totalCount)` pour remplir l'écran selon le
   mode :
   ```dart
   final maxCount = ceiling == null
       ? s.coreVisibleCount
       : math.max(1, math.min(ceiling, s.totalCount));
   ```
   **Plancher dur `minCount = min(2, totalCount)`** : **jamais 1 seul article**
   dès qu'au moins 2 sont disponibles, même en Lisible sur un petit écran (la 2e
   carte peut alors légèrement déborder — c'est préféré à une section à 1 carte).
   **Footer exclu du budget** (`footerHeight: 0`) : le gap de fin de section
   glisse hors écran au scroll, il ne doit pas coûter une carte.
3. **Carte Lisible raccourcie** : `regularImageHeight` 170 → **130** (donc
   `regularCardHeight` 312 → **272**) pour que 2-3 cartes tiennent sans
   débordement. L'image reste l'élément dominant (« image-forward »). La carte
   lit `spec.regularImageHeight` au rendu → l'estimation de fit et le rendu réel
   restent cohérents par construction.

### Plages obtenues (chrome = bandeau seul, ≈ 68px no-blurb ; footer exclu)

| Mode | Carte | Téléphone normal | Plancher | Plafond |
|------|-------|------------------|----------|---------|
| Minimaliste | 126px | 4 → 5 | 2 | 6 |
| Normal | 146px | 3 → 4 | 2 | 4 |
| Lisible | 272px | 2 → 3 (écran haut) | 2 | 3 |

Petit écran (iPhone SE, ~460px utiles) : **toujours ≥2 cartes** (plancher dur) —
la 2e Lisible peut déborder un peu, ce qui est préféré à une section à 1 carte.

## Correctif 2 — fit mode-aveugle au fallback (débordement Lisible / sous-remplissage Minimaliste)

### Symptôme

- Lisible : « Actus du jour » affichait **3 cartes** (dont 2 images) qui
  débordaient complètement un écran ~750px.
- Minimaliste : sections figées à **3** malgré l'espace et des articles dispo.

### Cause

Les deux = **3 = compte nominal backend** : le fit ne s'appliquait pas.
`_capSectionsToFit` retombait sur le **nominal mode-aveugle** dès que la hauteur
utile était nulle (1er frame) ou implausiblement petite. Or l'écran
(`_publishUsableHeight`) publiait **toute** hauteur > 0, y compris les mesures
transitoires/aberrantes (render box détachée lors d'un changement de mode), qui
empoisonnaient `usableViewportHeightProvider` et figeaient l'état au nominal —
nominal 3 qui **déborde** en Lisible (3×272) et **sous-remplit** en Minimaliste.

### Correctif

1. **Fallback mode-aware** : quand la hauteur est nulle/implausible, on cape
   quand même selon le mode sur une **hauteur de référence**
   (`kReferenceUsableHeight = 640`) au lieu du nominal mode-aveugle → Normal 3 /
   Minimaliste 4 / Lisible 2, affinés dès la 1ʳᵉ vraie mesure.
2. **Rejet à la source** : `_publishUsableHeight` ignore les mesures
   `< kMinPlausibleUsableHeight` (360) → une transitoire n'écrase plus la
   dernière bonne hauteur, le provider reste sur une mesure fiable (plus de
   bascule au fallback ni de flash de débordement au switch de mode).

## Tests

- `section_fit_test.dart` : plafonds par mode (4/6/3) + montée du fit jusqu'au
  plafond pour Normal, Minimaliste et Lisible.
- `flux_continu_provider_test.dart` : Normal monte à 4 sur écran haut ; Lisible
  capé à 2 ; never-1 sur petit écran ; fallback mode-aware sur la référence 640
  quand la hauteur est nulle/implausible (plus jamais le nominal mode-aveugle).
- `flux_continu_article_card_playful_test.dart` : slot image Lisible = 130px.
- Helpers de conteneur des suites provider (`makeContainer`, `makeDedupContainer`,
  `buildContainer` sources/tournée) overrident `displayModeSpecProvider` : le cap
  lit désormais le spec même sans mesure (box Hive `settings` non ouverte).
