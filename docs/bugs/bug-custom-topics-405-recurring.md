# Bug : Custom Topics 405 Method Not Allowed (Récurrent)

**Type** : Bug (récurrent — 3e occurrence)
**Sévérité** : Critique (fonctionnalité cassée en prod)
**Date** : 2026-04-06

## Symptôme

L'ajout de sujets personnalisés (questionnaire + "Mes intérêts") génère une erreur "Method Not Allowed" (405). Tous les `POST` vers `/api/personalization/topics/` et `/api/personalization/topics/disambiguate` échouent.

## Cause racine

### Régression par merge — commit `c626c0ad` (PR #332)

Le commit `c626c0ad` a écrasé le fix précédent (`d7bb6028`, PR #307) en :

1. **Supprimant** l'endpoint `POST /disambiguate` (désambiguïsation LLM)
2. **Remontant** les routes paramétrées `PUT /{topic_id}` et `DELETE /{topic_id}` AVANT les routes statiques `/suggestions`
3. **Supprimant** le champ `priority_multiplier` de `CreateTopicRequest`
4. **Supprimant** le nettoyage `UserSubtopic` lors du delete

### Mécanisme du 405

FastAPI matche les routes dans l'ordre d'enregistrement. Quand `/{topic_id}` est avant `/disambiguate` ou `/suggestions` :

- `POST /disambiguate` → matché par `/{topic_id}` (topic_id="disambiguate") → seuls PUT/DELETE existent → **405**
- L'endpoint `/disambiguate` n'existe même plus sur main

### Pourquoi ce bug revient

Le pattern `/{topic_id}` dans un même router est un **piège à merge** : tout commit qui touche `custom_topics.py` risque de réordonner les routes ou de perdre des endpoints lors de la résolution de conflits.

## Plan technique

### 1. Restaurer les endpoints et l'ordre des routes (Backend)

Dans `packages/api/app/routers/custom_topics.py` :

- **Restaurer** l'endpoint `POST /disambiguate` avec `DisambiguateRequest` et `DisambiguationSuggestionResponse`
- **Restaurer** `priority_multiplier` dans `CreateTopicRequest` avec validation
- **Restaurer** le nettoyage `UserSubtopic` dans `delete_topic`
- **Garantir** l'ordre : routes statiques (`/popular-entities`, `/`, `/disambiguate`, `/suggestions`) AVANT routes paramétrées (`/{topic_id}`)

### 2. Protection anti-régression (test)

Ajouter un test `test_route_ordering.py` qui :
- Vérifie que `POST /disambiguate` ne retourne pas 405
- Vérifie que `GET /suggestions` ne retourne pas 405
- Vérifie que `POST /` (create topic) ne retourne pas 405

### 3. Commentaire garde-fou dans le code

Ajouter un commentaire explicite en haut du fichier et autour des routes paramétrées pour prévenir les futures régressions.

## Fichiers impactés

| Fichier | Modification |
|---------|-------------|
| `packages/api/app/routers/custom_topics.py` | Restaurer /disambiguate, priority_multiplier, route ordering, UserSubtopic cleanup |
| `packages/api/tests/test_custom_topics_routes.py` | Nouveau — test anti-régression 405 |
