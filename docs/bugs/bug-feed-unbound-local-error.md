# Bug: UnboundLocalError sur l'endpoint /api/feed/

## Status: IDENTIFIÉ (Root Cause trouvée)

## Date: 29/01/2026

## Contexte
L'application mobile génère une `DioException` (Erreur 500) au chargement du feed. Ce bug est critique car il bloque l'utilisation principale de l'app pour les tests utilisateurs prévus demain.

## Analyse (Phase Measure)

### Symptôme
- Requête `GET /api/feed/` -> Retourne HTTP 500.
- Mobile : `DioException` error au chargement du feed.

### Root Cause
L'analyse montre une erreur `UnboundLocalError` dans `packages/api/app/services/recommendation_service.py` au sein de la méthode `get_feed()`.

Les variables `muted_sources`, `muted_themes` et `muted_topics` sont passées en arguments à `self._get_candidates()` (L137-140) **avant** d'être définies et assignées (L147-149).

```python
# L130 dans recommendation_service.py
candidates = await self._get_candidates(
    user_id, 
    limit_candidates=500,
    content_type=content_type,
    mode=mode,
    followed_source_ids=followed_source_ids,
    muted_sources=muted_sources, # 💥 UnboundLocalError ici
    muted_themes=muted_themes,
    muted_topics=muted_topics
)

# ...

# Les variables sont définies trop tard
muted_sources = set(personalization.muted_sources) if personalization and personalization.muted_sources else set()
muted_themes = set(t.lower() for t in personalization.muted_themes) if personalization and personalization.muted_themes else set()
muted_topics = set(t.lower() for t in personalization.muted_topics) if personalization and personalization.muted_topics else set()
```

### Script de reproduction
Un script de test `debug_feed_json.py` utilisant `TestClient` a permis de confirmer l'erreur localement :
`💥 Exception: cannot access local variable 'muted_sources' where it is not associated with a value`

## Solution proposée (Phase Decide)
Déplacer l'initialisation des sets de personnalisation avant l'appel à `_get_candidates()`.

## Historique
Ce bug semble être une régression introduite récemment lors de la modularisation du code de recommandation ou de l'ajout des filtres de personnalisation au niveau de la base de données.
