# Bug — Fiabiliser le swipe de « Ton Essentiel » + 3 finitions d'animation

> Branche `boujonlaurin-dotcom/essentiel-swipe-drift-fixes`. Plan complet :
> validé PO (11/08/2026). La pile de tri v2 (#1065) continuait de « fortement
> bugger » au swipe malgré ses garde-fous.

## Symptômes

1. **Geste sans fin détectée (priorité)** — certaines cartes restent **figées
   translatées** : ni `onHorizontalDragEnd` ni `onHorizontalDragCancel` ne se
   déclenchent.
2. **Drift des articles suivants** — la carte du dessous paraît décalée pendant
   le swipe.
3. Finitions : post « Je garde » plus satisfaisant, animation discrète de fin de
   tri, barre de progression + « Je veux lire X » plus discrets.

## Causes racines

### Bug 2 — geste sans fin détectée

Le `Timer? _exitGuard` (`triage_swipe_card.dart`) ne protège que la phase de
**sortie**, jamais la phase de **drag**. Si le `HorizontalDragGestureRecognizer`
ne délivre jamais de `onEnd`/`onCancel` terminal (2ᵉ doigt qui atterrit en cours
de swipe et fait « tenir » le recognizer ; perte de route d'arène),
`_dragUnderway` reste `true` et `_dragExtent` figé ≠ 0. Le reset de
`didUpdateWidget` ne sauve pas : aucune décision → l'index n'avance pas →
`articleId` ne change pas → gel **permanent**.

### Bug 1 — drift

La carte du dessous est statique et pleine largeur (opacité seule) — elle ne
bouge pas. Deux contributions sur la carte du **dessus** :

1. **Cause principale (confirmée au screenshot PO du 11/08)** : le
   `Transform.translate` du drag/de la sortie **peint hors des bornes de
   layout**, et un `Stack` ne rogne que ses enfants *positionnés* — jamais la
   carte du dessus (l'enfant non positionné). Pendant tout le geste, la carte
   débordait donc du cadre de la pile (tranche de carte visible à droite de
   « Ton Essentiel »), lue comme un décalage des articles suivants.
2. Contribution secondaire : la **rotation à origine centrée** (`dx/26°`,
   ~3,1° à 80px) faisait balayer ~11px horizontalement aux coins en plus de la
   translation.

## Fixes livrés

### Bug 2 — filet de sécurité passif `Listener` (`triage_swipe_card.dart`)

- Refactor : corps décisionnel de `_handleDragEnd` extrait dans
  `_resolveDragEnd({required double velocity})` (`_dragUnderway = false`
  d'abord ⇒ les deux entrées sont mutuellement exclusives ; lit `_screenWidth`
  mémorisé, plus de `MediaQuery` en callback).
- `Listener(behavior: HitTestBehavior.deferToChild)` autour du
  `GestureDetector` (précédent maison : `article_preview_modal.dart`). Passif
  ⇒ tap + long-press + drag intacts.
- `_activePointers` (Set) + réconciliation **différée** par `scheduleMicrotask`
  quand le dernier doigt se lève alors que `_dragUnderway` est encore vrai (le
  `Listener` s'exécute avant le `onEnd` du recognizer). No-op si le chemin
  normal a résolu / nouveau geste / sortie en cours ; sinon
  `_resolveDragEnd(velocity: 0)` — seule la distance décide, sous le seuil →
  spring-back.
- Nettoyage dans `didUpdateWidget` (changement d'`articleId`) et `dispose`.
- Compteur `lostGestureResolutions` `@visibleForTesting` : doit rester à 0 sur
  tous les drags propres.

### Bug 1 — pile rognée + rotation réduite/bornée/ancrée en haut

- **`ClipRect` autour du `Stack` de la pile** (`essentiel_triage_stack.dart`) :
  la carte draggée/sortante glisse *hors du cadre* et y disparaît proprement,
  comme tirée d'un paquet — plus aucun pixel ne balaie le feed. C'est la
  correction du drift constaté au screenshot (itération 2, après retour PO).
- `_rotationDivisor` 26 → **50**, angle clampé à ±**2,5°**, pivot
  `Alignment.topCenter` (les deux cartes partagent leur bord haut à `top: 0` ⇒
  déplacement du coin haut sub-pixel).
- Durcissement : suppression du `_emitProgress()` pré-avance dans
  `_completeExit` (flash d'opacité d'une frame sur la carte promue) ; c'est
  `didUpdateWidget` qui remet la promotion à zéro après l'avance d'index.

### Finitions

3. **Entrée de la ligne gardée** (`essentiel_triage_stack.dart`, `_KeptRow`) :
   glissée depuis la gauche (−16px→0) + fondu (`FacteurDurations.slow` 400ms,
   easeOutCubic) et **pop de la coche** (scale 0→1, easeOutBack avec léger
   dépassement), joués une seule fois à l'ajout (capture au montage du State),
   jamais sur les lignes du cold-boot. Pas de nouvelle haptique. Respecte
   `MediaQuery.maybeDisableAnimationsOf`. (Itération 2 : le fade + scale 0.98
   de la première passe était imperceptible — l'`AnimatedSize` pousse la liste
   au même moment et 2 % de scale sur 64px ≈ 1px.)
4. **Révélation de fin de tri** (`essentiel_hi_fi_card.dart`,
   `_TriageDoneReveal`) : fondu + remontée de 16px (400ms) sur la bascule vécue
   pile → liste des gardés (`_sawTriageActive`). Cold-boot déjà terminé =
   rendu direct. Respecte reduce-motion. Ni confetti ni haptique (sobriété
   Essentiel). (Itération 2 : même raison — seul un déplacement franc se lit
   pendant le réagencement de la carte.)
5. **Discrétion** : remplissage barre `alpha` 0.5 → **0.35** ;
   libellés « Je veux lire » / « articles aujourd'hui » `textSecondary` →
   `textTertiary` (le chiffre N reste `textPrimary` 14/w600).

## Itération 3 — retours PO du 11/08 (screenshot)

1. **Arrondis colorés autour de la première carte** (`essentiel_triage_stack.dart`)
   — l'image de la carte du **dessous** apparaissait dans les deux encoches
   laissées par les coins arrondis de la carte du dessus (deux arcs bleus sur le
   screenshot PO). Cause : le slot arrière était un `Positioned(top/left/right)`
   sans hauteur, rogné par le `Stack` au **rectangle droit** de la carte du
   dessus — donc pas à ses coins. Fix : `Positioned.fill` +
   `ClipRRect(FacteurRadius.large)` + `OverflowBox(topCenter, maxHeight:
   infinity)`. La zone rognée épouse exactement la silhouette de la carte du
   dessus, tandis que le contenu du dessous garde sa hauteur réelle (une
   contrainte serrée faisait déborder une carte image sous une carte texte
   courte — la raison pour laquelle `Positioned.fill` avait été écarté).
2. **Contrôle d'objectif plus discret et recentré sur l'action**
   (`TriageGoalControl`) : « Je veux lire N articles aujourd'hui » →
   **« Garder N articles »** (moins de mots, donc moins de masse au centre de la
   carte) ; libellés 12 → **11,5** ; chiffre N `textPrimary` 14 →
   **`textSecondary` 13**. Largeurs des barres de la silhouette
   (`triage_stack_skeleton.dart`) ajustées aux nouveaux mots (74/112 → 42/44),
   sans quoi la mise en page sauterait à l'hydratation.
3. **Barre de progression, contraste acquis/restant** : segment rempli
   `alpha` 0.35 → **0.45**, segment vide `colors.border` → **`border` à 0.45**.
4. **Fin de tri : un vrai sous-titre de carte** (`essentiel_hi_fi_card.dart`,
   `_KeptSectionTitle`) — « Tes articles » en **Fraunces 15/w600**, prolongé par
   un filet jusqu'au bord de la carte (titre *incrusté dans* le séparateur).
   Distinct de l'en-tête inline `TES ARTICLES` (Courier capitales) qui vit sous
   la pile **pendant** le tri : celui-ci marque la fin du tri. Rendu seulement
   si au moins un article est gardé (sinon `_NothingKeptNotice` tient la place).

## Tests

- `triage_swipe_card_test.dart` : multi-touch lever entrelacé (invariant
  anti-gel), drag abandonné + changement d'article (aucune fuite), PointerCancel
  au binding, filet exercé en événements bruts (compteur = 0 sur drags propres) ;
  non-régression des bancs existants (swipes rapides, exit ignoré, tap-vs-drag,
  tampons, `onGestureProgress`).
- `essentiel_hi_fi_card_test.dart` : révélation montée sur transition vécue,
  absente au cold-boot et sous reduce-motion ; entrée jouée sur la nouvelle
  ligne gardée seulement ; alphas de la barre (0.45 / border 0.45).
- Itération 3 — `essentiel_hi_fi_card_test.dart` : la carte du dessous, plus
  haute que celle du dessus (image sous carte texte), est rognée au **même
  arrondi** et au **même gabarit** que celle du dessus ; le sous-titre
  « Tes articles » existe en fin de tri, en police de titre, au-dessus de la
  première tuile et prolongé d'un filet — et n'existe **pas** pendant le tri
  (où seul l'en-tête inline `TES ARTICLES` est rendu) ; copy et style du
  contrôle d'objectif (« Garder » / « articles », chiffre 13 `textSecondary`).

## Restes

- Validation **visuelle** du drift (Bug 1 est un constat visuel) via
  `/validate-feature` — handoff dans `.context/qa-handoff.md`.
