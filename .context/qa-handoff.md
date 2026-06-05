# QA Handoff — Ajustements UX/UI de « L'Essentiel » (5 points)

> Rempli par l'agent dev. Input de `/validate-feature` (Chrome, viewport 390×844).

## Feature développée
5 frictions UX corrigées sur la page **L'Essentiel** (Flux Continu) et sa modal
« Mes favoris » : carte de perso dédiée + inline lié au snap, Grille collée aux
Actus, titres de sections plus clairs, thèmes livrables en onglet Flâner (modèle
exclusif comme les sources), et cap max affiché entre parenthèses.

## PR associée
[#798 — feat(flux-continu): ajustements UX de L'Essentiel](https://github.com/boujonlaurin-dotcom/facteur/pull/798)

## Écrans impactés
| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| L'Essentiel (Flux Continu) | `/` (flux continu) | Modifié |
| Modal « Mes favoris » | bottom sheet (depuis l'Essentiel / Flâner) | Modifié |
| Carte de perso | nouveau widget `PersonalisationCtaCard` | Nouveau |

## Scénarios de test

### Scénario 1 — Compte non personnalisé : grande carte de perso
**Parcours** :
1. Compte neuf (`tournee_customized_v1` absent / faux).
2. Ouvrir l'Essentiel.
**Résultat attendu** : juste après le hero « L'Essentiel du jour », une **grande
carte** « Personnalise ton Essentiel » avec l'illustration
(`facteur_reparation_velo.png`) et le bouton **« Composer ma Tournée »**. L'inline
discret « Gérer / Tes N favoris » n'apparaît PAS. Taper le bouton → ouvre la sheet
« Mes favoris ».

### Scénario 2 — Compte personnalisé : inline lié au snap
**Parcours** :
1. Personnaliser la Tournée (ajouter/retirer un favori) puis revenir à l'Essentiel.
2. Scroller (fling) à travers les sections.
**Résultat attendu** : la grande carte disparaît ; l'**inline** « Gérer / Tes N
favoris » réapparaît, embarqué en tête de la 1ʳᵉ section après le hero. Au snap, il
n'est plus « sauté » entre deux blocs — il fait partie du bloc de cette section.

### Scénario 3 — Modal : Grille, titres, caps
**Parcours** :
1. Ouvrir « Mes favoris ».
**Résultat attendu** :
- Sections nommées **« BLOCS DE TA PAGE L'ESSENTIEL »** et **« ONGLETS DE TA PAGE
  FLÂNER »**.
- **« Actus & Mot du jour »** présent ; **« La Grille du jour »** n'est PAS un bloc
  drag&drop.
- Au-delà du cap, les traits affichent **« Hors Tournée du jour (5) »** et **« Hors
  onglets (10) »**.

### Scénario 4 — Thème Essentiel ⇄ Flâner (modèle exclusif)
**Parcours** :
1. Dans « Mes favoris », sur un **thème** côté Essentiel, taper l'icône
   « déplacer vers Flâner » (flèche bas).
2. Fermer la modal, observer la barre d'onglets Flâner et la page Essentiel.
**Résultat attendu** : le thème apparaît en **onglet Flâner** (taper l'onglet filtre
le feed sur ce thème) et **disparaît des sections de l'Essentiel**. Le mouvement
inverse (flèche haut, côté Flâner) le ramène dans l'Essentiel.

### Scénario 5 — Cas limite : retrait d'un thème en mode Flâner
**Parcours** :
1. Thème en onglet Flâner → le retirer via la croix dans la modal.
**Résultat attendu** : il disparaît des deux modes (clé retirée de `tournee_order_v1`
et de `pinned_tabs_order_v1`), repasse en « suivi ». Pas de crash.

## Critères d'acceptation
- [ ] Carte de perso (illustration + CTA) sous le hero quand non personnalisé.
- [ ] Inline réapparaît une fois personnalisé et ne « saute » plus au snap.
- [ ] Grille non draggable + libellé « Actus & Mot du jour ».
- [ ] Titres « BLOCS DE TA PAGE L'ESSENTIEL » / « ONGLETS DE TA PAGE FLÂNER ».
- [ ] Thème déplaçable Essentiel ⇄ Flâner (filtre feed OK, exclusion Essentiel OK).
- [ ] Caps affichés « (5) » / « (10) ».
- [ ] Console sans erreurs, réseau sans 4xx/5xx inattendus.

## Notes techniques
- Aucun changement backend / migration / requête feed (le filtre thème existait
  déjà via `setTheme`).
- Tests : `manage_favorites_sheet_test`, `favorite_topic_tabs_test`,
  `flux_continu_tournee_order_test`, nouveau `personalisation_cta_card_test` — verts.
- 3 échecs pré-existants dans `essentiel_hi_fi_card_test` (weather badge, non liés).
