feat(flux-continu): ajustements UX de L'Essentiel (carte perso, Grille, titres, thèmes Flâner, caps)

## Quoi

Cinq frictions UX corrigées sur la page **L'Essentiel** (Flux Continu) et sa modal
« Mes favoris », sans toucher au backend ni à la physique du snap.

- **1 — Carte de perso dédiée (compte non personnalisé).** Tant que la Tournée
  n'a pas été personnalisée (`!tournee.customized`), une **grande carte**
  « Personnalise ton Essentiel » (illustration `facteur_reparation_velo.png` +
  bouton « Composer ma Tournée ») s'affiche juste après le hero, dans son propre
  bloc de snap. Nouveau widget `PersonalisationCtaCard`.
- **2 — Inline lié au snap (compte personnalisé).** Une fois personnalisé, la
  carte cède la place à l'inline discret `MyInterestsIntro` (« Gérer / Tes N
  favoris »), désormais **embarqué DANS le `KeyedSubtree`** de la 1ʳᵉ section de
  contenu après le hero → il fait partie du bloc de snap de cette section et
  n'est plus « sauté » entre deux blocs. Les deux s'excluent.
- **3 — Grille collée aux Actus + titres de sections clairs.** Dans la modal :
  sections renommées **« BLOCS DE TA PAGE L'ESSENTIEL »** et **« ONGLETS DE TA
  PAGE FLÂNER »** ; « Actus & Mot du jour » présent ; « La Grille du jour »
  n'est plus un bloc drag&drop.
- **4 — Thèmes livrables en onglet Flâner (modèle exclusif, miroir des sources).**
  Un thème peut être déplacé Essentiel ⇄ Flâner. La clé `theme:<slug>` est
  partagée entre `tournee_order_v1` (Essentiel) et `pinned_tabs_order_v1`
  (Flâner) : présent dans Flâner ⇒ rendu en onglet **et** exclu des sections
  Essentiel ; absent ⇒ reste côté Essentiel. La favorite reste un
  `ThemeFavoriteRef` (pas de `setInterestState`).
- **5 — Caps affichés entre parenthèses.** « Hors Tournée du jour (5) » et
  « Hors onglets (10) ».

## Pourquoi

Décision PO (5 juin 2026) : lever 5 frictions UX repérées sur L'Essentiel —
notamment l'inline favoris « subi » au snap et l'absence d'invitation claire à
personnaliser pour les nouveaux comptes.

## Comment c'est construit (anti-duplication)

- **Un seul point de filtre** pour le modèle exclusif thèmes :
  `_tourneeSectionByKey()` écarte les clés `theme:` présentes dans
  `tabOrderPrefsProvider` ; comme `_orderedTourneeKeys` se base sur
  `containsKey`, ces thèmes disparaissent aussi de l'ordre Essentiel.
- Recompose **ciblée** : un `ref.listen(tabOrderPrefsProvider)` qui ne
  recompose que si l'ensemble des clés `theme:` change (un réordre
  sujets/sources Flâner n'affecte pas la Tournée).
- Réutilise l'infra existante : `tourneeOrderPrefsProvider` /
  `tabOrderPrefsProvider`, `visualFor` + `kVeilleFacteurThemes` pour
  label/emoji d'onglet, `MyInterestsIntro`, `showTourneeComposerSheet`. Clé
  `tabOrderThemeKey('theme:<slug>')` miroir de `tourneeThemeKey`.
- Carte/inline pilotés par `tourneeOrderPrefsProvider.select((s) => s.customized)`
  (rebuild ciblé) ; placement dérivé de deux booléens (`heroPresent`,
  `inlineTargetIndex`).
- `PersonalisationCtaCard` : gabarit visuel *aligné sur* la `CarteCta` de la
  Grille mais widget distinct (CarteCta est couplée à l'état du jeu Grille —
  la réutiliser imposerait de simuler `GrilleTodayResponse`).

## Comment ça a été vérifié

- [x] `flutter analyze lib/features/flux_continu lib/features/feed` — **clean**
      (aucun error/warning ; seulement des `info` `withOpacity` pré-existants
      hors-scope).
- [x] `flutter test test/features/flux_continu/ test/features/feed/widgets/favorite_topic_tabs_test.dart`
      — verts **sauf 2 échecs pré-existants hors-scope** confirmés sur la
      baseline `origin/main` : `section_block_test.dart` (ne compile pas vs
      origin/main) + `essentiel_hi_fi_card_test.dart` (« Météo », carte hero non
      touchée).
- [x] Régression corrigée : `tournee_composer_sheet_test.dart` asseyait l'ancien
      titre de section (`CHAQUE MATIN DANS TON ESSENTIEL`) → mis à jour vers
      `BLOCS DE TA PAGE L'ESSENTIEL`.
- [x] Tests ajoutés/MAJ : `personalisation_cta_card_test`,
      `manage_favorites_sheet_test`, `favorite_topic_tabs_test`,
      `flux_continu_tournee_order_test`.
- [ ] Validation device/feel : à confirmer par le PO.

> CI = backend pytest only (pas de `flutter test`) → les 2 échecs mobiles
> pré-existants ne bloquent pas la CI.

## Zones à risque

- `flux_continu_screen.dart` (écran central scroll/snap) : **aucune** modif de
  `_SectionSnapPhysics`, `resolveSnapTarget`, ni des constantes de tuning. Les
  changements sont additifs (carte/inline) + du reformatage `dart format`.
- `flux_continu_provider.dart` : nouveau `ref.listen` ciblé + filtre exclusif
  dans `_tourneeSectionByKey()` — aucun changement de requête feed (le filtre
  thème existait déjà côté `setTheme`).
- Aucun changement backend / migration.
