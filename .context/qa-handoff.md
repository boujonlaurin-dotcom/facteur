# QA Handoff — PR-A Stabilité du questionnaire d'onboarding

> Salve pré-Stores. PR-A = stabilité + simplification du questionnaire.
> PR-B (Refonte sources + Wow) est gérée séparément, plus tard.

## Feature développée
Correction de l'écran gris fatal en fin/abandon de questionnaire (Sentry FLUTTER-2)
et refonte de fluidité : questionnaire raccourci (suppression des questions
articles/jour + gamification), tap carte source = modal de compréhension par défaut,
mode serein conditionnel déplacé juste avant le final, bouton « Passer » avec défauts
sains, et fix du champ sujet custom caché par le clavier.

## PR associée
À créer vers `main` (`--base main`).

## Écrans impactés
| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Splash (gate anti-rebond) | /splash | Modifié (logique redirect) |
| Onboarding (questionnaire) | /onboarding | Modifié |
| Conclusion onboarding | /onboarding/conclusion | Inchangé (vérif non-régression) |
| Essentiel / Flux Continu (sortie) | /flux-continu | Cible de sortie (vérif pas de gris) |
| Modal détail source | (bottom sheet) | Modifié (libellés sélection onboarding) |

## Scénarios de test

### Scénario 1 : Happy path — signup → fin du questionnaire
1. Créer un nouveau compte → confirmer email → arriver sur l'onboarding.
2. Répondre à toutes les questions jusqu'au bout (animation de conclusion).
**Résultat attendu** : atterrissage sur l'Essentiel, modals post-onboarding OK,
**aucun écran gris**.

### Scénario 2 : Abandon en cours de questionnaire
1. Démarrer l'onboarding, avancer de quelques questions.
2. Taper la croix « Quitter » → confirmer « Quitter ».
**Résultat attendu** : atterrissage sur l'Essentiel, **aucun écran gris**.

### Scénario 3 : Refaire le questionnaire depuis les réglages
1. Depuis Réglages, relancer le questionnaire.
2. Le terminer (fin) **puis** (autre run) l'abandonner.
**Résultat attendu** : les deux chemins atterrissent proprement, **aucun écran gris**.

### Scénario 4 : « Passer » tout le questionnaire
1. Sur chaque question proposant « Passer cette étape », taper « Passer ».
**Résultat attendu** : le parcours avance avec des défauts sains (objectifs vides →
Section 2 ; approach=detailed ; responseStyle=nuanced ; thèmes vides → sources
directement ; digestMode=pour_vous). Les suggestions de sources restent ≥ 5 même sans
thème sélectionné.

### Scénario 5 : Mode serein conditionnel
1. Run A : ne PAS cocher « La négativité » dans les objectifs → terminer.
   **Attendu** : la question « Rester serein ? » **n'apparaît pas** ; on passe direct au final.
2. Run B : cocher « La négativité » → terminer.
   **Attendu** : la question « Rester serein ? » apparaît **juste avant** le final, avec la
   mention « Vous pourrez activer ou désactiver le mode serein à tout moment depuis Mes
   intérêts. »

### Scénario 6 : Tap carte source vs sélection
1. Sur la page sources, taper le **corps** d'une carte source.
   **Attendu** : ouverture de la modal de compréhension (libellé bouton
   « Sélectionner cette source » / « Retirer de ma sélection »).
2. Taper le **cercle** de sélection à droite.
   **Attendu** : toggle de la sélection (zone de tap ≥ 44px), sans ouvrir la modal.

### Scénario 7 : Champ sujet custom + clavier (edge)
1. Sur « Affine tes centres d'intérêt », taper « + ajouter » pour saisir un sujet custom.
2. Observer pendant que le clavier monte (tester mono-thème ET multi-thème PageView, petit device).
**Résultat attendu** : le champ de saisie reste **visible au-dessus du clavier**.

## Critères d'acceptation
- [ ] Aucun écran gris en fin **ni** en abandon (FLUTTER-2 éteint sur la release suivante).
- [ ] Questionnaire raccourci : plus de question « articles/jour » ni « gamification ».
- [ ] Mode serein affiché uniquement si objectif « négativité » coché, et placé avant le final.
- [ ] Tap carte = modal ; tap cercle = sélection.
- [ ] Bouton « Passer » présent sur les questions skippables, défauts sains appliqués.
- [ ] Champ sujet custom visible au clavier.

## Zones de risque
- **Redirect / splash gate** : tester la matrice — déconnecté / email non confirmé /
  nouveau compte / utilisateur existant. Le shell ne doit pas se monter avant la résolution
  du statut d'onboarding.
- **Reprise Hive** : bump `_currentVersion` 3→4 → les positions sauvegardées sont wipées ;
  un utilisateur en cours de questionnaire au moment de la MAJ redémarre proprement.
- **Barre de progression** : Section 2 = 2 étapes, Section 3 = 5 (ou 6 si serein).

## Dépendances
- Aucun changement backend. Defaults `dailyArticleCount=5` / `gamification=true` /
  `digest_mode=pour_vous` envoyés via les fallbacks existants (`user_api_service`).
