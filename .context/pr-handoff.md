# PR — Feed Fallback: follow CTA + UX polish

## Quoi
Introduce `is_followed_source` field end-to-end (backend → schema → mobile model) to power a contextual "Suivre" CTA in the feed. When a theme/topic filter is active, unfollowed sources show a tappable badge that opens the ArticleSheet — where a new "Suivre cette source" button lets the user follow without losing their active filter. Also fixes an overflow chip regression when filters are active.

## Pourquoi
When the feed is filtered by theme/topic, it returns articles from sources the user doesn't follow yet. There was no discovery path: the old follow button called `toggleTrust()` inline and immediately invalidated the feed, resetting the active filter. Now the user can discover and follow a source from within the ArticleSheet flow, and the feed refreshes cleanly (via `refresh()`) preserving the filter state.

## Fichiers modifiés

**Backend:**
- `packages/api/app/services/recommendation_service.py` — `_hydrate_user_status()` now accepts `followed_source_ids` and sets `is_followed_source` per item; theme filter now correctly passes to the fast-path (was missing); removed temp debug log
- `packages/api/app/schemas/content.py` — Added `is_followed_source: bool = False` to `ContentResponse`

**Mobile:**
- `apps/mobile/lib/features/feed/models/content_model.dart` — Added `isFollowedSource` field with JSON deserialization
- `apps/mobile/lib/features/feed/widgets/feed_card.dart` — Added `hasActiveFilter` + `onFollowSource` props; restyled "Suivre" badge to match TopicChip neutral design
- `apps/mobile/lib/features/feed/screens/feed_screen.dart` — Wired `onFollowSource` to open ArticleSheet + `refresh()` on dismiss; suppressed overflow chips when filter is active
- `apps/mobile/lib/features/custom_topics/widgets/topic_chip.dart` — Added "Suivre cette source" FilledButton in untrusted source branch (mirrors "Suivre ce sujet" pattern); `showArticleSheet` promoted to `Future<void>` to support await

## Zones à risque

1. **`showArticleSheet` signature change** (`void` → `Future<void>`) — downstream callers that don't await are fine (no breaking change), but any caller that relied on the `void` return type is now slightly different. Only `feed_screen.dart` explicitly awaits it.
2. **`ref.invalidate(userSourcesProvider)` in ArticleSheet** — triggers a provider rebuild which re-fetches the sources list. This is the same pattern used elsewhere in the sheet; should be safe but adds one extra network call on follow.
3. **`refresh()` called after sheet dismiss** — fires even if the user opened the sheet but didn't follow anything. Minor extra fetch, not a regression.

## Points d'attention pour le reviewer

1. **Fast-path theme fix (`recommendation_service.py:329`)** — `theme` was missing from the explicit-filter guard. Before this fix, a theme-filtered feed would go through full scoring instead of the chronological fast-path, and `followed_source_ids` was not passed to `_hydrate_user_status`. Low risk but worth confirming the condition is correct: `if source_uuid or theme or topic or entity or mode == RECENT`.
2. **Overflow chip suppression (`feed_screen.dart:~847`)** — When any filter is active, overflow chips are replaced with `SizedBox.shrink()`. Confirm the condition covers all 4 filter types (theme, topic, entity, sourceId).
3. **`isFollowedSource` only meaningful with local API** — prod backend doesn't yet return `is_followed_source`. The field defaults to `false`, so the badge simply won't appear against prod — no visual regression.

## Ce qui N'A PAS changé (mais pourrait sembler affecté)

- `feed_provider.dart` — `refresh()` was already implemented and preserves `_selectedTheme`/topic/entity. No changes needed.
- The starred icon for followed sources (`isFollowedSource == true` branch in `feed_card.dart`) — unchanged, still shows a fill star.
- `toggleTrust()` logic in `userSourcesProvider` — unchanged; the ArticleSheet already used it for mute, now also uses it for follow.

## Comment tester

**Contre prod (badge + sheet flow):**
```bash
cd apps/mobile
flutter run -d chrome --dart-define=API_BASE_URL=https://api.facteur.app/api/
# 1. Aller sur le feed → activer un filtre thème
# 2. Vérifier que les chips d'overflow ont disparu sur les cartes filtrées
# 3. Vérifier qu'un badge "Suivre +" apparaît sur les sources non suivies
#    (NOTE: contre prod, is_followed_source = false toujours → badge visible sur tout)
# 4. Tapper le badge → ArticleSheet s'ouvre
# 5. Voir "Suivre cette source" FilledButton + mute button en dessous
# 6. Fermer la sheet → feed refresh sans perdre le filtre actif
```

**Distinction suivie/non-suivie (nécessite API locale avec is_followed_source):**
```bash
cd packages/api && source venv/bin/activate
uvicorn app.main:app --reload --port 8080
# Lancer l'app contre localhost
# Les sources déjà suivies affichent une étoile ★ (pas le badge "Suivre")
# Les sources non suivies affichent le badge "Suivre +" quand un filtre est actif
```
