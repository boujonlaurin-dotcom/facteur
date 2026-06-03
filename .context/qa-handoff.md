# QA Handoff — Snap d'ancrage « section par section » (L'Essentiel / flux-continu)

## Feature développée
Remplacement du demi-snap intermittent de #772 par un **snap d'ancrage** intégré à la
phase balistique du fling : au lâcher du doigt, une `ScrollPhysics` custom choisit une
position de repos alignée sur le **début d'une section** (sous la sticky bar), sur geste
lent **et** rapide (déclenchement constant, non gaté en vitesse), avec une haptique
`mediumImpact` **au repos**. Scroll libre dedans ; sections hautes (carte Essentiel hi-fi)
laissées libres.

## PR associée
À créer via `/go` (base `main`). Branche : `boujonlaurin-dotcom/essentiel-scroll-snap-ux`.

## Écrans impactés
| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| L'Essentiel (flux continu) | onglet Essentiel | Modifié (physique de scroll) |

## Scénarios de test

### Scénario 1 : Flick lent sur une frontière (happy path)
**Parcours** :
1. Aller sur L'Essentiel, scroller jusqu'à voir la sticky bar.
2. Faire un petit flick lent près d'une frontière de section.
**Résultat attendu** : le début de la section voisine se cale sous la sticky bar (snap
ferme), **une** haptique medium nette au moment où ça se pose. Pas de rubber-band.

### Scénario 2 : Fling fort sur plusieurs sections
**Parcours** :
1. Faire un fling appuyé qui traverse plusieurs sections.
**Résultat attendu** : atterrit aligné sur un **début** de section (jamais au milieu d'une
carte), **une seule** haptique au repos (pas de buzz par section traversée).

### Scénario 3 : Lecture dans la carte Essentiel hi-fi (section haute)
**Parcours** :
1. Scroller dans la grande carte Essentiel et s'arrêter au milieu.
**Résultat attendu** : on peut s'arrêter **au milieu** — pas piégé/ramené à une ancre
(garde « section haute » : atterrissage > 0,5 × viewport d'une ancre ⇒ scroll libre).

### Scénario 4 : Près du haut (pull-to-refresh)
**Parcours** :
1. Remonter tout en haut, tirer pour rafraîchir.
**Résultat attendu** : pull-to-refresh OK, **aucun** snap parasite dans la zone
header/bannières (bail si `pixels <= première ancre`).

### Scénario 5 : Highlight onglet + pulse du dot
**Parcours** :
1. Scroller section par section en observant la sticky bar.
**Résultat attendu** : l'onglet actif se met à jour, le dot de passage pulse, **pas de
double-buzz** (le `selectionClick` est supprimé pendant un snap, remplacé par le settle
medium).

## Critères d'acceptation
- [ ] Le snap se sent **et** cadre tout le scroll (déclenchement constant lent + rapide).
- [ ] Le snap fait partie de la décélération du fling (une seule motion, pas une 2e anim).
- [ ] Haptique medium **au repos** du snap, jamais doublée.
- [ ] Sections hautes / atterrissages loin d'une ancre laissés libres (lecture préservée).
- [ ] Pull-to-refresh intact, aucun snap dans la zone header.
- [ ] `flutter analyze` propre, tests `section_snap_test.dart` verts.

## Zones de risque
- **iOS vs Android** : `naturalLanding` dérive du parent plateforme (Bouncing/Clamping) →
  feel natif préservé, mais tuner `kSnapCaptureFraction` par plateforme si besoin.
- **Ancres lazy/hors-écran** : `localToGlobal` ne résout que les boxes attachées ; slivers
  non-lazy ici → bail gracieux si une ancre n'est pas montée cette frame.
- **Carte Essentiel hi-fi** : re-vérifier spécifiquement qu'on n'est jamais piégé dedans.

## Dépendances
Aucune (mobile-only, zéro backend / API). 4 knobs de tuning regroupés dans
`apps/mobile/lib/features/flux_continu/utils/section_snap.dart`
(`kSnapCaptureFraction`, `kBoundaryCrossVelocity`, `kSnapEpsilon`, `kSnapSpring`) pour
ajustement device au feeling.
