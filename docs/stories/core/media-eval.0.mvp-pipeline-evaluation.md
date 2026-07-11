# Story media-eval.0 — MVP (V0) pipeline d'évaluation des médias C1–C11

## Statut

- **Type** : Feature (outillage interne, rien de user-visible — pas d'entrée changelog)
- **PR 1** : `feat(media-eval): fondations (schéma, contrats, moteur d'évaluation)` — en cours
- **PR 2** : `feat(media-eval): collecte vague 1 + orchestration + run pilote` — à suivre
- **Plan validé PO** : 07/07/2026 (cf. `.context/attachments` plan MVP)

## Contexte

Facteur note des médias français sur 11 critères (méthodologie ouverte v1.2, 100 pts).
Architecture cible (doc du 07/07/2026, importé dans `docs/media-eval/architecture-v1.2.md`) :

- **collecte ≠ évaluation**, séparées par un data store Supabase (signaux horodatés + snapshots) ;
- **3 voies de collecte** : CODE (déterministe) / AGENT (jugement + web) / HUMAIN ;
- évaluateurs **sans accès web**, qui citent des `signal_ids` ;
- garde-fous mécaniques **codés en dur** (jamais dans les prompts).

Le V0 teste la pipeline de bout en bout sur un périmètre resserré, avec mesure
d'accord contre un golden set humain (Laurin).

## Décisions PO actées (07/07/2026)

- Data store = **DB Supabase prod** (partagée main/production) via migration Alembic
  **additive**, tables préfixées `media_eval_*`, **RLS deny-all**.
- Périmètre = critères **vague 1** : C1 (volet données tierces), C5, C7, C8, C9,
  C11 (volet manifeste) — 54 pts max.
- **2 médias pilotes** : CNEWS (`cnews.fr`, exposé, audiovisuel → ARCOM applicable)
  + Reporterre (`reporterre.net`, niche, presse en ligne → teste
  `donnees_insuffisantes` et la renormalisation avec N/A).
- Runtime = **sous-agents Claude Code** (pas de SDK). Les agents n'écrivent
  **jamais** en DB : artefacts JSON dans `.context/media_eval/` → scripts Python
  valident (Pydantic) puis insèrent. Les scripts voie A écrivent directement en DB.
- La fenêtre de fraîcheur V0 est **730 jours** (décision PO du plan, plus stricte
  que les 36 mois proposés dans les amendements v1.2 — à réconcilier à la
  publication de la méthodo v1.2 finale).

## Tasks PR 1

- [x] Import docs méthodo dans `docs/media-eval/` (README, méthodo, architecture, rubriques C1/C5/C7/C8/C9/C11 + `_common.md`)
- [x] Migration Alembic `me01_media_eval_tables` (7 tables, idempotente, RLS deny-all)
- [x] Modèles `app/models/media_eval.py` + enregistrement `app/models/__init__.py`
- [x] Contrats & constantes `scripts/media_eval/schemas.py` (Pydantic v2, `derive_score`, registre `type_signal`)
- [x] Garde-fous purs `scripts/media_eval/garde_fous.py` (fraîcheur, fallback C1, corroboration, raccourci JTI, `bloque_acces`)
- [x] Scripts moteur : `seed_medias.py`, `ingest_artifacts.py`, `build_eval_input.py`, `ingest_evaluations.py`, `synthese_fiche.py`, `evaluate_golden_agreement.py`
- [x] Tests `tests/scripts/media_eval/` + fixtures
- [x] Vérif E2E : migration DB vide (up/down/up), suite pytest, smoke dry-run/apply sur DB test

## Tasks PR 2 (à venir)

- [ ] Collecteurs voie A : `collect_pages_types.py`, `collect_cdjm.py`, `collect_jti.py`, `collect_cppap.py`, `collect_pappers.py`, `collect_arcom.py`
- [ ] Sous-agents `.claude/agents/media-eval-*.md` + commande `.claude/commands/media-eval-run.md`
- [ ] Run pilote `pilote-2026-07` (CNEWS puis Reporterre) + golden set + rapport d'accord

## Fichiers modifiés (PR 1)

- `docs/media-eval/` (nouveau) : README, méthodo, architecture, `rubrics/`
- `packages/api/alembic/versions/me01_media_eval_tables.py` (nouveau)
- `packages/api/app/models/media_eval.py` (nouveau) + `app/models/__init__.py`
- `packages/api/scripts/media_eval/` (nouveau) : `__init__.py`, `schemas.py`, `garde_fous.py`, `seed_medias.py`, `ingest_artifacts.py`, `build_eval_input.py`, `ingest_evaluations.py`, `synthese_fiche.py`, `evaluate_golden_agreement.py`
- `packages/api/tests/scripts/media_eval/` (nouveau) + `tests/scripts/fixtures/media_eval/`

## Critères de succès V0 (verrouillés)

1. 100 % des artefacts évaluateurs passent la validation programmatique sans édition manuelle.
2. Accord (exact sur niveaux C9/C11 ; |Δ| ≤ 20 % du barème sur C1/C5/C7/C8) sur
   ≥ 4 critères/6 par média ; aucun désaccord N/A-vs-score inexpliqué.
3. Reporterre : C1 sort en N/A `donnees_insuffisantes` (pas 0) et la fiche
   renormalise sur 34 pts.
4. Zéro écriture DB par agent (par construction, vérifié en revue d'artefacts).
