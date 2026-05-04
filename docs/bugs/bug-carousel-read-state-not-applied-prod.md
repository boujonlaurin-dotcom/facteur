# Bug — Carousel Read State Not Applied in Production

## Symptôme

Après ouverture (tap → article reader) d'une carte du carrousel dans le feed, la carte ne montre aucun changement visuel : pas de badge vert "Lu", pas d'opacity réduite, pas de compteur `X/N` dans l'en-tête. Reproductible après hot-restart et en build prod (TestFlight).

**PR antérieure** : #550 (mergée) avait correctement implémenté la logique optimiste dans `feed_provider.dart` et les widgets. Les tests unitaires passaient. Le bug était systémique, pas dans la logique d'isolation.

---

## Root Cause

### Primaire — Race Condition dans `_scheduleSilentRevalidation`

`_scheduleSilentRevalidation()` lance un microtask dès le build du feed quand le cache Hive a >= 60s. Ce microtask démarre un appel réseau asynchrone (`await _fetchPage(page: 1)`).

Séquence problématique :

1. Build depuis cache Hive → carousels : `status: unseen`
2. Microtask fire → `await _fetchPage(page: 1)` démarre (500ms–2s réseau)
3. User tape carte carrousel → `markContentAsConsumed` → state optimiste : `status: consumed` ✅
4. Réponse API retourne → `state = AsyncData(FeedState(carousels: response.carousels))` → **écrase** avec données API (status: unseen depuis server cache 30s, ou item exclu par backend car consommé)
5. User revient → `updateContent(updated)` lit `c.status = unseen` depuis état courant → badge disparu ❌

Le guard aux lignes 191–198 ne vérifiait que les filtres actifs, pas l'état consumed.

**Note backend** : `recommendation_service.py:1147–1155` exclut les items consumed des carousels sur les fetches frais. Donc la réponse API peut soit retourner l'item sans lui (carousel réduit) soit avec `status: unseen` via le server cache 30s. Dans les deux cas l'optimistic update était perdu.

### Secondaire — Cache Hive Non Mis à Jour (Piste 3)

Après `markContentAsConsumed`, `_persistDefaultFeedCache` n'était jamais rappelé. Le cache Hive gardait l'ancienne réponse API. Au prochain cold start, les items réapparaissaient avec `status: unseen`.

### Mineur — `clearDefaultViewCache` Manquant (Piste 4)

`markContentAsConsumed` ne appelait pas `FeedRepository.clearDefaultViewCache()`, contrairement à `toggleSave` et `toggleLike`. La fenêtre de dedupe 5s pouvait retourner les données pré-consommation.

---

## Fix (PR #XXX)

**Fichier** : `apps/mobile/lib/features/feed/providers/feed_provider.dart`

### Fix 1 — Merge consumed status dans `_scheduleSilentRevalidation`

Après le retour de l'API, on collecte les IDs consumed depuis l'état **courant** (post-await, pour capturer tout tap survenu pendant l'appel réseau) et on les ré-applique aux items de la réponse API avant d'écrire le state.

```dart
final consumedIds = <String>{
  ...?(currentState?.items.where(...consumed...).map((c) => c.id)),
  ...?(currentState?.carousels.expand(...items consumed...).map((c) => c.id)),
};
Content preserve(Content c) => consumedIds.contains(c.id)
    ? c.copyWith(status: ContentStatus.consumed) : c;
state = AsyncData(FeedState(
  items: response.items.map(preserve).toList(),
  carousels: response.carousels.map((car) =>
      car.copyWith(items: car.items.map(preserve).toList())).toList(),
));
```

### Fix 2 — Invalider cache après consumption

Dans `markContentAsConsumed`, après `updateContentStatus` réussit :
- `FeedRepository.clearDefaultViewCache()` (dedupe 5s)
- `feedCacheServiceProvider?.clearForUser(userId)` (Hive 10min)

Le prochain cold start fetche donc l'API fraîche, qui retourne le carousel sans l'item consommé (ou avec `status: consumed`).

---

## Test Ajouté

`apps/mobile/test/features/feed/feed_carousel_consumed_state_test.dart` :
- **"silent revalidation merge preserves consumed status from current state"** : simule la race condition (state courant = consumed, réponse fraîche = unseen), vérifie que le merge conserve `consumed`.

---

## Critères de Validation

1. Ouvrir une carte du carrousel feed
2. Revenir → badge vert "Lu" + opacity 0.6 + compteur `1/N` ✅
3. Attendre 5s sans interaction → badge reste ✅
4. Kill app + relance → au chargement initial, item absent du carousel (exclu par backend) ou badge présent (si API rapide) ✅
