# Bug: Clustering "couverture médiatique" sans filtre temporel

## Statut
- [x] En cours d'investigation
- [x] En cours de correction
- [x] Corrigé (date: 2026-07-14)

## Sévérité
- 🟡 Moyenne

## Description

Le clustering qui regroupe les articles par sujet (base des "Sujets du jour" /
détection trending = la "couverture médiatique" d'un sujet par plusieurs
sources) ne vérifiait jamais l'écart temporel entre deux articles avant de
les fusionner dans le même cluster. La fusion se fait uniquement sur la
similarité Jaccard des titres (`ImportanceDetector.build_topic_clusters`,
seuil `ScoringWeights.TOPIC_CLUSTER_THRESHOLD = 0.45`, tokenisation déléguée
à `app/services/text_similarity.py`).

Concrètement : si deux articles partagent assez de mots-clés de titre (sujet
récurrent, marronnier, dépêche republiée, gros titre générique...), ils
étaient regroupés dans le même "sujet" **quel que soit l'écart entre leurs
dates de publication**, tant qu'ils se trouvent dans le pool de candidats
fourni par l'appelant.

Ce n'était pas visible en prod car chaque appelant limite déjà la fenêtre de
récupération des contenus (7j pour le digest "sujets du jour" via
`DigestSelector._get_candidates(hours_lookback=168)`, ~48h pour le pipeline
éditorial). Mais rien dans `build_topic_clusters` lui-même n'empêchait de
mélanger un article du jour 1 et un article du jour 7, et toute évolution
future élargissant/supprimant ce filtre amont aurait réintroduit
silencieusement des clusters mêlant des sujets sans rapport temporel.

## Cause racine

`ImportanceDetector.build_topic_clusters()`
(`packages/api/app/services/briefing/importance_detector.py`) ne comparait
que les tokens de titre (similarité Jaccard) pour décider si un contenu
rejoint un cluster existant. Aucun champ temporel n'était lu ni comparé
pendant la boucle de clustering.

Le filtrage temporel n'existait qu'**en amont**, côté appelants
(`DigestSelector._get_candidates`, docstring `compute_global_context`), pas
dans la fonction de clustering elle-même — ce n'était pas une garantie
structurelle de l'algorithme.

## Solution

Ajout d'un filtre temporel **dans** `build_topic_clusters`, indépendant des
appelants :

1. **`packages/api/app/services/recommendation/scoring_config.py`**
   Nouvelle constante à côté de `TOPIC_CLUSTER_THRESHOLD` /
   `TOPIC_CLUSTER_MIN_TOKENS` / `TOPIC_CLUSTER_MAX_TOKENS` :
   `TOPIC_CLUSTER_MAX_TIME_GAP_HOURS = 720` (30 jours). Valeur volontairement
   large pour ne rien changer côté digest/éditorial (fenêtres amont ≤ 7j) :
   garde-fou structurel, pas un resserrement du comportement actuel.

2. **`packages/api/app/services/briefing/importance_detector.py`**
   - `build_topic_clusters()` accepte un nouveau paramètre optionnel
     `max_time_gap_hours` (défaut : la constante ci-dessus), surchargeable
     comme `similarity_threshold`.
   - Chaque cluster en cours de construction garde en mémoire ses bornes
     temporelles (`min_published_at` / `max_published_at`).
   - Un contenu candidat ne peut rejoindre un cluster que si son
     `published_at` est à ≤ `max_time_gap_hours` de la borne la plus proche
     du cluster (`_within_time_gap`), en plus du critère Jaccard existant.
   - Fail-open : si le contenu ou le cluster n'a pas de date exploitable
     (`published_at` absent/`None`, ou mock sans date réelle), le filtre
     temporel ne bloque pas la fusion — comportement historique préservé.
   - Gestion tz-aware/naive (`_normalize_published_at`), alignée avec le
     pattern déjà utilisé ailleurs dans le digest (ex.
     `TopicSelector._best_recency_bonus`).
   - N'affecte pas la logique de "fold" des agrégateurs (Reddit) ni le
     comptage par `source_domains` ajoutés depuis (Phase 2 de
     `build_topic_clusters`, indépendante de la Phase 1 modifiée ici).

3. **Tests** (`packages/api/tests/test_importance_detector.py`,
   classe `TestBuildTopicClustersTimeGap`)
   - Cas nominal : deux articles proches dans le temps + titres similaires →
     même cluster (comportement actuel inchangé).
   - Cas régression : deux articles à >30 jours d'écart + titres très
     similaires → clusters séparés.
   - Override de `max_time_gap_hours` (fenêtre resserrée à 6h).
   - Fail-open : contenu sans `published_at` → pas de blocage, pas de crash.
   - `published_at` naive (sans tzinfo) → pas de crash.
   - Suite `TestAggregatorFold` existante (fold Reddit) toujours verte, non
     affectée par ce changement.

## Fichiers concernés
- `packages/api/app/services/recommendation/scoring_config.py`
- `packages/api/app/services/briefing/importance_detector.py`
- `packages/api/tests/test_importance_detector.py`

## Hors scope

- `StoryService.cluster_hybrid` (`packages/api/app/services/story_service.py`,
  si présent sur cette base) : clustering distinct, sans appelant identifié
  dans la codebase — non traité ici.
- `DeepMatcher` (`packages/api/app/services/editorial/deep_matcher.py`) est
  volontairement **sans limite de temps** ("No time limit on deep articles,
  can be months old") — choix produit assumé (articles de fond), pas un bug.

## Notes
Demande utilisateur : "AJOUTER UN FILTRE TEMPOREL (même large, par exemple
d'1 mois ?) lors du clustering" — valeur par défaut : 30 jours (720h),
configurable via `ScoringWeights.TOPIC_CLUSTER_MAX_TIME_GAP_HOURS`.

**Note process** : la première itération de ce correctif avait été
développée par erreur sur une branche partie de `staging` (au lieu de
`main`), sur une version de `importance_detector.py` significativement plus
ancienne (avant l'extraction de `text_similarity.py` et l'ajout du fold
agrégateurs/`source_domains`). La branche a été réinitialisée sur `main` et
le correctif refait contre le code actuel.
