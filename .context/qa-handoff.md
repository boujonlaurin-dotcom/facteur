# QA Handoff — Onboarding : polish du « cœur » sélection des sources

Branche : `boujonlaurin-dotcom/onboarding-source-selection-polish` (base `main`).
Backend non touché. Feature UI only.

## Écrans impactés

1. **Swipe de calibration** (`SwipeDisambiguatorQuestion`, Q9c)
2. **Page « Tes médias, sur mesure »** (`SourcesQuestion`, Q10)

## Setup

- Build web Flutter, viewport mobile **390x844**, sémantique activée au boot
  (cf. skill `facteur-qa-web`).
- Parcourir l'onboarding jusqu'au swipe (répondre thèmes/sujets pour avoir des
  groupes thématisés), puis continuer jusqu'à la page sur-mesure.

## Scénarios — Swipe (B)

- **En-tête dynamique (B.2)** : plus de titre statique « Quels médias suivre ? ».
  Un en-tête par **groupe** s'affiche (ex. « L'actu au quotidien »,
  « Des médias indépendants », « Pour aller au fond… », « Un autre point de
  vue », ou thématisé « Pour creuser Tech & Innovation… »). Il **change** quand
  on passe d'un bloc de cartes au suivant (transition douce).
  - Edge : l'ordre des blocs suit les prefs — répondre « médias spécialisés »
    (independent) doit mener avec indépendants/fond ; « grands médias »
    (established) avec références/grands médias.
- **Hint (B.1)** : sous la carte, texte renommé **« Touche pour ouvrir le
  média »** (visible sur la 1ʳᵉ carte, disparaît au 1ᵉʳ geste), rapproché du bas
  du deck.
- **Centrage (B.3)** : le deck est centré verticalement (plus d'espace mort en
  haut depuis la suppression du gros titre).
- **Undo (B.4)** : 3 boutons ronds sur une ligne — **undo discret (plus petit,
  gris) à gauche** de (X) et (♥). Invisible tant qu'aucun vote ; (X)/(♥) restent
  centrés (placeholder symétrique). L'undo de l'overlay final reste inchangé.

## Scénarios — Page sur-mesure (A)

- **Déjà ajoutés (A.1)** : en tête de la section 1, puces **discrètes** (libellé
  léger « Déjà ajoutés », logos ~18px), alimentées par les sources likées au
  swipe. Ces sources sont hors carrousel et déjà cochées.
- **Carrousels (A.2)** : sections 1 (suggestions) **et** 3 (catalogue) en
  **carrousel horizontal** (swipe latéral, ~1,2 carte visible, peek sur la
  suivante). Le filtre par thème (section 3) repart de la 1ʳᵉ carte.
- **Cartes (A.3/A.4)** : cartes portrait — logo + nom + pastille de biais en
  tête ; **aspects matchés** (tags : thème, « Spécialisé en X », « ≈ Similaire à
  … », fiable/anti-bruit/serein) mis en valeur au cœur ; cercle de sélection
  ≥44px ; tap carte → modale détail.

## Critères d'acceptation

- En-tête de swipe change visiblement entre groupes ; aucun em-dash.
- Carrousels fluides, peek visible ; sélection/desélection OK ; modale détail OK.
- Console sans erreurs ; pas de 4xx/5xx réseau inattendus.

## Vérifs déjà passées (dev)

- `flutter test test/features/onboarding` → **84 passed** (dont nouveaux tests
  `buildSpanningGroups` : ordre par prefs, libellé thème vs pôle, dégradation).
- `flutter analyze` sur les fichiers touchés → propre (seuls infos `withOpacity`
  pré-existantes, conformes au reste du code).

## Note hors-scope (à signaler)

`apps/mobile/assets/changelog.json` était **JSON invalide sur `main`** (deux
entrées `unreleased` fusionnées par un mauvais merge → parsing cassé). Réparé
dans cette PR + ajout de l'entrée « Onboarding » de la feature.
