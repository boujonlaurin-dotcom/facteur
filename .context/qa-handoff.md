# QA Handoff — Tour guidé Facteur (coach-mark post-onboarding)

> Rempli par l'agent dev. Input de `/validate-feature` (Playwright Agent CLI).

## Feature développée
Tour guidé en 5 étapes joué **une seule fois juste après l'onboarding**. Il pilote la vraie app (bascule d'onglet, ouvre la feuille « Mes favoris », scrolle l'Essentiel) et présente : l'Essentiel + ta Tournée, la réorganisation, Flâner, puis spotlight de l'avatar profil pour Réglages et Mon courrier. À la fin (« Terminer » ou « Passer »), la main est rendue aux modales post-onboarding existantes (thème puis notifications).

## PR associée
À créer vers `main` (`--base main`).

## Écrans impactés
| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| L'Essentiel (Flux Continu) | `/flux-continu` | Modifié (ancres hero + 1ʳᵉ section + avatar) |
| Flâner | `/flaner` | Modifié (étape 3, voile centré) |
| Feuille « Mes favoris » | bottom sheet (branche) | Modifié (ancre spotlight) |
| Overlay tour guidé | overlay racine | Nouveau |

## Scénarios de test

### Scénario 1 : Happy path (5 étapes complètes)
1. Compléter l'onboarding jusqu'à l'écran de conclusion → arrivée sur L'Essentiel.
2. **Étape 1/5** : coach card en bas, spotlight sur le hero « L'Essentiel du jour » + onglet Essentiel. Cliquer « Suivant ».
3. **Étape 2/5 (a)** : l'app scrolle vers la 1ʳᵉ section de la Tournée, spotlight dessus. « Suivant ».
4. **Étape 2/5 (b)** : la feuille « Mes favoris » s'ouvre, spotlight la cerne par-dessus. Pastille toujours « 2 / 5 ». « Suivant ».
5. **Étape 3/5** : bascule sur Flâner, voile plein, coach card centrée. « Suivant ».
6. **Étape 4/5** : retour Essentiel, spotlight de l'avatar profil (haut-droite). « Suivant ».
7. **Étape 5/5** : même avatar profil, bouton « Terminer ».
8. **Terminer** → carte « C'est parti ! » brève → puis enchaînement des modales thème puis notifications.

**Attendu** : 5 puces de progression, pastille « N / 5 », pas d'écran gris, pas d'erreur console, pas de 4xx/5xx.

### Scénario 2 : « Passer » à n'importe quelle étape
1. Démarrer le tour, cliquer « Passer » dès l'étape 1.
**Attendu** : overlay retiré, enchaînement direct vers les modales thème/notifications.

### Scénario 3 : Une seule fois
1. Tour terminé, fermer/rouvrir l'app (même utilisateur).
**Attendu** : le tour ne rejoue pas ; les modales post-onboarding (si encore dues) jouent directement.

### Scénario 4 : Edge — feuille favoris refermée au doigt (étape 2b)
1. À l'étape « Compose ta Tournée », fermer la feuille par swipe vers le bas (au lieu de « Suivant »).
**Attendu** : auto-avance vers l'étape Flâner (pas de voile orphelin bloquant).

## Critères d'acceptation
- [ ] Le tour pilote réellement l'app entre les étapes.
- [ ] Étapes 4 & 5 restent sur l'accueil et spotlight l'avatar profil (pas de navigation Settings/Courrier).
- [ ] Joué une seule fois, post-onboarding, aucun point d'entrée « Revoir ».
- [ ] Tour d'abord, puis modales thème/notifications.
- [ ] Pas d'em-dash dans la copy (règle PO).

## Zones de risque
- **Ancre pas encore layoutée** après bascule d'onglet (slide 260ms) / scroll → voile plein tant que la cible n'est pas mesurée/visible, rect recalculé chaque frame.
- **Z-order** : overlay inséré dans l'overlay **racine** ; la feuille favoris reste en navigator de branche (ne PAS passer `useRootNavigator: true`).
- **GlobalKeys uniques** : avatar + onglet Essentiel ancrés uniquement côté Essentiel (les deux branches sont montées simultanément).

## Dépendances
Aucune (frontend pur, persistance locale `SharedPreferences` clé `nudge.guided_tour.seen.<userId>`). Nécessite un compte qui vient de finir l'onboarding.
