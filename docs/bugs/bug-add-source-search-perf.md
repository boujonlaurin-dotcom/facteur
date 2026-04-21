# Bug : Perf & UX de "Ajout de source custom"

**Date** : 2026-04-21
**Statut** : En cours
**Impact** : Élevé — friction majeure sur le flux d'onboarding/ajout de sources

---

## Symptômes

1. **[Critique] Recherche lente même pour une source déjà en DB.** Une recherche "Mediapart" (source curated) prend 2–5 s alors qu'un seul appel DB devrait suffire. Les utilisateurs perçoivent la fonctionnalité comme cassée.
2. **Badges types décoratifs.** Les 5 badges affichés sous la recherche (Médias, Newsletters, YouTube, Reddit, Podcasts) ne sont pas cliquables — l'utilisateur ne peut pas affiner sa recherche.
3. **Loading messages "fake".** Les 3 messages défilent toutes les 1.5 s, donnant l'impression d'une animation canned qui ne reflète pas un vrai travail en cours.

---

## Cause racine

### Problème 1
`SmartSourceSearchService.search()` (`packages/api/app/services/search/smart_source_search.py:118`) exécute un pipeline cascadant :

```
cache → catalog (ILIKE) → YouTube API → Reddit → Brave → Google News → Mistral
```

Le short-circuit après catalog n'est déclenché que si `curated_count >= 3` (`MIN_RESULTS_FOR_SHORTCIRCUIT = 3`). Pour une requête qui matche 1–2 sources curated (cas le plus courant : on cherche *une* source précise), le pipeline continue à travers tous les layers externes, ajoutant ~2–5 s de latence sans bénéfice.

### Problème 2
`_buildSourceTypesRow()` dans `apps/mobile/lib/features/sources/screens/add_source_screen.dart:417` rend les badges comme de simples `Icon + Text`, sans `onTap`. Le backend ne supporte pas non plus de filtre par `content_type`.

### Problème 3
`source_result_skeleton.dart:40` utilise un `Timer.periodic(Duration(milliseconds: 500))` qui change les dots toutes les 500 ms et le message tous les 3 dots (1.5 s). Avec seulement 3 messages, le cycle complet fait 4.5 s — si la requête prend 3 s, l'utilisateur voit 2 messages se succéder rapidement puis le premier revenir, ce qui brise l'illusion.

---

## Résolution

### Backend

**Short-circuit agressif + gating par type + mode expand.**

- Nouveau prédicat `_is_strong_catalog_match(result, normalized)` : match nom exact / préfixe / word-boundary.
- Si catalog retourne ≥1 strong match ET `expand=False` → `_finalize()` immédiat.
- Nouveau param `content_type: Literal["article","youtube","reddit","podcast"] | None = None` :
  - Filtre le catalog (`Source.type == content_type`).
  - Skip les layers non pertinents (ex. `content_type="youtube"` → skip Brave/GoogleNews/Mistral).
  - "Médias" et "Newsletters" mappent tous les deux sur `article` côté mobile (pas d'heuristique domaine pour l'instant).
- Nouveau param `expand: bool = False` : ignore le short-circuit catalog, force le pipeline complet. Respecte toujours `content_type`.
- Cache key élargie (inclut `content_type` + `expand`) pour éviter les collisions.

### Mobile

- Badges convertis en `ChoiceChip`s single-select (`_selectedContentType`).
- Nouveau bouton "Élargir la recherche" affiché sous les résultats quand `layers_called == ["catalog"]` ET `_expanded == false`. Tap → relance la recherche avec `expand: true`.
- Skeleton : timer 500 ms → 800 ms, message change tous les 6 ticks (~4.8 s), 6 messages variés au lieu de 3.

---

## Fichiers impactés

**Backend**
- `packages/api/app/schemas/source.py`
- `packages/api/app/services/search/smart_source_search.py`
- `packages/api/app/services/search/cache.py`
- `packages/api/app/routers/sources.py`
- `packages/api/tests/services/search/test_smart_source_search.py`

**Mobile**
- `apps/mobile/lib/features/sources/repositories/sources_repository.dart`
- `apps/mobile/lib/features/sources/providers/sources_providers.dart`
- `apps/mobile/lib/features/sources/screens/add_source_screen.dart`
- `apps/mobile/lib/features/sources/widgets/source_result_skeleton.dart`

---

## Vérification

**Unitaire :** `pytest -v packages/api/tests/services/search/test_smart_source_search.py`, `flutter test`, `flutter analyze`.

**Manuel (QA Chrome, viewport 390×844) :**
1. "Mediapart" → résultats <500 ms, bouton "Élargir" visible.
2. Tap "Élargir" → nouveaux résultats externes, bouton disparaît.
3. Chip "YouTube" + "fireship" → seul YouTube layer appelé, latence réduite.
4. "Médias" puis "Newsletters" → mêmes résultats (ARTICLE).
5. "xyzzyq" → pipeline complet, 6 messages du skeleton observables, rotation ~4.8 s.

---

## Trade-offs

- **Short-circuit agressif** peut masquer une meilleure source externe → mitigé par le bouton "Élargir".
- **Cache key élargie** multiplie les entrées ×10 max → acceptable (TTL 24 h).
- **Streaming SSE** écarté : le bouton "Élargir" donne un équivalent sans nouvelle infra.
