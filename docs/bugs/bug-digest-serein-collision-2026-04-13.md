# Bug — Le digest Serein reprend les articles du mode Normal (2026-04-13)

> **Critique** — utilisateur (Laurin) rapporte depuis 2 jours : "la pipeline de
> digest serein ne marche plus du tout — reprend les articles du mode Normal".
> En parallèle : demande produit pour réduire les faits divers + sport dans
> les deux modes.

## Symptôme

- Le digest serein contient sensiblement les mêmes 4-5 sujets que le digest
  Normal (pour_vous), avec uniquement le ton éditorial qui change.
- Demande produit additionnelle : limiter les faits divers + sport (pas de
  filtre actif aujourd'hui sur ces deux catégories).

## Cause racine

Pipeline éditorial actuel (`editorial_v1`, format de production) :

1. `digest_generation_job._get_global_candidates(session)` — fetch les **200
   articles les plus récents** (48h), **sans aucun filtrage serein**.
2. Boucle `for mode in ("pour_vous", "serein")` qui appelle
   `pipeline.compute_global_context(global_candidates, mode=mode)` avec **le
   même pool** pour les deux modes.
3. Dans `compute_global_context` :
   - `ImportanceDetector.build_topic_clusters(contents)` clusterise sur le pool
     non filtré → **clusters identiques entre les deux modes**.
   - `CurationService.select_topics(clusters, ...)` est **mode-agnostique** :
     le LLM choisit les "top 4 sujets les plus importants" sans tenir compte du
     mode → mêmes sujets sélectionnés pour pour_vous et serein.
   - `ActuMatcher.match_global` est aussi mode-agnostique → mêmes articles
     d'actu rattachés.
   - Seules différences mode-spécifiques :
     - À la une (`select_bonne_nouvelle` vs `select_a_la_une`)
     - Prompt d'écriture (ton)
     - `actu_decalee` ajouté pour serein
4. Le filtre serein (`apply_serein_filter` + `is_cluster_serein_compatible`)
   existe et fonctionne, mais il n'est appliqué **que** dans le legacy
   `topic_selector.py` (output_format=`topics_v1`), pas dans le pipeline
   éditorial.

Régression introduite par PR #374 (commit `fd072fd`, 2026-04-09) — le
pre-compute "dual variant" du contexte éditorial a été ajouté pour éviter le
on-demand sur le toggle serein, mais le pool global candidats n'a jamais été
filtré par mode.

Pourquoi "depuis 2 jours" ? Le pre-compute date du 09-04 mais le format
`editorial_v1` est devenu obligatoire/sticky avec PR #381 (10-04, "Prevent
digest format downgrade to legacy flat_v1"). Avant, un fallback `topics_v1`
était possible et le filtre serein s'appliquait via `topic_selector`. Depuis
#381, tous les digests sont en `editorial_v1`, ce qui expose le bug.

## Plan de correction

### Fix 1 — Filtrer le pool serein au niveau SQL (couche basse)

`packages/api/app/jobs/digest_generation_job.py:253-285`

`_get_global_candidates` reçoit un nouveau param `mode` :
- `mode == "serein"` → applique `apply_serein_filter` (defaults
  `SEREIN_EXCLUDED_THEMES` + keywords) sur la query SQLAlchemy avant
  `.limit(200)`.
- `mode == "pour_vous"` → comportement actuel (aucun filtre).

Appel mis à jour ligne 170 :
```python
for mode in ("pour_vous", "serein"):
    global_candidates = await self._get_global_candidates(session, mode=mode)
```

### Fix 2 — Filtrer les clusters au niveau pipeline (défense en profondeur)

`packages/api/app/services/editorial/pipeline.py:80-93`

Dans `compute_global_context`, après `build_topic_clusters` :
- Si `mode == "serein"`, exclure les clusters dont
  `is_cluster_serein_compatible(cluster) == False` AVANT toute sélection (À
  la une, curation LLM, etc.).
- Garantit que même si le filtre SQL laisse passer un article (cas
  `is_serene IS NULL` non taggé par LLM), le clustering ne regroupe pas un
  sujet anxiogène pour serein.

### Fix 3 — Pénaliser faits divers + sport dans LES DEUX modes

Nouvelle constante partagée dans
`packages/api/app/services/recommendation/filter_presets.py` :

```python
LOW_PRIORITY_KEYWORDS = [
    # Faits divers (déjà partiellement dans SEREIN_KEYWORDS, mais ici utilisé
    # aussi pour pour_vous comme déprioritisation, pas exclusion)
    "fait divers", "faits divers", "fait-divers",
    "accident", "incendie", "noyade", "agression",
    # Sport (NOUVEAU — pas exclu, juste déprioritisé)
    "football", "rugby", "tennis", "basket", "ligue 1", "ligue 2",
    "champions league", "ligue des champions", "roland-garros",
    "tour de france", "formule 1", "f1", "moto gp", "jeux olympiques",
    "psg", "om", "ol", "asse", "rcl", "asm",
]
```

Nouvelle fonction `is_low_priority_cluster(cluster) -> bool` (analogue à
`is_cluster_serein_compatible` : > 50% des articles matchent ou theme dominant
== "sport").

`packages/api/app/services/editorial/pipeline.py` — après clustering, **dans
les deux modes** :
- Identifier les low-priority clusters.
- Quota dur : maximum 1 cluster sport + 1 cluster faits divers parmi les 5
  sujets sélectionnés (configurable). Si le LLM en choisit plus, on remplace
  par le suivant trending non-low-priority.

### Fix 4 — Tests de régression

- `tests/test_digest_serein_pipeline.py` (nouveau) :
  - Un cluster contenant uniquement des articles "guerre Ukraine" est
    EXCLU du contexte serein (mais inclus pour pour_vous).
  - Le pool global serein ne contient pas d'articles `is_serene=False`.
  - Mode `serein` et `pour_vous` produisent des `subjects` différents quand
    des sujets anxiogènes dominent l'actualité.

- `tests/test_low_priority_cap.py` (nouveau) :
  - Si 4 clusters trending sont du sport, max 1 sport apparaît dans le digest.
  - Si seulement du sport est disponible, le quota est levé pour atteindre
    target_count (pas de digest vide).

## Fichiers modifiés

| Fichier | Modification |
|---------|--------------|
| `packages/api/app/jobs/digest_generation_job.py` | `_get_global_candidates(mode)` + appel boucle |
| `packages/api/app/services/editorial/pipeline.py` | Filtre serein post-clustering + cap low-priority |
| `packages/api/app/services/recommendation/filter_presets.py` | Nouvelles constantes + `is_low_priority_cluster` |
| `packages/api/tests/test_digest_serein_pipeline.py` | Nouveau (regression serein) |
| `packages/api/tests/test_low_priority_cap.py` | Nouveau (cap sport/faits divers) |

## Risques

- Pool serein réduit → si très peu d'articles `is_serene=True` ce matin,
  fallback keyword-only (déjà géré par `apply_serein_filter`). Si le pool est
  trop pauvre (< 5 clusters), la curation LLM logge déjà `insufficient_clusters`
  et utilise ce qu'elle a.
- Le cap sport/faits divers peut frustrer pendant une compétition majeure
  (Coupe du Monde) — mitigé par "À la une" qui reste libre + le quota n'est pas
  appliqué si TOUT est sport.
- Aucun changement au modèle DB, aucune migration Alembic.

## Status — 2026-04-13 (après implémentation)

- [x] Fix 1 — `_get_global_candidates(mode)` filtre serein au SQL.
- [x] Fix 2 — `compute_global_context` filtre les clusters non-serein-compatibles.
- [x] Fix 3 — cap sport + faits divers dans les deux modes, avec escape-hatch
  si le pool non-low-priority est trop pauvre (< 5 clusters).
- [x] Tests de régression (44/44 tests pertinents passent sur Python 3.12) :
  - `tests/test_low_priority_cap.py` — unit tests sur les helpers (12 tests).
  - `tests/editorial/test_pipeline_mode_filters.py` — intégration pipeline
    (4 tests : serein exclut les clusters anxieux, pour_vous les garde, cap
    sport limite à 1, cap skippé si pool trop petit).
  - `tests/test_digest_generation_job.py::TestGlobalCandidatePool` — 2
    nouveaux tests vérifient que la SQL du pool serein JOIN `sources` et
    filtre via `Source.theme`, et que le pool pour_vous reste inchangé.

## Hors scope

- Tagging `is_serene` pour les articles existants non taggés (job séparé).
- Refonte complète de la curation LLM (le prompt actuel reste mode-agnostique).
- Préférences utilisateur "muet sport" (déjà disponible via mute_themes).
