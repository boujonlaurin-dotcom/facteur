# Volet « Pas de recul » (deep reco) dans le reader — backend + mobile

## Résumé
Réactive le moteur « Pas de recul » (désactivé au post-unification cleanup) et
l'expose **par article ouvert** : l'endpoint `GET /contents/{id}/perspectives`
renvoie une recommandation d'article de fond (`deep_recommendation`), et le
reader la rend tout en bas, sous la « Couverture médiatique ». Premier étage de
la dimension « deep » de l'app. **Aucune migration Alembic.**

## Changements — Backend
- **`deep_matcher.py`** : nouvelle méthode `match_for_content(content)` — variante
  reader de `match_for_topics`. Dérive un pseudo-angle depuis l'article ouvert
  (titre + topics + theme), réutilise tel quel `_load_deep_articles` / `_prefilter`
  / `_expand_query` / `_llm_evaluate` / `_fallback_pick`. Exclut l'article ouvert
  **et** tout article du même cluster (pas une autre dépêche du même évènement).
  Helper `_entity_names` tolérant aux deux formats d'entités (JSON & `name:type`).
- **`routers/contents.py`** : cache dédié `_deep_reco_cache` (TTL 2h) + sentinelle
  `_DEEP_NO_MATCH` + garde in-flight. Le matching tourne en **background**
  (`_compute_deep_reco_background`) car il fait 2 appels LLM — on ne bloque pas
  l'ouverture du reader, exactement comme le pattern partiel/refresh des
  perspectives. `deep_recommendation` (dict|null) + `deep_pending` (bool) sont
  attachés aux 3 chemins de retour (cache hit / snapshot digest / live) et
  préservés à travers le refresh background.
- **`editorial_prompts.yaml`** : prompt `deep_matching` décommenté. **`config.py`** :
  commentaire TODO nettoyé.

## Changements — Mobile
- **`feed_repository.dart`** : modèle `DeepRecommendation` + champs
  `deepRecommendation` / `deepPending` sur `PerspectivesResponse` (+ parsing JSON,
  rétro-compatible : clés absentes ⇒ `null` / `false`).
- **`deep_recommendation_card.dart`** (nouveau) : carte « Pas de recul »
  (médaillon 🔭, titre, raison de match, source ; tap → ouvre l'article dans le
  reader). Palette dérivée des tokens `colors.*` ⇒ cohérent clair/sombre/oled.
- **`content_detail_screen.dart`** : rendu de la carte en bas du reader (gardé par
  `deep_recommendation != null && !_isExternal`), `_openDeepReco()` (push route
  `content/:id`), et refetch one-shot étendu à `deepPending` (pas de double appel
  LLM-coûteux).

## Contrat API (nouveaux champs de la réponse perspectives)
```
deep_recommendation: {
  content_id, title, url, thumbnail_url, content_type,
  source_id, source_name, source_logo_url, published_at,
  match_reason, description
} | null
deep_pending: bool   # true = matching en cours en background → mobile doit refetch
```

## Tests
- `tests/editorial/test_deep_matcher.py` : `TestMatchForContent` (sélection LLM,
  exclusion self, exclusion même cluster, pool vide, pivot maigre, fallback no-LLM)
  + `TestEntityNames`. **25/25 verts.**
- `tests/routers/test_contents_deep_reco.py` (nouveau) : helpers `_deep_reco_to_dict`,
  `_apply_deep_from_cache`, `_attach_deep_recommendation`. **8/8 verts.**
- `deep_recommendation_card_test.dart` (nouveau) + `feed_repository_perspectives_test.dart`
  (étendu : parsing `deep_recommendation` / `deep_pending`).
- 1 seul head Alembic, aucune migration.

## Vérif manuelle suggérée (avant merge)
`uvicorn` local + `curl /contents/{id}/perspectives` → `deep_pending:true` au 1er
appel, puis `deep_recommendation` peuplé au 2e (article avec sujet couvert par une
source `source_tier='deep'`) ; `null` sur un fait divers.

## Suite
- Chantier curation deep (séparé) : labelliser plus de sources `source_tier='deep'`
  + chaînes YouTube + reportages.
