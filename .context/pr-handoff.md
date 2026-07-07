# fix(search): recherche de sources — pertinence + latence (backend, sans migration)

Corrige 3 axes de la recherche de sources (« Ajouter une source » / Veille), confirmés par
`source_search_logs`. Une seule cause racine côté orchestrateur
`SmartSourceSearchService.search`. 100 % backend, additif, **aucune migration**.

## Changements

1. **URL collée → détection de flux directe.** `_classify_query` renvoyait `url_like` sans
   jamais brancher le résultat → une URL partait en recherche texte (9-31 s, 0 résultat). Nouvelle
   branche `(0)` dans `search()` : normalise l'URL, `_detect_with_root_fallback`, renvoie 1 résultat
   `layer="direct"` et saute Brave/GNews/Mistral. Reddit exclu (path `/r/<sub>` non résolu au root).
   Pas de flux → fall-through au pipeline normal (jamais vide). Nouveau score `direct: 0.85`.

2. **Le filtre content_type déclenche sa couche.** Le chip « YouTube » + `micode` n'appelait
   jamais la couche (heuristique texte ratée). Désormais `content_type == "youtube"` déclenche
   **toujours** la couche ; `None` garde l'heuristique. Idem Reddit. `external_eligible` déjà False
   avec un filtre → externes correctement sautés, pas de double-fire.

3. **Gate de pertinence sur les résultats EXTERNES.** Fonction pure `_is_relevant_external`
   (token overlap / substring dé-espacé / trigrammes de caractères). N'utilise **pas**
   `jaccard_similarity` (qui drop <3 char + chiffres → tuerait `bdm`/`11`). Appliquée au point de
   convergence `_detect_candidates` (Brave/GNews) + inline dans `_search_mistral`. **Jamais** sur le
   catalogue. Validé 7/7 sur cas prod : garde onemondial↔onzemondial, snowball, blog-moderateur→BDM,
   micode, usine-digitale ; drop insight-clement→BDM, hypertext→BBF.

4. **Dédup par feed_url + host.** `seen_urls` (URL exacte) → helper `_dedup_add` : dédup par
   `feed_url` (toujours) + par host (externes seulement, hors `_PATH_LEVEL_PLATFORMS`). Deux chaînes
   YouTube / deux Substack survivent ; « blog modérateur » ne renvoie plus BDM ×2.

## Tests

- `test_smart_source_search.py` : `_classify_query` (url_like/free_text/youtube/reddit),
  `_is_relevant_external` (7 cas prod + vides + token court `bdm`), `_dedup_add` (feed_url, host
  externe, 2 chaînes YouTube, 2 catalogue même host), gate `_detect_candidates` on/off-topic.
- `test_smart_source_search_session.py` : URL avec flux → `layers=["direct"]`, catalog/brave non
  appelés ; URL sans flux → fall-through catalogue ; `content_type=youtube`+`micode` → couche
  youtube, externes sautés ; régression `content_type=None`+`micode` → youtube non déclenché.
- `pytest tests/services/search/` : **95 passed**. `ruff` : clean.

## Différé (suivi PO, hors PR)

Ajout d'Onze Mondial au catalogue + colonne `aliases text[]` (équivalence chiffre↔mot `11`↔`onze`).
Le gate est calibré pour au moins **ne pas casser** onemondial → onzemondial (trigramme ~0,55).
