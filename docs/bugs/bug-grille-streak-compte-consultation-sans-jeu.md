# Bug — le streak « Mot du jour » compte les jours simplement consultés, pas joués

- **Signalé par** : PO, 2026-07-27
- **Impact utilisateur** : streak affiché (`GAppBar`) incohérent avec l'assiduité réelle
- **Statut** : corrigé

## Symptôme

Le compteur de streak affiché en haut de l'écran « La Grille du jour » ne reflète pas
fidèlement les jours où l'utilisateur a réellement joué.

## Cause racine

`GrilleService._compute_streak` (`packages/api/app/services/grille_service.py`) dérive le
streak des `puzzle_date` distincts présents dans `grille_game_states`, sans filtrer sur une
partie réellement jouée :

```python
rows = (
    await self.db.scalars(
        select(GrilleGameState.puzzle_date)
        .where(GrilleGameState.user_id == user_id)
        .distinct()
    )
).all()
```

Or `GrilleService.get_today` appelle `_get_or_create_game` (qui insère une ligne
`status=in_progress, attempts=0`) **avant** de calculer le streak. Résultat : ouvrir
simplement l'écran de la grille — sans taper une seule lettre — suffit à faire compter la
journée comme « jouée » dans le streak, pour toujours (la ligne reste en base).

## Correctif

`_compute_streak` filtre désormais sur les lignes ayant un essai soumis
(`attempts > 0`) ou un statut qui n'est plus `in_progress` (couvre `reveal_word`, qui
termine une partie sans jamais incrémenter `attempts` — « donner sa langue au chat » doit
rester compté comme joué, cf. test `test_reveal_preserves_streak`) :

```python
.where(
    GrilleGameState.user_id == user_id,
    or_(
        GrilleGameState.attempts > 0,
        GrilleGameState.status != STATUS_IN_PROGRESS,
    ),
)
```

Aucune migration : pas de nouvelle colonne, juste un filtre de requête.

## Tests

`packages/api/tests/test_grille_api.py::test_streak_excludes_screen_view_without_attempt`
(nouveau) — une ligne `in_progress`/`attempts=0` créée par simple ouverture d'écran
n'interrompt/n'alimente pas le streak. Suite streak complète (5 tests, dont
`test_reveal_preserves_streak` en non-régression) : `PASSED`.
