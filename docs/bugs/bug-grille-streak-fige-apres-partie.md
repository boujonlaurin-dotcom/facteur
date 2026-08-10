# Bug — le streak « Mot du jour » reste figé sur la valeur de la veille après la partie

- **Signalé par** : PO, 2026-08-10 (« l'indicateur semble statique et ne pas évoluer »)
- **Impact utilisateur** : après avoir joué, l'app affiche « 1 jours d'affilée » alors que
  la série réelle vaut 2, 3, … — le compteur paraît codé en dur
- **Statut** : corrigé

## Symptôme

L'utilisateur joue le mot du jour, puis lit « **1 jours** d'affilée. Reviens demain pour
tenir la série ». Le lendemain, même partie jouée, même « 1 jours ». Le compteur ne semble
jamais monter à 2 ou 3.

## Ce qui n'est PAS en cause

Le calcul serveur est correct et couvert par des tests. Une simulation multi-jours du flux
réel (ouverture d'écran → partie gagnée → classement, 3 jours consécutifs) donne bien
`1, 2, 3` côté `GET /grille/today/leaderboard`. `_compute_streak` remonte les
`puzzle_date` distincts réellement joués et n'a pas de défaut.

## Cause racine

Le streak **exposé par `GET /grille/today` est calculé avant que la partie du jour ne soit
jouée**, et rien ne le rafraîchit ensuite :

1. `GrilleService.get_today` appelle `_get_or_create_game` (ligne `in_progress`,
   `attempts = 0`) **puis** `_compute_streak`. Or une ligne `attempts = 0`/`in_progress`
   est délibérément exclue du décompte (cf.
   [bug-grille-streak-compte-consultation-sans-jeu](bug-grille-streak-compte-consultation-sans-jeu.md)) :
   la réponse porte donc la série **arrêtée à hier**.
2. `POST /grille/today/guess` et `POST /grille/today/reveal` ne renvoient pas de `streak`.
   `GrilleNotifier` recopie l'état local avec `copyWith` → `today.streak` **conserve la
   valeur d'avant-partie**.
3. `grilleProvider` n'est pas `autoDispose` : la valeur périmée survit jusqu'au prochain
   cold start de l'app.

Conséquence, pour un utilisateur qui joue tous les jours, la valeur lue **juste après la
partie** est systématiquement celle de la veille (`N-1`) :

| Jour | Série réelle | Affiché après la partie (app bar / carte CTA / pied « déjà joué ») |
|------|--------------|--------------------------------------------------------------------|
| J1   | 1            | **0**                                                              |
| J2   | 2            | **1**                                                              |
| J3   | 3            | **2**                                                              |

L'écran Classement (`_StreakStrip`), lui, affiche la bonne valeur : son streak vient de
`GET /grille/today/leaderboard`, appelé une fois la partie terminée.

Deux copies aggravaient la lecture « valeur en dur » :

- `« $streak jours d'affilée »` (écran Classement) et `« $streak jours »` (pied « déjà
  joué » de la carte CTA) forçaient le pluriel → « **1 jours** » au lieu de « 1 jour ».

## Correctif

**Mobile uniquement** — aucun changement de contrat API, aucune migration.

1. `GrilleNotifier._refreshStreak()` : dès que la partie se termine (`submitGuess` avec
   `isFinished`, ou `reveal`), un `getToday()` silencieux re-synchronise **le seul champ
   `streak`** de l'état courant (sans `AsyncLoading`, sans toucher aux essais/statut, donc
   sans clignotement ni écrasement de `justFinished`). Le serveur, lui, compte désormais la
   partie du jour puisqu'elle est terminée. Best-effort : un échec réseau laisse
   simplement l'ancienne valeur, recalée au prochain chargement.
2. `formatStreakDays()` (`grille_format.dart`) : « 0 jour » / « 1 jour » / « 3 jours »,
   utilisé par l'écran Classement et le pied de la carte CTA.

Non retenu : afficher le +1 dès le **1er essai** accepté (le serveur compte la journée dès
`attempts > 0`). C'est un choix produit — la série ne se « gagne » visuellement qu'une fois
la grille terminée.

## Tests

- `packages/api/tests/test_grille_api.py::test_today_streak_includes_today_once_finished`
  (nouveau) — verrouille le contrat serveur sur lequel repose le re-fetch mobile : avant la
  partie `GET /today` renvoie `N-1`, après la partie `N`.
- `apps/mobile/test/features/grille/providers/grille_provider_test.dart` — le streak est
  re-synchronisé après une partie gagnée et après un `reveal` ; aucun re-fetch tant que la
  partie est en cours ; un échec réseau du re-fetch ne casse pas l'état.
- `apps/mobile/test/features/grille/utils/grille_utils_test.dart` — pluriel de
  `formatStreakDays`.
- `apps/mobile/test/features/grille/widgets/grille_cta_card_test.dart` — le pied « déjà
  joué » écrit « 1 jour ».
