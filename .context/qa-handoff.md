# QA Handoff — « Le mot du jour » : refonte UX & ajustements (Story 24.3)

> Rempli par l'agent dev. Input de /validate-feature (Chrome 390×844).

## Feature développée
Refonte UX du module « Le mot du jour » (ex-« La Grille du jour ») : renommage,
validation par « Entrée » (fin de l'auto-validation), animation de victoire
(confettis + rebond), option « Donner sa langue au chat », lien explicite avec
les Actus du jour, fix couleur dark mode (tuile « présent »), carte persistante
dans le feed, lien de partage qui ouvre l'app, et graphique de classement
recalibré.

## PR associée
À créer (cf. `/go`).

## Écrans impactés
| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Jeu / Résultat / Déjà-joué | `/grille` | Modifié |
| Classement | `/grille/leaderboard` | Modifié (graphique) |
| Partage | `/grille/share` | Modifié (titre + lien) |
| Feed / fin de tournée | `/flux-continu` | Modifié (carte CTA persistante) |

## Scénarios de test

### Scénario 1 : Validation par Entrée + clavier
1. Ouvrir `/grille`, saisir un mot complet (6 lettres).
2. **Attendu** : PAS d'auto-validation ; la touche `↵` (à droite, `⌫` à gauche)
   se remplit en ocre primaire et pulse ; l'essai ne part qu'au tap sur `↵`.

### Scénario 2 : Victoire
1. Trouver le mot.
2. **Attendu** : burst de confettis + rebond de la ligne gagnante sur l'écran
   Résultat ; bouton « Lire les actus du jour » présent ; console sans erreurs.

### Scénario 3 : Dark mode (couleur « présent »)
1. Passer l'app en thème sombre, jouer un mot avec une bonne lettre mal placée.
2. **Attendu** : tuile/touche « présent » = **jaune/ocre** (plus rouge) ;
   « placé » = vert.

### Scénario 4 : Donner sa langue au chat
1. En cours de jeu, menu `⋯` (app bar) → « Donner sa langue au chat » → confirmer.
2. **Attendu** : mot révélé, écran Résultat mode « révélé » (cachet « ? RÉVÉLÉ »,
   copie « Tu as donné ta langue au chat. »), **bouton classement masqué**,
   streak préservé.

### Scénario 5 : Lien Actus + mini-CTA
1. Sur l'écran Résultat → « Lire les actus du jour » → navigue vers `/flux-continu`.
2. En jeu, après 2 essais non gagnants → mini-CTA « le mot est dans l'actu du
   jour — aller lire » s'affiche.

### Scénario 6 : Carte persistante
1. Compléter la grille, puis fermer la tournée (ClosingCard).
2. **Attendu** : la carte « Le mot du jour » reste dans le feed (état « déjà
   jouée »).

### Scénario 7 : Partage → ouvre l'app
1. Écran Partage / Classement → « Défier un·e ami·e » (copie le lien).
2. **Attendu** : lien = `io.supabase.facteur://grille` (ouvre `/grille` dans
   l'app via deep-link, plus le site facteur.app).

### Scénario 8 : Classement
1. Terminer la partie, ouvrir le classement.
2. **Attendu** : barres de distribution proportionnelles (la plus fréquente =
   pleine largeur), compactes ; ligne « toi » surlignée.

## Critères d'acceptation
- [ ] « Le mot du jour » partout / « Trouve le mot du jour » sur la carte feed
- [ ] Validation uniquement via « Entrée », touche en avant + pulse
- [ ] Confettis + rebond à la victoire (reduce-motion safe)
- [ ] « Langue au chat » : mot révélé, non classé, streak conservé
- [ ] Tuile « présent » jaune/ocre en dark mode
- [ ] Carte reste dans le feed après fermeture
- [ ] Lien de partage ouvre la grille dans l'app
- [ ] Barres de classement aux bons ordres de grandeur

## Zones de risque
- Reduce-motion (`MediaQuery.disableAnimations`) : pas de pulse/confetti/rebond.
- Cold-load d'une partie « révélée » : retombe sur l'écran Déjà-joué standard.

## Dépendances
- Backend : nouvel endpoint `POST /api/grille/today/reveal` (aucune migration).
- Le deep-link entrant `io.supabase.facteur://grille` est géré par
  `DeepLinkService` + redirect GoRouter.
