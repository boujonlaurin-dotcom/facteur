# Bug + UX — La Grille : mots valides refusés & jeu peu fluide

**Statut** : Corrigé (en attente de PR)
**Branche** : `claude/grille-du-jour-crash-oDgO8`
**Sévérité** : 🟠 Élevée (jeu quasi-injouable au lancement)
**Contexte** : suite de [bug-grille-du-jour-crash.md](bug-grille-du-jour-crash.md)
(la grille s'affiche enfin, mais on ne peut pas y jouer correctement).

## Symptômes (remontés par le PO en prod)

1. **Bug bloquant** : entrer un mot renvoie « Ce mot n'est pas distribué — essaie
   un autre » pour des mots français pourtant valides (MAISON, SOLEIL, CHEVAL…).
2. **UX peu fluide** :
   - il faut **retaper soi-même** la « 1re lettre offerte » ;
   - il faut cliquer **« Entrer »** pour valider ;
   - **aucune explication** rapide n'introduit le jeu.

## Diagnostic

### #1 — Dictionnaire de validation trop petit (cause du bug)

`app/data/grille_words_fr.txt` ne contenait qu'une liste MVP « volontairement
compacte » : **311 mots** de 6 lettres réellement chargés. `submit_guess` rejette
donc en `hors_dictionnaire` la quasi-totalité des mots courants. Vérifié :

```
loaded 6-letter words: 311
MAISON REJECTED · SOLEIL REJECTED · CHEVAL REJECTED · POMMES REJECTED …
```

### #2 — 1re lettre jamais pré-saisie (UX)

`mot_grid.dart` n'affichait la lettre offerte en « hint » que tant que le draft
était vide ; le notifier démarrait le draft à `''`. La lettre n'était donc qu'un
indice visuel — il fallait la retaper.

### #3 — Validation manuelle uniquement + aucune intro (UX)

Le clavier exposait « Entrer » (`onEnter → submitGuess`) sans auto-validation, et
aucun écran/sheet n'expliquait les règles.

## Correctifs

### Backend — dictionnaire complet (13 901 mots)

- Nouveau `scripts/build_grille_dictionary.py` : génère `grille_words_fr.txt`
  depuis `words/an-array-of-french-words` (liste FR de référence, licence libre),
  filtré à 6 lettres après normalisation (MAJ, sans accent), **union des mots du
  jour seedés** (ré-ajoute EUROPE, nom propre absent de la source). Fichier
  committé (pas de fetch au runtime), régénérable.
- 311 → **13 901 mots**. MAISON/SOLEIL/CHEVAL/POMMES… désormais acceptés ;
  invariant seed conservé (CLIMAT, BUDGET… toujours présents) ; ZZZZZZ refusé.

### Mobile — 1re lettre pré-remplie + verrouillée

`grille_provider.dart` : le draft d'une ligne neuve démarre sur
`today.premiereLettre` (`_initialDraft`), re-posée après chaque essai valide.
`removeLetter` ne descend jamais sous la lettre verrouillée. L'utilisateur ne
tape plus que les 5 lettres restantes.

### Mobile — auto-validation

`grille_screen.dart` : dès que le mot atteint la longueur cible, `onKey` soumet
automatiquement (chemin commun `_submitGuess` partagé avec « Entrer », analytics
inchangés). « Entrer » reste disponible en repli.

### Mobile — intro one-shot + icône « ? »

- `grille_intro_provider.dart` : `grilleIntroSeenProvider` (FutureProvider) +
  `markGrilleIntroSeen()` (SharedPreferences, clé `grille_intro_seen`).
- `grille_intro_sheet.dart` : bottom-sheet « Comment jouer » (3 puces : 1re lettre
  offerte, le mot part tout seul, le sens des couleurs).
- Affichée **une fois** au 1er chargement de données ; ré-ouvrable via l'icône
  « ? » ajoutée à `GAppBar` (`onHelp`).

### Durcissement complémentaire

Les `.value?.today` restants des écrans Grille (leaderboard, share) et du
listener passent en `.valueOrNull` (même anti-pattern de re-lève que le crash
initial).

## Tests

- Backend : suite grille **28 passed** (dont `test_grille_logic` dictionnaire :
  chargé, 6 lettres, contient les mots seedés, ZZZZZZ exclu).
- Mobile : suite grille **36 passed** (SDK 3.38.6), `flutter analyze` clean.
  Tests notifier réécrits pour la 1re lettre verrouillée + ré-amorçage de ligne ;
  `grille_cta_card_test` (erreur → rien sans throw ; loading→data gated).
