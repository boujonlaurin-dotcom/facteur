# Bug: Pull-to-refresh sans effet en mode chronologique

## Problème

Le geste pull-to-refresh sur le feed est censé renouveler les articles affichés.

- **Mode chronologique (défaut, aucun chip sélectionné)** : aucun effet visible, les mêmes articles réapparaissent dans le même ordre.
- **Seuls les articles lus (`SEEN`/`CONSUMED`) ou sauvegardés (`is_saved`)** disparaissent après refresh — parce qu'ils sont filtrés au niveau SQL pour une raison indépendante de l'impression.

## Root cause

Le geste pull-to-refresh déclenche `POST /feed/refresh` (`packages/api/app/routers/feed.py:228`) qui upsert `UserContentStatus.last_impressed_at = now()` pour chaque `content_id` visible (≥90% viewport, capturé côté mobile).

Cette valeur est uniquement consommée par l'`ImpressionLayer` (`packages/api/app/services/recommendation/layers/impression.py`) qui applique un malus de scoring tiéré (`-100 pts` si <1h, étiqueté _"invisible après refresh"_).

En mode chronologique, `_apply_chronological_diversification` (`packages/api/app/services/recommendation_service.py:756`) n'applique **aucun scoring** — il trie purement par `published_at DESC`. Le malus de l'`ImpressionLayer` est complètement ignoré. Le filtre d'exclusion SQL (`recommendation_service.py:2113-2143`) ne considérait que `is_hidden`, `is_saved`, `status IN (SEEN, CONSUMED)` — jamais `last_impressed_at`.

Le même problème touchait le marqueur `manually_impressed` ("j'ai déjà vu cet article") : `-120 pts` permanent en scoring, mais ignoré en chronologique.

## Fix appliqué

Étendre le filtre d'exclusion SQL de `_get_candidates` dans la branche "default feed" (sans filtre explicite) pour exclure :

- Les articles avec `last_impressed_at > now() - ScoringWeights.IMPRESSION_HIDE_WINDOW_HOURS` (1h)
- Les articles avec `manually_impressed = TRUE`

Alignement fidèle sur la sémantique `IMPRESSION_VERY_RECENT` déjà documentée dans `ScoringWeights`.

### Fichiers modifiés

- `packages/api/app/services/recommendation/scoring_config.py` — ajout constante `IMPRESSION_HIDE_WINDOW_HOURS = 1`
- `packages/api/app/services/recommendation_service.py` (branche default feed de `_get_candidates`) — extension du `or_()` dans `exists_stmt`

### Portée

Appliqué uniquement à la branche "default feed". Les filtres explicites (source / theme / topic / entity / keyword) conservent leur sémantique relâchée existante (l'utilisateur veut parcourir tout le contenu pour la facette sélectionnée).

## Tests

Voir `packages/api/tests/test_feed_chronological_refresh.py` :

- Articles impressionés <1h exclus du feed par défaut
- Articles impressionés >1h réapparaissent
- Filtre explicite par source ignore l'impression (articles encore visibles)
- `manually_impressed = TRUE` exclut l'article du feed par défaut

## Comportement de l'undo

`POST /feed/refresh/undo` restaure `last_impressed_at` à sa valeur précédente. Si la valeur restaurée est `NULL` ou >1h, l'article redevient éligible → l'undo fonctionne.
