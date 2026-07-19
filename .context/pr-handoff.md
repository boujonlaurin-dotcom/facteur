# feat(media-eval): collecte vague 1 + orchestration + rapport (PR 2)

Complète la pipeline media-eval de bout en bout par-dessus les fondations
PR 1 (#944) : **6 collecteurs voie A** (code → DB), **3 sous-agents** (2
collecteurs web voie B + 1 évaluateur sans web), **1 commande d'orchestration**
(`/media-eval-run`), et l'outillage de **run pilote** (golden gate, export,
rapport avec verdict V0). Le run pilote `pilote-2026-07` lui-même est en
hand-off (accès réseau réel + `PAPPERS_API_TOKEN` + notation humaine en aveugle
+ `--allow-prod`).

## Bug latent PR 1 réparé
La FK `media_eval_signaux.run_id → media_eval_runs.run_id` n'était jamais
satisfaite (aucun run créé) ; les tests PR 1 passaient sur un conteneur test
« sale ». Réparé par le fixture `run_test` (conftest mutualisé) + `create_run.py`.
`build_eval_input` calait aussi la fraîcheur sur `now()` au lieu de
`MediaEvalRun.date_reference` (rejouabilité cassée) — corrigé via `require_run()`.

## Contenu
- **`collect_common.py`** : fetch httpx + repli curl_cffi (ne lève jamais),
  `require_run`, `Collecteur` (dédupe applicative + validation Pydantic), dédupe
  voie A préfixée `code|` (D2), harnais CLI `run_cli`.
- **6 collecteurs** : `collect_{pages_types,cdjm,jti,cppap,pappers,arcom}.py`
  (fonctions `parse_*` pures + `collecter` async, fixtures figées, zéro réseau
  en test). ARCOM auto-désactivé hors audiovisuel ; Pappers dégrade en 3
  `bloque_acces` si token absent (exit 0).
- **`create_run.py`** (D1), patchs moteur : `ingest_artifacts` (D6 voie
  `humain:`, `collecte_at`, `version_prompt_collecteur`),
  `evaluate_golden_agreement --out-dir`, `build_eval_input` (date_reference),
  `.gitignore` (`.context/`).
- **`export_evaluations.py`** + **`rapport_pilote.py`** (D7) : unique collecte DB
  (`collecter_donnees_rapport`) → **deux rendus** — `.md` ASCII git-diffable +
  **`.html` propre autonome** (lentille propreté data `evaluer_proprete_donnees`
  : trou d'accès vs absence confirmée ; `render_html` single-file CSS inline
  calqué sur le design system media-eval ; verdict V0).
- **`.claude/agents/media-eval-{collecteur-debunkages,evaluateur}.md`** +
  agents gouvernance (voir PR 2b) + **`.claude/commands/media-eval-run.md`** +
  `golden/gold_v0.template.json`.

## PR 2b — corrections collecte (diagnostic du run pilote initial)

Le run pilote cnews.fr a révélé des **faux positifs voie A** et une substance
capturée mais jamais exposée. Corrections incluses dans cette PR :

- **Anti soft-404 + filtre lexical** (`collect_pages_types.py`) : `present`
  seulement si le texte ≠ home (hash/similarité) **et** porte les marqueurs
  lexicaux du type ; pénalité anti-flux (dons/régie servis en fils d'articles).
  ⇒ les faux `present` C8/charte, C11/ligne-éditoriale, C7/régie,
  C5/transparence deviennent `absent_verifie` (test de non-régression cnews).
- **Substance exposée** (`build_eval_input.py`) : `serialiser_signal` joint
  `snapshot_extrait` (~4 000 c) + `snapshot_url` quand le signal a un `snapshot_id`.
- **`export_snapshots.py`** (nouveau) : dump des snapshots vers
  `.context/media_eval/<run_id>/snapshots/*.txt`, lus par la voie B (anti-403).
- **Pappers** : SIREN cnews.fr corrigé (SESI SNC **412 916 215**, éditeur du
  site) + **repli gratuit** `recherche-entreprises.api.gouv.fr` sans token
  (identification `present`, actionnariat `partiel`) au lieu de 3 `bloque_acces` ;
  pré-vol token dans le healthcheck + `/media-eval-run` §0.
- **CPPAP** : dataset réel confirmé (`liste-des-publications-de-presse`, Explore
  v2.1, champs `titre`/`ndeg_cppap`) + repli voie C documenté.
- **Couverture** (`ingest_artifacts.py`) : WARNING listant les `type_signal`
  gouvernance sans signal (anti-passivité).
- **Agents gouvernance découpés en 2** (`gouvernance-transparence` C5+C7,
  `gouvernance-independance` C8+C9+C11) : lisent les snapshots exportés, couvrent
  tout leur registre ; politique de mort d'agent + support antenne/site portés
  dans la commande et les prompts.

> **Non inclus** (attend le re-run corrigé `pilote-2026-07b` + GOLD GATE) :
> `docs/media-eval/fiches/cnews_fr_pilote-2026-07.md` (fiche du run buggé, à
> régénérer) et les artefacts `.context/` du run.

## Décisions de design D1–D7
D1 création de run explicite (refus mutation `date_reference`) · D2 dédupe voie
A préfixée `code|` (coexiste avec la voie B) · D3 évaluateur Read-only (réponse
= JSON) · D4 GOLD GATE anti-contamination + preuve horodatage · D5 CPPAP open
data (jamais le form POST) · D6 voie dérivée du préfixe `humain:` · D7 rapport
généré par script (chiffres auditables).

## Tests
- **191 tests** `tests/scripts/media_eval` verts sur DB propre (dont
  non-régression cnews soft-404/flux, repli Pappers gratuit, snapshot_extrait,
  couverture voie B), ruff clean (check + format).
- Smoke offline validé (create_run → seed → ingest → build_eval_input →
  ingest_evaluations → synthese → export → rapport).
- Pas de nouvelle migration (dédupe snapshots applicative) — `alembic heads` = 1.

Pas d'entrée changelog (outillage interne).
