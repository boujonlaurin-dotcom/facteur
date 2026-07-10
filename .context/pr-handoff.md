# feat(media-eval): fondations (schéma, contrats, moteur d'évaluation)

PR 1/2 du MVP pipeline d'évaluation des médias C1–C11 (story
`docs/stories/core/media-eval.0.mvp-pipeline-evaluation.md`, plan PO validé le
07/07/2026). Entièrement testable offline — la collecte (voie A + agents) et le
run pilote arrivent en PR 2.

## Ce que fait cette PR

### Docs source de vérité PO (`docs/media-eval/`)
- Import de la méthodologie v1.1.1 (PDF converti) + amendements v1.2 actés
  (raccourci JTI, pondération débunkages, temporalité, lettres A–E).
- Import de l'architecture collecte ≠ évaluation du 07/07/2026.
- **Rubriques évaluateur** (`rubrics/_common.md` + `C1/C5/C7/C8/C9/C11.md`) :
  barème §4 verbatim + section « Sortie structurée » (`determinations`
  énumérables). Lues verbatim par `build_eval_input.py` ;
  `version_prompt` = sha256 du fichier rubrique.

### Schéma DB (migration `me01_media_eval_tables`, additive, RLS deny-all)
7 tables `media_eval_*` : medias (référentiel niveau domaine), snapshots,
corpus_articles (créée mais vide en V0), signaux (pivot ; statuts
present/absent_verifie/partiel/bloque_acces ; dédup idempotente par
`dedupe_key`), debunkages (qualification émetteur/gravité/suite, couple 1-1
avec un signal C1), evaluations (score NULL si N/A, `signal_ids` cités,
version_methodo/version_prompt), fiches (renormalisation, lettre, confiance).
- `down_revision = ue01_user_entity_affinity` → 1 seul head. Idempotente
  (guard `has_table` par table — la chaîne boote sur les 2 services Railway).
  RLS pattern `sec02` (ENABLE + REVOKE anon/authenticated, aucune policy).
- Modèles `app/models/media_eval.py` (StrEnum locaux, enums VARCHAR non natifs,
  pattern `Source`), enregistrés dans `app/models/__init__.py`.

### Contrats & garde-fous codés en dur (`scripts/media_eval/`)
- `schemas.py` : `BAREMES` (100 pts), `CRITERES_VAGUE_1` (54 pts),
  `NIVEAU_SCORES` C9/C11, `LETTRES`, registre `type_signal` figé, artefacts
  Pydantic (Signal/Debunkage/Evaluation + enveloppes batch, GoldenSet).
  **`derive_score(critere, determinations)`** : le score faisant foi est dérivé
  par code, jamais choisi par le LLM (philosophie `derive_reliability`).
  Validator dur : éval sans `signal_ids_cites` rejetée (sauf flag
  `donnees_insuffisantes` → N/A). `poids_emetteur` des débunkages dérivé par
  code (`arcom/justice/cdjm` = fort, fact-checkers de médias concurrents =
  moyen, inconnu = faible).
- `garde_fous.py` (fonctions pures) : fraîcheur 730 j (signaux événementiels
  seulement, structurels constatés à date), fallback C1 (< 3 débunkages/2 ans),
  raccourci JTI, corroboration (score plein sans ≥ 2 domaines sources
  indépendants → palier inférieur + flag `corroboration_insuffisante`),
  `bloque_acces` → `revue_requise` — jamais converti en 0.

### Scripts moteur (dry-run par défaut, `--apply` gardé, `--allow-prod` hors DB test)
`seed_medias.py` (2 pilotes : cnews.fr audiovisuel, reporterre.net presse en
ligne) · `ingest_artifacts.py` (valide en bloc puis insère — un artefact
invalide = exit non-zéro, rien d'écrit ; idempotent) · `build_eval_input.py`
(exports `eval_inputs/<media>_<critere>.json` + garde-fous amont) ·
`ingest_evaluations.py` (garde-fous aval : signal_ids existants / bon média /
bon critère, score dérivé, corroboration, statuts) · `synthese_fiche.py`
(renormalisation sur les seuls critères évalués, lettre, confiance, fiche md +
ligne DB) · `evaluate_golden_agreement.py` (accord vs gold : exact C9/C11,
|Δ| ≤ 20 % du barème en continu, désaccords N/A-vs-score listés).

## Tests & vérifications

- **91 tests** `tests/scripts/media_eval/` (purs + DB savepoint) : contrats,
  table `derive_score`, bornes fraîcheur 729/730/731 j, fallback 2 vs 3,
  corroboration, JTI, `bloque_acces` jamais 0, renormalisation 0/1/3 N/A
  (cas Reporterre max 34), bornes lettres 84.9/85, matrice confiance,
  idempotence dedupe/évals, rejets (signal d'un autre média/critère,
  artefact partiellement invalide → rien d'écrit), métriques gold.
- Migration sur **DB vide** : `upgrade head` → `downgrade -1` → `upgrade head`
  OK, exactement 1 head (`me01_media_eval_tables`).
- Smoke E2E offline sur DB jetable : seed → ingest artefacts (5 signaux dont
  2 couples débunkage, poids dérivés) → build_eval_input (fallback C1 déclenché
  à 2 débunkages, 6 entrées écrites) → ingest_evaluations (3 évals, C1 N/A) →
  synthese_fiche (10/20 → 50/100, lettre D, confiance moyenne).
- Suite backend complète `pytest` + `ruff check`/`format` OK.

Pas d'entrée changelog : outillage interne, aucun impact user (bypass de la
règle 400 lignes assumé).

## Suite (PR 2)

Collecteurs voie A (`collect_pages_types/cdjm/jti/cppap/pappers/arcom`),
sous-agents `.claude/agents/media-eval-*`, commande `/media-eval-run`, run
pilote `pilote-2026-07` (CNEWS puis Reporterre) + golden set Laurin
(`docs/media-eval/golden/gold_v0.json`) + rapport d'accord. Prérequis :
`PAPPERS_API_TOKEN` (env locale, compte gratuit).
