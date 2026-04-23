# QA Handoff — Welcome Tour (Story 16.1 PR2)

> Feature branch : `boujonlaurin-dotcom/welcome-tour`
> Story : `docs/stories/core/16.1.welcome-tour-nudges.md`

## Feature développée

Tour de bienvenue 3 écrans animés (Essentiel / Ton flux / Personnalisation) déclenché pour **tous les utilisateurs** (nouveaux + existants) une fois après onboarding. Gated par le redirect GoRouter via `AuthState.welcomeTourSeen`, persisté par le NudgeService unifié (PR1 #468).

## PR associée
À remplir après `gh pr create`.

## Écrans impactés

| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Welcome Tour (PageView 3 pages) | `/welcome-tour` | **Nouveau** |
| Router redirect | (routes.dart) | Modifié (gate `welcomeTourSeen`) |
| Conclusion onboarding | `/onboarding/conclusion` | Non touché (le redirect intercepte) |
| Digest | `/digest` | Non touché |

## Scénarios de test

### Scénario 1 : Nouveau user — onboarding → tour → digest
**Parcours** :
1. Fresh install, créer un compte, confirmer l'email
2. Compléter les 15 étapes d'onboarding
3. Observer la `ConclusionAnimationScreen` (loading animation)
4. Elle navigue vers `/digest?first=true` mais le redirect intercepte → `/welcome-tour`
5. Swipe entre les 3 pages (ou tap "Suivant")
6. Tap "Commencer" sur la 3ᵉ page

**Résultat attendu** :
- Les 3 pages s'affichent dans l'ordre Essentiel → Ton flux → Personnalisation
- Les dots en bas indiquent la progression
- Chaque page a une illustration animée (soleil + cartes / cartes défilantes / chips + slider)
- Après "Commencer" → arrive sur `/digest?first=true`
- Le `DigestWelcomeModal` existant s'affiche

### Scénario 2 : User existant — 1ʳᵉ relance post-deploy
**Parcours** :
1. User déjà onboardé avant ce PR (cache `onboarding_completed=true`, pas de `nudge.welcome_tour.seen`)
2. Relancer l'app → splash → auth check
3. Router redirect : `!needsOnboarding && !welcomeTourSeen` → `/welcome-tour`

**Résultat attendu** :
- Le tour s'affiche à la place du `/digest`
- Même comportement qu'au scénario 1 pour la suite

### Scénario 3 : Skip depuis la page 1
**Parcours** :
1. Arriver sur `/welcome-tour` (via scénario 1 ou 2)
2. Tap "Passer" en haut à droite

**Résultat attendu** :
- Navigue directement vers `/digest` (sans `?first=true` → pas de welcome modal)
- `markSeen(welcome_tour)` persiste le flag

### Scénario 4 : Re-relance après tour vu
**Parcours** :
1. Après scénarios 1, 2 ou 3, tuer l'app
2. Rouvrir l'app

**Résultat attendu** :
- Pas de re-affichage du tour
- Arrivée directe sur `/digest` (default authenticated route)
- Deep link `/welcome-tour` forcé → le redirect renvoie vers `/digest`

### Scénario 5 : Retour back-button pendant le tour
**Parcours** :
1. Être sur le tour (n'importe quelle page)
2. Appuyer sur le bouton back Android / geste back iOS

**Résultat attendu** :
- Le back est bloqué par `PopScope(canPop: false)` — le user ne peut pas quitter le tour sans "Passer" ou "Commencer"

### Scénario 6 : Interruption mid-tour (crash/force quit)
**Parcours** :
1. Arriver sur le tour, swipe à la page 2
2. Force-quit l'app
3. Relancer

**Résultat attendu** :
- Le tour réapparaît à la page 1 (état éphémère pas persisté — par design)
- Pas de crash ni de deadlock

## Critères d'acceptation (story 16.1)

- [ ] AC-1 : Après onboarding, 3 pages Essentiel → Ton flux → Personnalisation
- [ ] AC-2 : Bouton "Passer" top-right dismiss le tour (mark seen + go digest)
- [ ] AC-3 : "Commencer" sur dernière page → `/digest?first=true` → `DigestWelcomeModal` s'affiche
- [ ] AC-4 : Flag persisté → relance de l'app ne re-affiche pas le tour
- [ ] AC-5 : User existant (pré-PR2) voit le tour **une fois** au prochain boot

## Zones de risque

- **Timing du redirect** : le chargement de `welcomeTourSeen` est async dans `_init()`. Avant qu'il charge, `welcomeTourSeen=true` par défaut → pas de redirect. Cela évite un flash du tour avant que la vraie valeur soit lue. À tester : latence réseau lente au boot, vérifier que le tour apparaît bien après le chargement.
- **Clash avec `DigestWelcomeModal`** : le modal existant (nudge `digest_welcome`) est déclenché par `/digest?first=true`. Si un user existant n'a jamais vu le modal non plus, il verra tour → digest → modal. C'est l'expérience voulue.
- **iOS gesture-back** : à vérifier que `PopScope` bloque aussi le swipe-from-left edge natif iOS.
- **Dark mode** : vérifier que les illustrations (soleil, cartes, chips) sont lisibles dans les deux thèmes.

## Dépendances

- Aucune nouvelle dépendance backend.
- Utilise `NudgeService` / `NudgeRegistry` (PR1 mergée #468).
- Route `/welcome-tour` hors `ShellRoute` (pas de bottom nav pendant le tour).

## Notes

- Tests unitaires PR1 (24 tests) : toujours verts.
- Widget tests PR2 (3 tests, `test/features/welcome_tour/tour_pages_test.dart`) : les 3 pages rendent titre + subtitle sans crash.
- Test pré-existant `router_redirection_test.dart::Router should redirect to EmailConfirmationScreen` échoue **sur main** déjà — non lié à PR2.
