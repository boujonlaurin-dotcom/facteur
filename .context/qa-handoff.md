# QA Handoff — Mode Serein déplacé de l'onboarding vers le tour guidé

> Rempli par l'agent dev. Input de /validate-feature.

## Feature développée
Retrait de l'écran « 🌿 Rester serein ? » en fin d'onboarding et présentation du
Mode Serein comme **dernière étape du tour guidé post-onboarding** : le coach-mark
ouvre la modale Réglages, met en surbrillance la tuile « Mode Serein » (switch
actionnable sur place), avec les explications de l'ancien écran. Aucun commit
automatique — le mode reste OFF par défaut.

## PR associée
À créer (base `main`).

## Écrans impactés
| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Onboarding Section 3 (finalize) | flow onboarding | Modifié (écran serein retiré ; récap sans ligne « Mode ») |
| Tour guidé (overlay) | par-dessus `/flux-continu` | Modifié (nouvelle étape `serein`, 6/6) |
| Modale Réglages | `/settings` | Modifié (tuile Mode Serein = ancre spotlight `tourSereinTileKey`) |

## Scénarios de test

### Scénario 1 : Onboarding SANS objectif « anxiety »
**Parcours** : faire un onboarding complet sans cocher « anxiety ».
**Résultat attendu** : l'écran « Rester serein ? » n'apparaît jamais ; le récap
final n'affiche plus la ligne « Mode : … » (3 lignes : thèmes, sources, articles).

### Scénario 2 : Onboarding AVEC objectif « anxiety »
**Parcours** : onboarding complet en cochant « anxiety ».
**Résultat attendu** : identique au scénario 1 — l'écran serein n'apparaît plus
(l'étape n'est plus conditionnelle à l'objectif). La séquence Section 3 fait
toujours 5 questions (themes → subtopics → swipe → sources → finalize).

### Scénario 3 : Dernière étape du tour guidé (happy path)
**Parcours** : après l'onboarding, dérouler le tour jusqu'à la dernière étape.
1. Passer les étapes jusqu'à « Mon courrier » (bouton « Suivant »).
2. À l'étape suivante « Mode Serein » : la modale Réglages s'ouvre, la tuile
   « Mode Serein » est en surbrillance, le texte reprend les explications
   (filtrer les contenus anxiogènes, activable/désactivable à tout moment), et
   le bouton est « Terminer » (pastille 6/6).
3. Activer le switch Mode Serein directement sous le spotlight.
4. Taper « Terminer ».
**Résultat attendu** : le switch bascule ON (persisté), la modale se referme, la
carte « C'est parti ! » s'affiche par-dessus le shell puis disparaît (~1,8 s).

### Scénario 4 : Fermeture manuelle de la modale (edge case / watchdog)
**Parcours** : à l'étape « Mode Serein », refermer la modale Réglages au doigt
(drag down) sans taper « Terminer ».
**Résultat attendu** : le tour enchaîne vers la conclusion (carte « C'est parti »)
sans rester bloqué derrière un voile orphelin.

### Scénario 5 : Ne pas activer le mode
**Parcours** : à l'étape « Mode Serein », taper « Terminer » sans toucher le switch.
**Résultat attendu** : Mode Serein reste OFF (aucun commit automatique).

## Critères d'acceptation
- [ ] L'écran « Rester serein ? » n'apparaît plus en onboarding (avec ou sans anxiety).
- [ ] Le récap final n'a plus la ligne « Mode ».
- [ ] Le tour guidé a une dernière étape « Mode Serein » (6/6, bouton « Terminer »).
- [ ] La modale Réglages s'ouvre et la tuile Mode Serein est en surbrillance et actionnable.
- [ ] Aucun commit automatique du mode (OFF par défaut) ; activation persistée si l'utilisateur bascule.
- [ ] Console sans erreurs, réseau sans 4xx/5xx inattendus.

## Zones de risque
- **Reprise Hive** : `_currentVersion` bumpé 7 → 8 (le retrait de `digestMode`
  réindexe `finalize` 5 → 4). Un onboarding en cours d'une version antérieure est
  réinitialisé au boot — comportement attendu et conforme aux bumps précédents.
- **Overlay racine vs modale** : le spotlight (overlay racine) doit peindre
  par-dessus la modale `/settings` (même mécanique que la feuille favoris).
- **Ancre spotlight** : `tourSereinTileKey` n'est montée qu'à l'ouverture de la
  modale → jamais dupliquée.

## Dépendances
- Contrat API `POST /users/onboarding` **inchangé** : `digest_mode` reste envoyé
  (`pour_vous` par défaut → `serein_enabled=false`).
