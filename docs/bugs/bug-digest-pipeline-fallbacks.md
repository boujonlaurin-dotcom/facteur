# Bug: Digest — Fallbacks "promesse revue de presse"

**Type:** Bug
**Branche:** `boujonlaurin-dotcom/digest-fallbacks`
**Date:** 2026-05-02

---

## Symptômes (digest 2026-05-02 utilisateur Laurin)

- 4 articles au lieu de 5 (rang 5 silencieusement perdu)
- Tous les rangs à `source_count=2`, aucun marqué `is_a_la_une=true`
- Article 4 = vidéo YouTube BLAST (`content_type='youtube'`) avec un "miroir" Reddit qui pointe vers la même vidéo → la couverture "2 médias" est en réalité 1 source d'info
- Pas de Bonne Nouvelle du jour : digest serene `failed` (1 user sur 75 aujourd'hui)

## Causes racines

### C1 — Pas d'À la Une si aucun cluster ≥3 sources (jours creux)
`importance_detector.is_trending` exige ≥3 sources. `pipeline.py:171-202` ne sélectionne A la Une que parmi `trending_clusters`. Le 2026-05-02 (samedi 1er mai voisin, 783 articles vs 1500 en semaine), aucun cluster n'atteint 3 sources → `a_la_une_topic=None`, rang 1 redevient un sujet ordinaire.

### C2 — Sujet sans actu/deep silencieusement droppé
`digest_service.py:1762-1769` filtre `subjects` sans article. Aucun fallback ne tente de remplacer le sujet par le 6e cluster. Résultat : digest à 4 articles au lieu de 5 sans visibilité côté observabilité.

### C3 — YouTube/vidéos non filtrés au pass 1
`actu_matcher._find_best_article_global` (`actu_matcher.py:289-304`) tri par `(thumbnail_url, published_at)` sans filtre `content_type`. La vidéo YouTube gagne contre l'article texte miroir.

### C4 — Miroirs Reddit/agrégateurs comptés comme sources distinctes
Le cluster "Trump enrichissement" contient :
- BLAST `youtube` (`youtube.com/watch?v=lUZCxnhYW3I`)
- Reddit r/france `article` (`reddit.com/.../trump_un_mandat_au_service_de_son_enrichissement/`) — partage la même vidéo

`source_count=2` est faux : c'est 1 source. Le clustering ne distingue pas les agrégateurs.

### C5 — Serene on-demand fragile
`digest_selector.py:309-340` : si cache éditorial process-local froid (autre worker que le batch), on recompute sur le pool **user-personnalisé** (`_get_candidates`) qui peut être vide. La pipeline retourne `None` → `"selector returned empty digest"`. 12 retries en boucle dans `_process_batch`/regen on-demand.

## Plan technique (P0 + P1)

### F1 — Fallback À la Une (`pipeline.py`)
Si `trending_clusters` vide MAIS un cluster `is_multi_source` (≥2) existe : promouvoir le top en À la Une avec `selection_reason = "Repris par X médias aujourd'hui"`.

### F2 — Fallback sujet de remplacement (`pipeline.py` + `digest_service.py`)
Lorsque `actu_matcher.match_global` n'a pas trouvé d'article et qu'aucun deep n'a matché pour un sujet, demander à `curation` un sujet de remplacement parmi les clusters non encore retenus. Ne droper qu'en dernier recours (et alors logger en `error`, pas `warning`).

### F3 — Filtre YouTube actu (`actu_matcher.py`)
Au pass 1 de `_find_best_article_global`, exclure `content_type ∈ {youtube, video}`. Garder en pass 2 (relaxed) si vraiment aucun candidat texte.

### F4 — Fold miroirs (`importance_detector.py` + clustering)
Dans `build_topic_clusters`, après agrégation, dédupliquer les `source_ids` qui pointent vers un domaine externe identique (Reddit URL → host extrait). Compter une seule fois "même contenu".

### F5 — Robustifier serene on-demand (`digest_selector.py`)
- Si on-demand serene avec cache miss : essayer d'abord un pool global (mode-aware) avant le pool user-personnalisé
- Cap retries au job batch (le selector lui-même n'a pas à boucler)
- Si pipeline retourne None : renvoyer un digest serene minimal (juste pépite/coup de cœur) plutôt que `None` qui propage `"empty digest"`

## Vérification

Tests unitaires (`tests/services/editorial/`) :
- À la Une fallback (cluster ≥2 mais aucun ≥3) → rang 1 marqué `is_a_la_une`
- Sujet sans actu/deep → remplacement par cluster suivant si disponible
- Cluster {YouTube, article texte} → actu_article = article texte
- Cluster {BLAST direct, Reddit-share-de-BLAST} → `source_count=1` après fold
- Serene on-demand pool vide → fallback graceful (pas d'exception, pas de `None`)

Test E2E : régénération forcée pour Laurin sur 2026-05-02 → 5 sujets, A la Une présent (top cluster ≥2 sources), Bonne Nouvelle ou message dégradé propre.
