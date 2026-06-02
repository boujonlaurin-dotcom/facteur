# Bug — Classement des « Actus du jour » incompréhensible

## Symptômes (rapportés par le PO)

1. Des sujets à **1 seul article** remontent très haut.
2. Un sujet **11 sources, polarisé, paru aujourd'hui** (qui « devrait être #1 »)
   se retrouve 10ème.
3. Les **faux-positifs France Culture** (séries type « Philippe Jaenada, l'art
   de la contre-enquête ») peuplent toujours la section, malgré le fix
   anti-doublon de mai 2026.

## Cause racine

« Actus du jour » = la `DigestTopicSection(kind: essentiel)` legacy, alimentée
par les `subjects` du pipeline éditorial, en deux étapes :

- **Étape 1 — sélection globale** (`editorial/pipeline.py::compute_global_context`).
- **Étape 2 — projection per-user** (`digest_selector.py::_project_editorial_for_user`,
  format `editorial_v2`, PR #740) : « À la Une » reste rang 1, **et tout le reste
  est ré-trié par le score de personnalisation** de l'article représentant.

Pourquoi les 3 symptômes :

- **#2** : l'étape 2 ne passe pas la couverture multi-sources au tri ; la
  personnalisation seule ordonne le rang 2+. La couverture a donc **zéro poids**.
- **#1** : l'étape 2 injecte des **sujets solo** (`source_count=1`) triés dans le
  même paquet par score perso → passent devant des sujets multi-sources.
- **#3** : `curation.py` filtre/trie par `len(source_ids)`, **pas** `source_domains`
  → les 2 sous-sources France Culture (même domaine `radiofrance.fr`) comptent
  comme un cluster « 2 sources ». Le fix `source_domains` (commit 2667003b) est
  appliqué partout ailleurs sauf ici. De plus `is_news_bulletin_title` ne matche
  pas les titres de **séries**.

## Décisions PO (validées)

- Ordre rang 2+ : **importance éditoriale d'abord** (couverture + récence +
  polarisation), personnalisation en **départage**.
- Sujets solo (1 source) : **relégués** — autorisés mais jamais au-dessus d'un
  sujet multi-sources.

## Correctif (PR `fix(digest)`)

- **A** — `curation.py` + `pipeline.py` : dédoublonnage par `source_domains`
  (plus `source_ids`) pour la porte multi-source, les tris et `source_count`.
- **B** — `filter_presets.py` : `is_news_bulletin_title` étendu aux séries
  nommées ; garde d'éligibilité cluster dans `compute_global_context` (écarte un
  cluster dont tous les contenus sont bulletin/série ou source denylistée).
- **C** — `digest_selector.py::_project_editorial_for_user` : tri par clé
  composite `(is_multi, importance, perso)`, « À la Une » rang 1 préservé.
  `importance = coverage + recency + polarization`, réutilise
  `helpers/coverage_score.py` + nouveau `helpers/editorial_ranking.py`.
- **D** — `digest_service.py` : bump `editorial_v2` → `editorial_v3` (sémantique
  d'ordre changée → régénération des digests cachés). Forme JSON inchangée.

Aucun DDL → pas de migration Alembic.

## Vérification terrain — cas « Philippe Jaenada » (lecture seule prod)

Requête read-only sur `contents` (2026-06-02) : le sujet est une **série de 5
épisodes France Culture**, tous portés par **le même `source_id`**
(`b9becd34-…`, domaine `radiofrance.fr`) :

| titre | source | published_at |
|-------|--------|--------------|
| …, l'art de la contre-enquête 1/5 … | France Culture | 2026-06-01 |
| … 2/5 … | France Culture | 2026-06-02 |
| … 3/5 / 4/5 / 5/5 … | France Culture | 06-03 → 06-05 |

**Conclusion** : ce n'est **pas** « 2 feeds même domaine » (hypothèse initiale du
plan pour #3) mais **1 source / 5 articles**. → c'est la **Partie B** qui le
règle : le pattern série `,\s*l['']art (de|…)` matche les 5 titres, et la garde
d'éligibilité cluster (`_is_non_actu_cluster`) écarte le cluster (100 % bulletins/
séries). L'article légitime « …ou le grand art de la contre-enquête » (Slate, sans
virgule + `l'art`) n'est **pas** matché → pas de faux-positif.

La **Partie A** (dédoublonnage par domaine) reste un durcissement correct et
nécessaire (le cas « 2 feeds radiofrance.fr » existe ailleurs), mais n'était pas
le levier décisif pour ce cas précis.
