# QA Handoff — La Grille du jour : dictionnaire + UX

> Stabilisation post-lancement de La Grille (suite du fix « écran gris »).

## Feature développée

Dictionnaire de validation complet (311 → 13 901 mots) + 3 améliorations UX :
1re lettre pré-remplie et verrouillée, auto-validation du mot, intro « Comment
jouer » (one-shot + icône « ? »).

## PR associée

À créer (branche `claude/grille-du-jour-crash-oDgO8`).

## Écrans impactés

| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| La Grille — Jeu | `/grille` | Modifié (saisie, clavier, app bar, intro) |
| Intro « Comment jouer » | bottom-sheet | Nouveau |
| Onglet Essentiel (carte CTA) | `/` | Inchangé fonctionnellement |

## Scénarios de test

### Scénario 1 : Happy path — jouer un mot
1. Ouvrir `/grille`.
2. La 1re lettre du mot est **déjà posée** dans la 1re case (ex. « B »).
3. Taper 5 lettres pour former un mot français de 6 lettres.
**Attendu** : à la dernière lettre saisie, l'essai **part automatiquement** (pas
besoin de « Entrer ») ; les cases se colorent (vert/jaune/gris).

### Scénario 2 : Mot français courant accepté (bug corrigé)
1. Compléter avec un mot courant comme MAISON, SOLEIL, CHEVAL, POMMES.
**Attendu** : le mot est **accepté** (essai consommé + coloration). Plus de « Ce
mot n'est pas distribué » sur un mot français valide de 6 lettres.

### Scénario 3 : 1re lettre verrouillée
1. Appuyer plusieurs fois sur « Effacer » (backspace).
**Attendu** : la saisie se vide jusqu'à la 1re lettre offerte **incluse, qui
reste** ; impossible de l'effacer.

### Scénario 4 : Intro one-shot + icône « ? »
1. Tout 1er accès à `/grille` (état SharedPreferences vierge).
**Attendu** : la sheet « Comment jouer » s'affiche **une seule fois**. Après
fermeture, ne réapparaît plus automatiquement.
2. Taper l'icône « ? » dans l'app bar.
**Attendu** : la sheet se ré-ouvre à la demande.

### Scénario 5 : Mot hors dictionnaire
1. Compléter avec une suite invalide (ex. « BXXXXX »).
**Attendu** : message « Ce mot n'est pas distribué — essaie un autre », ligne qui
secoue (shake), **essai non consommé**.

## Critères d'acceptation

- [ ] Un mot français courant de 6 lettres est accepté.
- [ ] La 1re lettre est pré-remplie et ne peut pas être effacée.
- [ ] Le mot se valide automatiquement à la dernière lettre.
- [ ] L'intro s'affiche 1 fois, puis est accessible via « ? ».
- [ ] Aucun crash / écran gris (cf. fix précédent toujours en place).

## Notes techniques

- Backend : la validation reste 100 % serveur (`grille_words_fr.txt`). Le fichier
  est généré via `scripts/build_grille_dictionary.py`.
- Tests : backend 28 passed ; mobile grille 36 passed (SDK 3.38.6) + analyze clean.
