# Story media-eval.0 — MVP (V0) pipeline d'évaluation des médias C1–C11

## Statut

- **Type** : Feature (outillage interne, rien de user-visible — pas d'entrée changelog)
- **PR 1** : `feat(media-eval): fondations (schéma, contrats, moteur d'évaluation)` (#944) — mergée
- **PR 2** : `feat(media-eval): collecte vague 1 + orchestration + run pilote` — code + tests livrés ; **run pilote en attente** (network + `PAPPERS_API_TOKEN` + GOLD GATE humain + `--allow-prod` prod)
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

## Tasks PR 2

- [x] **Réparation FK latente** (voir ci-dessous) : `conftest.py` (`run_test`),
  `create_run.py`, `build_eval_input` piloté par `date_reference` (plus `now()`)
- [x] Module commun voie A `collect_common.py` (fetch httpx+curl_cffi, `require_run`,
  `Collecteur`, dédupe voie A `code|` (D2), harnais CLI) + tests
- [x] Collecteurs voie A : `collect_pages_types.py`, `collect_cdjm.py`, `collect_jti.py`, `collect_cppap.py`, `collect_pappers.py`, `collect_arcom.py` + fixtures + tests
- [x] Patchs moteur : `ingest_artifacts` (D6 voie humain/agent, `collecte_at`, `version_prompt_collecteur`), `evaluate_golden_agreement --out-dir`, `.gitignore` (`.context/`)
- [x] Export + rapport : `export_evaluations.py`, `rapport_pilote.py` (verdict V0
  ASCII **+ rapport HTML propre** : lentille propreté data `evaluer_proprete_donnees`,
  `render_html` autonome single-file, collecte factorisée `collecter_donnees_rapport`) + tests
- [x] Sous-agents `.claude/agents/media-eval-{collecteur-debunkages,collecteur-gouvernance,evaluateur}.md` + commande `.claude/commands/media-eval-run.md` + `golden/gold_v0.template.json`
- [ ] **Run pilote `pilote-2026-07`** (CNEWS puis Reporterre) + golden set + rapport d'accord — bloqué sur : accès réseau réel aux sources, `PAPPERS_API_TOKEN` (compte gratuit à créer), GOLD GATE (notation humaine en aveugle), `--allow-prod` (GO PO écriture DB prod)

## Bug latent PR 1 réparé en PR 2

La FK `media_eval_signaux.run_id → media_eval_runs.run_id` n'était jamais
satisfaite : aucun script ni fixture ne créait de ligne run. Les tests PR 1
passaient sur un conteneur test **« sale »** (une ligne `run-test` résiduelle) ;
sur DB propre (`DROP SCHEMA`), `test_ingest_artifacts.py` échouait sur
`ForeignKeyViolation media_eval_signaux_run_id_fkey`. Réparé par le fixture
`run_test` (conftest mutualisé) + `create_run.py`. `build_eval_input` calait
aussi la fraîcheur sur `datetime.now()` au lieu de `MediaEvalRun.date_reference`
(rejouabilité cassée) — corrigé via `require_run()`.

## Décisions de design PR 2 (D1–D7)

- **D1 — Création de run explicite** : `create_run.py` (upsert idempotent),
  `require_run()` lève si absent, refus de mutation silencieuse de
  `date_reference` (pilote la fraîcheur).
- **D2 — Collision dédupe voie A/B** : clé voie A préfixée `code|` (distincte de
  la clé voie B) → un signal code de détection et un signal agent de substance sur
  le même quadruplet coexistent (2 lignes).
- **D3 — Évaluateur Read-only** : sa réponse finale EST le JSON de l'artefact ;
  l'orchestrateur l'écrit (jamais l'agent, jamais d'édition manuelle).
- **D4 — Golden anti-contamination** : GOLD GATE entre `build_eval_input` et le
  spawn des évaluateurs ; `rapport_pilote.py` vérifie `gold.note_at` <
  horodatage des évaluations (WARNING sinon).
- **D5 — CPPAP open data** : `data.culture.gouv.fr` (jamais le formulaire POST) ;
  dataset inaccessible → `bloque_acces` (repli voie C possible).
- **D6 — Voie dérivée du préfixe** : `agent` commençant par `humain:` →
  `voie=humain` à l'ingestion (ouvre la voie C sans nouveau script).
- **D7 — Rapport généré par script** (`rapport_pilote.py`, lecture seule DB +
  gold) : chiffres auditables. Unique collecte DB (`collecter_donnees_rapport`)
  → **deux rendus** : `.md` ASCII (git-diffable, audit) **et** `.html` propre
  autonome single-file (deux lentilles : propreté des données collectées puis
  qualité des évaluations + verdict V0 ; lentille `evaluer_proprete_donnees`,
  distinction cardinale trou d'accès vs absence confirmée).

## Fichiers modifiés (PR 1)

- `docs/media-eval/` (nouveau) : README, méthodo, architecture, `rubrics/`
- `packages/api/alembic/versions/me01_media_eval_tables.py` (nouveau)
- `packages/api/app/models/media_eval.py` (nouveau) + `app/models/__init__.py`
- `packages/api/scripts/media_eval/` (nouveau) : `__init__.py`, `schemas.py`, `garde_fous.py`, `seed_medias.py`, `ingest_artifacts.py`, `build_eval_input.py`, `ingest_evaluations.py`, `synthese_fiche.py`, `evaluate_golden_agreement.py`
- `packages/api/tests/scripts/media_eval/` (nouveau) + `tests/scripts/fixtures/media_eval/`

## Fichiers modifiés (PR 2)

- `packages/api/scripts/media_eval/` : `create_run.py`, `collect_common.py`,
  `collect_{pages_types,cdjm,jti,cppap,pappers,arcom}.py`, `export_evaluations.py`,
  `rapport_pilote.py` (nouveaux) ; patchs `ingest_artifacts.py`,
  `build_eval_input.py`, `evaluate_golden_agreement.py`
- `packages/api/tests/scripts/media_eval/` : `conftest.py` + `test_create_run.py`,
  `test_collect_common.py`, `test_collect_{pages_types,cdjm,jti,cppap,pappers,arcom}.py`,
  `test_export_evaluations.py`, `test_rapport_pilote.py` ; MAJ `test_ingest_*`
- `tests/scripts/fixtures/media_eval/html/` + `api/` : fixtures figées
- `.claude/agents/media-eval-*.md` (3), `.claude/commands/media-eval-run.md`
- `docs/media-eval/` : `golden/gold_v0.template.json`, README mis à jour ;
  `rapports/` + `fiches/` + `golden/gold_v0.json` remplis au run pilote
- `.gitignore` : `.context/`

## PR 2b — corrections collecte (pilote-2026-07b)

Diagnostic du run pilote initial (cnews.fr) : la voie A produisait des faux
positifs et n'exposait jamais la substance capturée. Corrections livrées :

- **Anti soft-404 + filtre lexical** (`collect_pages_types.py`) : une page n'est
  `present` que si son texte ≠ home (hash/similarité — un site qui sert sa home
  sur `/charte` est écarté) **et** porte les marqueurs lexicaux de son type ;
  pénalité anti-flux (dons/régie servis comme fils d'articles taggés → écartés).
  ⇒ les faux `present` C8/`charte_deontologique`, C11/`ligne_editoriale_publiee`,
  C7/`regie_pub_identifiee`, C5/`transparence_financement` deviennent
  `absent_verifie`.
- **Substance exposée à l'évaluateur** (`build_eval_input.py`) : `serialiser_signal`
  joint `snapshot_extrait` (~4 000 c) + `snapshot_url` quand le signal porte un
  `snapshot_id` — l'évaluateur voit ce que dit la page, pas juste qu'elle existe.
- **`export_snapshots.py`** (nouveau) : dump des snapshots du run vers
  `.context/media_eval/<run_id>/snapshots/*.txt` (en-tête de provenance), lu par
  la voie B au lieu de re-fetcher (levier anti-403).
- **Pappers** (`collect_pappers.py`) : SIREN cnews.fr corrigé (site édité par
  **SESI SNC 412 916 215**, ≠ société de la chaîne TV) + **repli gratuit**
  `recherche-entreprises.api.gouv.fr` sans token (identification `present`,
  actionnariat/capital `partiel`) au lieu de 3 `bloque_acces` ; pré-vol token
  ajouté au healthcheck + `/media-eval-run` §0.
- **CPPAP** (`collect_cppap.py`) : dataset réel confirmé
  (`liste-des-publications-de-presse`, API Explore v2.1, champs `titre` /
  `ndeg_cppap`) ; repli voie C documenté (ISSN dans le snapshot).
- **Couverture voie B** (`ingest_artifacts.py`) : WARNING listant les
  `type_signal` gouvernance sans signal (anti-passivité, le silence est interdit).
- **Agents gouvernance découpés en 2** (`gouvernance-transparence` C5+C7,
  `gouvernance-independance` C8+C9+C11) : chacun lit les snapshots exportés,
  couvre tout son registre, WebSearch en complément ; politique de mort d'agent
  (respawn périmètre réduit) et distinction support antenne/site portées dans
  `/media-eval-run` et les prompts.

### Fichiers modifiés (PR 2b)

- `packages/api/scripts/media_eval/` : `export_snapshots.py` (nouveau) ; patchs
  `collect_pages_types.py`, `build_eval_input.py`, `collect_pappers.py`,
  `collect_cppap.py`, `ingest_artifacts.py`
- `packages/api/tests/scripts/media_eval/` : `test_build_eval_input.py`,
  `test_export_snapshots.py` (nouveaux) ; MAJ `test_collect_{pages_types,pappers,
  cppap}.py`, `test_ingest_artifacts.py`
- `tests/scripts/fixtures/media_eval/` : `html/` (mentions/charte/dons OK,
  cnews home riche + flux dons/publicité), `api/` (pappers SESI SNC,
  recherche-entreprises, cppap v2)
- `.claude/agents/` : `media-eval-collecteur-gouvernance-{transparence,
  independance}.md` (remplacent l'agent gouvernance unique)
- `.claude/commands/media-eval-run.md`, `scripts/healthcheck-agent-secrets.sh`

## Critères de succès V0 (verrouillés)

1. 100 % des artefacts évaluateurs passent la validation programmatique sans édition manuelle.
2. Accord (exact sur niveaux C9/C11 ; |Δ| ≤ 20 % du barème sur C1/C5/C7/C8) sur
   ≥ 4 critères/6 par média ; aucun désaccord N/A-vs-score inexpliqué.
3. Reporterre : C1 sort en N/A `donnees_insuffisantes` (pas 0) et la fiche
   renormalise sur 34 pts.
4. Zéro écriture DB par agent (par construction, vérifié en revue d'artefacts).
