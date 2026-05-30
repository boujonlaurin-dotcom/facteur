# PR 1 · Backend « La Grille du jour » (Story 24.1)

Fondation serveur du jeu **La Grille du jour** (Wordle postal Facteur). Le mobile (PR 2) consomme ce contrat — **cette PR merge en premier.**

## Contenu
- **Modèles** : `grille_puzzles` (puzzle global daté, mot secret serveur) + `grille_game_states` (1 partie/user/jour, unicité `(user_id, puzzle_date)`).
- **Migration** `gr01_la_grille_du_jour` (additive, `down_revision = cl01_drop_daily_top3`, 1 head).
- **Dictionnaire FR** embarqué (`app/data/grille_words_fr.txt`) chargé en `frozenset` au boot.
- **Logique** (`grille_text` + `grille_service`) :
  - `compute_tiles` à **comptage d'occurrences** (corrige la version simplifiée du proto, ne sur-colore plus les lettres doublées).
  - Validation 100 % serveur : longueur / hors-dictionnaire (essai non consommé), rejeu interdit (409), `solved`/`failed`.
  - Streak **dérivé** des parties (ne touche pas `UserStreak`).
  - Classement quotidien : `distribution`, `percentile`, podium anonymisé (initiales via hash quotidien salé, `Toi` au rang du joueur).
- **3 endpoints** sous `/api/grille` : `GET /today`, `POST /today/guess`, `GET /today/leaderboard`.
- **Seed** : `app/data/grille_puzzles_seed.json` (≥ J+14) + `scripts/seed_grille_puzzles.py` (idempotent, assert word ∈ dico).

## ⚠️ Note pour PR 2 (mobile)
Les chemins réels sont préfixés `/api` (convention repo) : **`/api/grille/today`**, `/api/grille/today/guess`, `/api/grille/today/leaderboard` — et non `/grille/...`. Clés JSON = noms FR exacts (`dateAffichee`, `nbEssais`, `premiereLettre`, `prochainMotDansSec`, …). Le mot (`mot`) et le `pourquoi` ne sont jamais renvoyés tant que `statut == in_progress`.

## Décisions (défauts confirmés par le PO au GO)
- Préfixe API `/api/grille` (et non `/grille`).
- Podium anonymisé via **hash quotidien salé** de `user_id` → 2 initiales non nominatives.
- Ajout colonne `date_affichee` (absente du proto, requise par le masthead).

## Tests / VERIFY
- `pytest tests/test_grille_logic.py tests/test_grille_api.py` → **24 passed**.
- Suite complète backend → **1383 passed, 1 skipped, 2 xfailed** (aucune régression).
- Alembic : `upgrade head` + `downgrade -1` + re-upgrade OK sur DB **vide**.
- Seed rejoué → idempotent (0 créés / 15 maj).

Story : `docs/stories/core/24.1.la-grille-du-jour-backend.md`.
