# Bug: Trending chips affichent des titres complets + retournent 0 résultat

## Statut
- [x] En cours de correction
- [ ] Corrigé (date: YYYY-MM-DD)

## Sévérité
🟠 Haute (UX cassée sur une feature de découverte)

## Description

Dans la `SearchFilterSheet` du feed Actus (chip "Rechercher" du `feed_screen`), la section **"SUJETS DU MOMENT"** affiche des chips trending dont :

1. Le **label est le titre complet** du meilleur article du cluster (souvent tronqué par ellipsis), au lieu d'un mot-clé court type "Trump", "PSG", "Pékin" — incohérent avec les chips "RECHERCHES RÉCENTES" juste au-dessus.
2. Le tap sur la chip ne fait apparaître **aucun article**, généralement parce que le sujet trending vient d'une source que l'utilisateur ne suit pas.

## Étapes de reproduction

1. Ouvrir l'app, onglet Actus
2. Tap sur le chip "Rechercher" en haut du feed
3. Section "SUJETS DU MOMENT" : observer que les labels sont des phrases longues
4. Tap sur n'importe quel chip trending → feed vide

## Cause racine

**Côté backend (`packages/api/app/routers/feed.py:574-581`)** :
```python
response.append(
    TrendingTopicResponse(
        label=best_content.title,  # ← FULL TITLE (bug)
        keyword=_best_keyword(titles),
        ...
    )
)
```

`label` est utilisé pour l'affichage du chip mais reçoit le titre complet de l'article représentatif.

**Côté backend filtering (`packages/api/app/services/recommendation_service.py:2275-2310`)** :
- `apply_keyword_filter` fait un ILIKE sur `Content.title`
- La query est ensuite restreinte à `Source.id.in_(followed_source_ids)`
- Or les clusters trending sont calculés sur **toutes les sources des dernières 24h** (`get_trending_topics()`)
- → Si la source n'est pas suivie : 0 résultat

## Solution

### Backend
1. **Label = keyword extrait** : `feed.py:577` — `label=_best_keyword(titles).title()` au lieu de `label=best_content.title`
2. **Param `include_unfollowed`** : ajout sur l'endpoint `GET /feed/`. Quand `True` ET `keyword` présent, court-circuiter le filtre `followed_source_ids` dans `_get_candidates`.

### Mobile
1. `feedProvider.setKeyword(includeUnfollowed: bool)` propagation
2. `feed_repository` : passe `include_unfollowed` au query string
3. `search_filter_sheet` : `_TrendingChip.onTap` → variante qui marque le tap comme venant d'un trending → propagé jusqu'à la requête

La recherche libre (TextField) et les recherches récentes restent scopées aux sources suivies (comportement inchangé).

## Fichiers concernés

**Backend**
- `packages/api/app/routers/feed.py`
- `packages/api/app/services/recommendation_service.py`

**Mobile**
- `apps/mobile/lib/features/feed/providers/feed_provider.dart`
- `apps/mobile/lib/features/feed/repositories/feed_repository.dart`
- `apps/mobile/lib/features/feed/widgets/search_filter_sheet.dart`
- `apps/mobile/lib/features/feed/screens/feed_screen.dart`

## Notes

- Plan détaillé : `~/.claude/plans/system-instruction-you-are-working-proud-popcorn.md`
- Approche minimale (~30 lignes) — refonte hashtag-style/TF-IDF gardée hors scope
