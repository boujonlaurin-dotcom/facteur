# Maintenance — Mot du jour : anti-répétition par historique + vocabulaire élargi

## Problème

Le « Mot du jour » de La Grille revient parfois (2× le même mot sur une période
courte). Deux causes :

1. **Anti-répétition trop courte.** Le sélecteur hybride
   (`grille_selector.select_daily_word`) n'excluait que le mot de la **veille**
   (`_yesterday_word`, J-1). Le fallback seed (`grille_seed._fallback_word`)
   choisissait un mot par hash SHA256 de la date, **sans aucune** vérification
   d'historique.
2. **Pool de candidats étroit.** Le mot du jour est tiré de
   `grille_quality_words_fr.txt` (~168 mots) ; petit pool ⇒ collisions. Les pays/
   régions n'étaient que dans le dico de *validation*, pas dans le pool de
   *sélection*.

## Solution

### 1. Anti-répétition basée sur l'historique (sans migration)

La table `grille_puzzles` est déjà l'historique (1 mot par `puzzle_date`).
Nouveau helper `_recent_words(session, target_date, days=60)` → set des mots
normalisés des 60 derniers jours.

- `grille_selector._select_from_corpus` : `exclude` accepte désormais un
  `set[str]` (le mot du jour évite tous les mots récents, pas seulement J-1).
- `grille_seed._fallback_word` : devient history-aware — itère une séquence
  déterministe de hash salés (`sha256(date:i)`) et retient le **premier** mot du
  pool absent de l'historique récent. Déterminisme par date conservé.

Fenêtre : **60 jours** (~2 mois).

### 2. Vocabulaire élargi (pays/régions deviennent mots du jour ET réponses)

- `grille_quality_words_fr.txt` (pool de sélection) : +pays/régions/villes de
  6 lettres ⇒ plus de variété du mot du jour.
- `grille_proper_nouns_fr.txt` (dico de validation) : compléments pays/régions/
  capitales ⇒ acceptés comme réponses.
- Régénérer le dico committé :
  `cd packages/api && python -m scripts.build_grille_dictionary`

## Fichiers

- `packages/api/app/services/grille_selector.py`
- `packages/api/app/services/grille_seed.py`
- `packages/api/app/data/grille_quality_words_fr.txt`
- `packages/api/app/data/grille_proper_nouns_fr.txt`
- `packages/api/app/data/grille_words_fr.txt` (régénéré)
- Tests : `test_grille_selector.py`, `test_grille_seed.py`

## Vérification

```bash
cd packages/api && pytest tests/test_grille_selector.py tests/test_grille_seed.py \
  tests/test_grille_quality_pool.py tests/test_grille_logic.py -v
```

Pas de migration Alembic (lecture seule sur table existante). Aucun changement
mobile (sélection 100 % serveur).
