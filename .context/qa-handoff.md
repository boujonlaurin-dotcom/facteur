# QA Handoff — Onboarding Q9b : carrousel pour l'affinage des thèmes

## Feature développée

L'écran d'affinage des centres d'intérêt (`Q9b — Affine tes centres d'intérêt`) ne défile plus verticalement. Les thèmes sélectionnés à Q9 sont désormais présentés sous forme de carrousel horizontal (un thème par page, swipe latéral). Un sticky header animé affiche le thème courant au-dessus du carrousel ; des dots indicateurs colorés à la couleur du thème courant indiquent la progression. Le bouton "Continue" reste actif dès le départ ; un modal de confirmation apparaît si l'utilisateur tente de continuer sans avoir parcouru tous les thèmes.

## PR associée

À créer après validation QA.

## Écrans impactés

| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Onboarding Q9b — Affine tes centres d'intérêt | Onboarding section 3, step 1 (après Q9 themes) | Modifié |

## Scénarios de test

### Scénario 1 : Happy path multi-thèmes
**Parcours** :
1. Démarrer un nouvel onboarding (ou réinitialiser)
2. Avancer jusqu'à Q9 et sélectionner 4 thèmes (ex. tech, international, science, culture)
3. Continuer vers Q9b

**Résultat attendu** :
- Le sticky header affiche l'emoji + label du premier thème (couleur primaire du thème).
- 4 dots apparaissent sous le header ; le 1er est actif (forme allongée 24×10), les 3 autres sont inactifs (10×10).
- La carte du thème courant occupe la majorité de l'espace ; un léger peek de la carte suivante est visible à droite (viewportFraction 0.92).
- Swipe vers la gauche → navigation vers le 2ᵉ thème : le sticky header s'anime (fade + slide), les dots avancent, la couleur active du dot passe à celle du nouveau thème.

### Scénario 2 : Persistance des sélections au swipe
**Parcours** :
1. Sur Q9b avec 3+ thèmes
2. Sur le thème 1, cocher 2 subtopics et 1 entité populaire
3. Swipe vers le thème 2, cocher 1 subtopic
4. Swipe retour vers le thème 1

**Résultat attendu** : les 2 subtopics + l'entité du thème 1 sont toujours cochés.

### Scénario 3 : Couleur dynamique des dots
**Parcours** : sélectionner ≥ 3 thèmes de couleurs différentes, swipe entre eux.

**Résultat attendu** : à chaque page, le dot actif prend la couleur du thème courant (ex. bleu pour tech, vert pour environnement, etc.).

### Scénario 4 : Mono-thème (pas de carrousel)
**Parcours** : à Q9, ne sélectionner qu'1 seul thème, continuer.

**Résultat attendu** :
- Pas de sticky header au-dessus.
- Pas de dots indicateurs.
- La carte unique du thème s'affiche directement, avec son header interne (emoji + label) en haut de la carte (comportement legacy préservé).
- Tap Continue → pas de modal, navigation directe vers Q10.

### Scénario 5 : Custom topic + clavier
**Parcours** :
1. Sur Q9b, sur n'importe quel thème, tap "ajouter un sujet"
2. Le clavier apparaît, le TextField se met en focus
3. Saisir un nom et soumettre

**Résultat attendu** : le TextField reste visible (le SingleChildScrollView interne à la page absorbe le décalage du clavier). Le custom chip apparaît dans la liste au-dessus du CTA.

### Scénario 6 : Continue sans tout parcourir → modal
**Parcours** :
1. Sélectionner 4 thèmes à Q9
2. Sur Q9b, ne swiper que jusqu'au 2ᵉ thème (visited = {0, 1})
3. Tap Continue

**Résultat attendu** :
- Modal `AlertDialog` apparaît avec titre "Êtes-vous sûr ?" et contenu "Vous pourrez toujours définir vos intérêts plus tard dans 'Mes intérêts'."
- 2 actions : "Voir les autres thèmes" (referme sans naviguer) et "Continuer" (procède à la sauvegarde + navigation Q10).
- Tester les 2 actions.

### Scénario 7 : Continue après tout parcourir → pas de modal
**Parcours** : sélectionner 4 thèmes, swiper jusqu'au dernier (indice 3, visited = {0, 1, 2, 3}), tap Continue.

**Résultat attendu** : pas de modal, navigation directe vers Q10. Les sélections (subtopics + entities + customs des 4 thèmes) sont sauvegardées en backend.

### Scénario 8 : Restart onboarding
**Parcours** : compléter Q9b une fois, revenir à Q9b via reset partiel.

**Résultat attendu** : les sélections précédentes sont restaurées (chips cochés sur les bons thèmes), la page initiale est 0 (premier thème).

## Critères d'acceptation

- [ ] Carrousel horizontal swipeable entre thèmes (≥ 2 thèmes sélectionnés)
- [ ] Sticky header animé au-dessus du carrousel reflétant le thème courant
- [ ] Dots indicateurs colorés à la couleur du thème courant
- [ ] Bouton Continue actif dès le départ
- [ ] Modal de confirmation uniquement si pas tous les thèmes parcourus
- [ ] Cas mono-thème : rendu direct sans carrousel ni modal
- [ ] Sélections persistantes lors des changements de page
- [ ] Custom topic + keyboard fonctionnent dans une page de carrousel
- [ ] Aucune régression sur la sauvegarde des subtopics/entities/customs

## Zones de risque

- **Hauteur dynamique** : les cards de "tech" ou "international" peuvent être plus hautes que l'écran (beaucoup de subtopics + entités). Vérifier que le `SingleChildScrollView` interne à la page absorbe correctement le débordement vertical.
- **Keyboard + PageView** : sur certains devices, le clavier qui s'ouvre dans une page de carrousel peut perturber le scroll. Vérifier que le TextField reste visible et que le scroll-into-view fonctionne.
- **Animation du sticky header** : à valider visuellement — fade + slide de 0.2 vertical sur 250ms. Si trop sec ou trop lent, ajuster.
- **Couleurs des thèmes** : 9 thèmes ont chacun leur couleur (cf. `AvailableThemes.all`). Vérifier que toutes les couleurs sont lisibles en tant que dot actif sur le fond standard.

## Dépendances

- API `/topics/follow` (via `customTopicsProvider.followTopic`) — inchangé.
- Provider `popularEntitiesProvider(themeSlug)` — inchangé.
- `OnboardingAnswers.subtopics` (state via Riverpod) — inchangé.

Aucun endpoint backend modifié, aucune migration DB.

## Fichiers modifiés

- `apps/mobile/lib/features/onboarding/screens/questions/subtopics_question.dart` (seul fichier modifié pour cette feature)
