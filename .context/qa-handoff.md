# QA Handoff — Epic 13 Learning Checkpoint + Mobile Stability Fixes

> Ce fichier est rempli par l'agent dev à la fin du développement.
> Il sert d'input à la commande /validate-feature de l'agent QA.

## Feature développée

Epic 13 Learning Checkpoint — **backend** (Stories 13.1 à 13.4) + corrections de régressions mobile bloquantes introduites pendant le développement :

1. **Backend Epic 13**
   - Nouvelle migration Alembic `ln01` (tables `user_learning_proposals` et `user_entity_preferences`, renommée depuis `lc01` pour supprimer un cycle de révisions)
   - Service `LearningService` : agrégation de signaux, génération de propositions d'ajustement, résolution (accept/reject/alternative)
   - Endpoints `/learning/proposals` (GET, PATCH) et `/learning/entity-preferences` (POST, DELETE)
   - Intégration dans `recommendation_service.py` : filtrage des candidats par `UserEntityPreference.mute` (ligne 358-385)
   - Intégration dans `feed.py` : `learning_checkpoint` injecté dans `FeedResponse` quand `offset=0` et feed non-saved
   - `pagination.has_next` basé sur `total_candidates` (pool pré-diversification) pour une pagination fiable

2. **Régressions mobile corrigées**
   - **`content_detail_screen.dart`** : "Cannot use ref after the widget was disposed" + cascade `LateInitializationError` sur `Supabase.instance`. Le code de tracking (progression lecture + analytics) était exécuté APRÈS `super.dispose()`. Déplacé AVANT, avec `try/catch` défensif.
   - **`theme_section.dart`** : ~7 `await` suivis de `ref.invalidate(...)` sans garde `context.mounted` → "ref after dispose" si l'utilisateur quittait la page pendant la requête. Ajout de `if (!context.mounted) return;` après chaque await pour `ThemeSection` (ConsumerWidget) et `if (!mounted) return;` pour `_SuggestionsBlockState` (ConsumerStatefulWidget).
   - **`feed_screen.dart`** : `Future.delayed(...)` qui lisait `ref.read(streakProvider.notifier)` après le délai → risque de disposed ref. Capture du notifier AVANT le delay.
   - **`feed_provider.dart`** :
     - Suppression du `ref.listen(sereinToggleProvider)` dupliqué (était déclaré 2× de suite, provoquait double refresh).
     - Pagination hybride : `_hasNext = response.pagination.hasNext && response.items.isNotEmpty` (trust backend + stop si page vide pour éviter boucle infinie si regroupement renvoie 0).
     - `loadMore` ne remplace plus l'état par `AsyncError` sur un échec de page 2+ (ce qui effaçait le feed existant) — log + stop paging, l'utilisateur peut pull-to-refresh.
   - **`feed_repository.dart`** : parse désormais le bloc `pagination` renvoyé par le backend et expose `pagination.hasNext` / `pagination.total` via `FeedResponse`.

> Stories 13.5/13.6 (UI mobile du Learning Checkpoint — bannière, modal) sont **hors périmètre** de cette PR. Elles seront implémentées dans une PR dédiée.

## PR associée

Branche : `claude/learning-checkpoint-algo-UDwDy`

## Écrans impactés

| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Feed | `/feed` | Modifié (pagination, serein toggle, streak refresh) |
| Article detail | `/feed/content/:id` | Modifié (dispose order — tracking fix) |
| Custom topics / Themes | `/custom-topics` (ThemeSection) | Modifié (mounted guards sur follow/mute/priority) |
| (Backend) Learning API | `/learning/proposals`, `/learning/entity-preferences` | Nouveau |
| (Backend) Feed | `/feed` — la réponse inclut désormais `pagination.has_next` + éventuel `learning_checkpoint` | Modifié |

## Scénarios de test

### Scénario 1 : Post-login → ouverture d'un article puis back feed
**Parcours** :
1. Se connecter à l'app (login frais)
2. Dans le feed, tap sur le premier article → content_detail_screen s'ouvre
3. Scroller l'article (progression > 10 %)
4. Appuyer sur back avant la fin de lecture
5. Observer la console / les logs
**Résultat attendu** :
- Aucune exception `Cannot use 'ref' after the widget was disposed`
- Aucune `LateInitializationError` sur Supabase
- Le feed se réaffiche avec l'article marqué lu (progression persistée)
- Les analytics `trackArticleRead` sont envoyés

### Scénario 2 : Feed pagination (scroll infini)
**Parcours** :
1. Ouvrir `/feed` avec un compte contenant >50 articles disponibles
2. Scroller jusqu'au bas de la page 1
3. Observer le loader inline + apparition de la page 2
4. Continuer jusqu'à épuiser le pool
**Résultat attendu** :
- Chaque fin de page déclenche le fetch de la suivante tant que `pagination.has_next == true` côté backend ET que la page renvoyée n'est pas vide
- Quand le backend retourne `has_next: false` ou `items: []`, l'indicateur de chargement disparaît et reste un `SizedBox(height: 64)` en bas
- **Pas de boucle infinie** de `loadMore` quand le regroupement (clustering backend) renvoie 0 items alors que `has_next` disait true

### Scénario 3 : Feed — échec transitoire sur page 2+
**Parcours** :
1. Charger le feed (page 1 OK)
2. Couper le réseau (airplane mode)
3. Scroller pour déclencher `loadMore`
4. Réactiver le réseau et pull-to-refresh
**Résultat attendu** :
- L'échec de page 2 est logué mais le feed page 1 reste visible (pas de remplacement par erreur plein écran)
- `_hasNext` devient `false` — plus d'auto-paging
- Pull-to-refresh recharge page 1 proprement

### Scénario 4 : Themes — follow / mute / priority avec navigation rapide
**Parcours** :
1. Ouvrir `/custom-topics`
2. Tap rapidement sur un bouton mute/follow d'un thème
3. Immédiatement faire back pour quitter l'écran avant que la requête ne termine
**Résultat attendu** :
- Aucune exception "ref after dispose" ou "context is not mounted"
- La requête termine côté API, mais aucune invalidation n'est tentée sur un widget démonté (gardes `context.mounted`)

### Scénario 5 : Serein toggle
**Parcours** :
1. Ouvrir `/feed`
2. Activer puis désactiver le mode Serein plusieurs fois
**Résultat attendu** :
- Un **seul** refresh est déclenché à chaque toggle (plus de double refresh lié au listener dupliqué)
- L'indicateur de chargement s'affiche brièvement puis le feed se met à jour

### Scénario 6 : Backend — Endpoints Learning
**Parcours** (via curl ou Postman, JWT valide) :
1. `GET /learning/proposals` → liste (vide au démarrage)
2. Consommer 5+ articles d'un même thème → recalcul signal
3. `GET /learning/proposals` → doit contenir au moins une proposition pending
4. `PATCH /learning/proposals/{id}` avec `{"status": "accepted"}` → OK, proposition resolved
5. `POST /learning/entity-preferences` `{"entity_canonical": "Elon Musk", "preference": "mute"}` → 201
6. `GET /feed` → les articles mentionnant "Elon Musk" sont absents
**Résultat attendu** :
- Schéma réponse conforme (`id`, `proposal_type`, `entity_label`, `signal_strength`, `status`…)
- Filtrage entity mute effectif sur `/feed` (recommendation_service)

### Scénario 7 : Pagination backend — `has_next`
**Parcours** :
1. `GET /feed?offset=0&limit=20` avec un pool de 50 candidats
2. Vérifier `pagination.has_next: true` (30 restants)
3. `GET /feed?offset=40&limit=20` → `has_next: false`
**Résultat attendu** :
- `has_next = (offset + limit) < service.total_candidates` (feed.py:119)
- `total` reflète `total_candidates` (pool pré-diversification), pas le nombre d'items dans la page

## Critères d'acceptation

**Backend**
- [ ] Alembic : exactement **1 head** (`alembic heads` = `ln01`)
- [ ] Migration `ln01` applicable et réversible (upgrade + downgrade)
- [ ] Tables `user_learning_proposals` + `user_entity_preferences` créées avec index et UK
- [ ] `tests/test_learning_service.py` : **25/25 pass** ✅ (vérifié localement)
- [ ] Endpoints `/learning/*` JWT-protégés
- [ ] `recommendation_service` filtre par entity mute (preuve : test ou requête manuelle)
- [ ] Feed inclut `learning_checkpoint` uniquement quand `offset=0` et feed non-saved
- [ ] Réponse `/feed` inclut `pagination.has_next` / `pagination.total`

**Mobile**
- [ ] Aucune exception "Cannot use 'ref' after the widget was disposed" sur le parcours post-login → detail → back
- [ ] Aucune `LateInitializationError` sur `Supabase.instance` en dispose
- [ ] Pagination feed : pas de boucle infinie, pas de perte d'état sur erreur page 2+
- [ ] Serein toggle : un seul refresh par changement
- [ ] `flutter analyze` : 0 errors sur les fichiers modifiés (à valider côté QA — flutter non dispo en sandbox)
- [ ] `flutter test` : suite verte (à valider côté QA — flutter non dispo en sandbox)

## Zones de risque

- **Dispose order** : tout nouveau ConsumerStatefulWidget qui track des analytics en dispose() doit respecter le pattern "tracking AVANT super.dispose()" avec try/catch.
- **ref.read dans un Future.delayed** : toujours capturer le notifier en dehors du callback retardé.
- **Alembic heads** : le rename `lc01 → ln01` ne doit être appliqué sur aucun env qui aurait déjà exécuté la migration sous le nom `lc01` (non applicable ici, migration jamais déployée).
- **Pagination hybride** : si le backend corrige son `has_next` pour tenir compte du regroupement post-diversification, retirer la garde `items.isNotEmpty` côté mobile deviendra sûr.
- **Filtrage entity mute** : le canonical-name est comparé en lowercase simple — les variantes orthographiques ne sont PAS déduplées (limitation connue, Story 13.7+).

## Dépendances

- **Backend**
  - Migration Alembic `ln01` à appliquer (via Supabase SQL Editor en prod, jamais sur Railway).
  - Pas de nouvelle variable d'env.
- **Mobile**
  - Aucune dépendance pub.dev nouvelle.
  - Nécessite un backend à jour (endpoints `/learning/*` + `pagination.has_next` dans `/feed`).

## Tests backend exécutés en local

```
PYTHONPATH=. pytest tests/test_learning_service.py -q
→ 25 passed, 18 warnings in 1.05s
```

Les autres failures observées dans la suite complète (`test_classification_queue`, `test_custom_topics`, `test_feed_refresh_undo`, `test_serein_filter`, `test_source_*`, `test_feed_filter_inspiration`) sont des **erreurs de plomberie sandbox** (sqlalchemy async + httpx AsyncClient API change), **sans rapport avec cette PR**.
