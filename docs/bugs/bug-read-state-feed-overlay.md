# Bug — marquage « Lu » qui disparaît au retour dans le feed

## Symptôme

Le bandeau « Lu » / « Lu jusqu'au bout » (`ReadingBadge`) sur les cartes du feed
Flâner disparaît de façon **inconstante** après qu'un article a été ouvert et lu.

## Racine

Le marquage « Lu » a deux niveaux :

1. **Optimiste local** — à l'ouverture (timer 1 s), `ReadSyncService.markConsumed`
   écrit dans la file Hive `pending_reads` et propage en mémoire via
   `_propagateLocal` : ajout de l'id à `consumedContentIdsProvider` (Set durable)
   + passage des items `feedProvider` en `status = consumed`.
2. **Backend** — POST `/api/contents/{id}/status` async ; le feed ne renvoie
   `status=consumed` qu'**après** que ce POST a abouti.

Le rendu de la carte feed lit **uniquement** `content.status` et **ne consulte
pas** `consumedContentIdsProvider`. Plusieurs chemins de reload reconstruisent
les `Content` depuis la réponse réseau (encore `unseen`) **sans** ré-appliquer le
set consommé :

| Chemin | Ré-appliquait l'état consommé ? |
|--------|---------------------------------|
| `_scheduleSilentRevalidation()` | ✅ oui (mais source = état courant uniquement) |
| `refresh()` (pull-to-refresh / reprise) | ❌ **non — culprit principal** |
| `loadMore()` | ❌ non |

⇒ Un `refresh()` déclenché entre le marquage « Lu » et l'aboutissement du POST
écrase le badge par la réponse serveur `unseen`. D'où l'inconstance.

Le Flux Continu n'est pas affecté : sa carte superpose déjà
`consumedContentIdsProvider` au rendu — pattern de résilience copié ici.

## Fix

`apps/mobile/lib/features/feed/providers/feed_provider.dart` : nouveau helper
`_overlayConsumed(items, carousels)` qui ré-applique `status = consumed` à partir
de `consumedContentIdsProvider` **∪** des items déjà consommés dans l'état
courant. Appliqué dans `refresh()`, `loadMore()` et
`_scheduleSilentRevalidation()` (dont il généralise la dérivation locale).

Aucun changement de widget, aucune migration, aucun appel réseau supplémentaire.

## Tests

- `test/features/feed/feed_consumed_overlay_test.dart` — refresh()/loadMore()
  préservent le statut consommé quand le serveur répond `unseen` ; no-op quand
  le set est vide.
- Non-régression : `feed_carousel_consumed_state_test.dart`,
  `feed_refresh_recovery_test.dart`.
