# QA Handoff — Progression PR1 (Mon courrier → Progression, gamification)

> Ce fichier est rempli par l'agent dev à la fin du développement, après validation du PO.
> Il sert d'input à la commande /validate-feature de l'agent QA.

## Feature développée
L'onglet « Mon courrier (progression) » devient « Progression » : grades de facteur dérivés des lettres complétées (Apprenti facteur → Maître facteur), badge de niveau discret sur l'avatar header, header gamifié sur l'écran Progression, teaser « Classement des Facteurs (BIENTÔT) », carte Progression en haut du Profil, avatar + grade dans la sheet Réglages, banner feed avec étape x/n et mini barre. 100 % client, zéro backend.

## PR associée
À créer via /go (base main). Branche : boujonlaurin-dotcom/progression-tab-gamification.

## Écrans impactés
| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Progression (ex Mon courrier) | /lettres | Modifié (titre, header gamifié, teaser classement, sections sans em-dash) |
| Profil | profil (depuis sheet Réglages) | Modifié (carte PROGRESSION en premier) |
| Sheet Réglages | bouton avatar header | Modifié (_ProfileBlock : RingAvatar + grade au lieu de « Plan gratuit ») |
| Feed Essentiel (banner lettres) | / (flâner/essentiel) | Modifié (kicker « ÉTAPE 01 · x/n », mini barre, pastille enveloppe) |
| Avatar header | toutes pages avec header | Modifié (badge numérique de niveau bas-droite) |

## Scénarios de test

### Scénario 1 : Écran Progression (happy path)
**Parcours** :
1. Ouvrir l'avatar header → Réglages → « Progression » (ou route /lettres)
2. Observer le header
**Résultat attendu** : titre « Progression » ; carte header avec avatar (initiales + badge niveau), titre de grade (ex « Apprenti facteur »), sous-ligne « NIVEAU 1 · 0 LETTRE CLASSÉE », barre de progression globale, « x/n étapes sur la lettre en cours » ; sections EN COURS / À VENIR / CLASSÉES sans tirets « — » ; teaser « CLASSEMENT DES FACTEURS » + « BIENTÔT » entre À VENIR et CLASSÉES, non tappable.

### Scénario 2 : Badge niveau sur l'avatar header
**Parcours** :
1. Sur le feed, observer l'avatar en haut à droite
2. Activer le Mode Serein dans Réglages, ré-observer
**Résultat attendu** : petit disque sombre bas-droite avec le chiffre du niveau (discret). En serein : le lotus remplace le badge niveau (un seul badge de coin).

### Scénario 3 : Profil + sheet Réglages
**Parcours** :
1. Avatar header → sheet Réglages : bloc profil
2. Tap sur le bloc profil → écran Profil
3. Tap sur la carte PROGRESSION
**Résultat attendu** : sheet : avatar RingAvatar (mêmes initiales que le header) + grade en sous-titre (plus de « Plan gratuit »). Profil : carte « PROGRESSION » en premier (avatar, grade, « Lettre 02 · x/y étapes », mini barre) ; tap → écran Progression.

### Scénario 4 : Banner feed
**Parcours** :
1. Avec une lettre active, aller sur l'Essentiel/Flâner
**Résultat attendu** : banner avec enveloppe sur pastille teintée, kicker « ÉTAPE 02 · x/n » (sans x/n si la lettre n'a pas d'actions), mini barre sous le titre ; dismiss X masque pour la session ; tap ouvre la lettre.

### Scénario 5 : Cas d'erreur
**Parcours** :
1. Couper le réseau, ouvrir /lettres
**Résultat attendu** : « Impossible de charger ta progression. » + Réessayer. Carte Profil et avatar : pas de badge ni carte (shrink silencieux), pas de crash.

## Critères d'acceptation
- [ ] Titre « Progression » partout côté UI (route /lettres inchangée)
- [ ] Grade correct : 0 lettre complétée = niveau 1 (letter_0 bienvenue ignorée), 1 = niveau 2, clamp à Maître facteur
- [ ] Badge niveau discret, serein prioritaire (jamais 2 badges)
- [ ] Aucun em-dash dans la nouvelle copy
- [ ] Dark mode (Encre & Nuit + Encre Pure) : nouveaux widgets lisibles
- [ ] Viewport 390x844, console sans erreurs, pas de 4xx/5xx inattendus

## Zones de risque
- Goldens RingAvatar : chemin non-serein sans level doit rester byte-identical (vérifié : goldens existants inchangés).
- Le grade est 100 % client : avec seulement letter_0 archivée (actions vides), niveau doit être 1, pas 2.
- Scroll de l'écran Progression : CLASSÉES passe sous le fold avec le nouveau header.

## Dépendances
Aucune : zéro backend, zéro migration. Endpoint lettres existant uniquement.
