# Évaluation des médias — pipeline (méthodologie Facteur)

> Pipeline d'évaluation de la fiabilité des médias (méthodologie ouverte Facteur,
> 100 pts). Ce dossier est la **source de vérité PO** des barèmes et contrats donnés
> aux agents.
>
> **Grille active : v1.3** (`methodologie-v1.3.md`, 18/07/2026 — **10 critères**,
> axes 60/20/20, barèmes à niveaux, fenêtre 36 mois). Rubriques verbatim :
> `rubrics/v1.3/`. La **v1.2** (11 critères) reste la référence du run pilote batch 1
> (`pilote-2026-07b`) : la version est portée **par run**
> (`media_eval_runs.version_methodo`) — voir la table de correspondance en Annexe B
> de la v1.3. V0 = 6 critères (vague 1), 2 médias pilotes.

## Principe fondateur : collecte ≠ évaluation

1. **Collecte** (3 voies) → produit des **signaux** horodatés, sourcés, avec
   citation et snapshot, dans les tables `media_eval_*` (Supabase). La collecte
   **ne note jamais**.
   - **Voie A — CODE** : 6 scripts déterministes déposant leurs signaux en DB via
     le module commun `collect_common.py` (fetch httpx + repli curl_cffi, dédupe
     applicative, validation `SignalArtifact` avant insertion, harnais dry-run) :
     `collect_pages_types` (découverte + détection des pages institutionnelles),
     `collect_cdjm` (adhésion + avis fondés), `collect_jti` (certification),
     `collect_cppap` (open data `liste-des-publications-de-presse`),
     `collect_pappers` (propriété/capital, repli gratuit
     `recherche-entreprises.api.gouv.fr` sans token),
     `collect_arcom` (sanctions audiovisuel, auto-désactivé sinon).
     `page_significative` écarte les soft-404 (page = home) et les pages sans
     marqueur lexical de leur type. `export_snapshots.py` dump ensuite les
     snapshots vers `.context/media_eval/<run_id>/snapshots/*.txt`.
   - **Voie B — AGENT** : sous-agents Claude avec accès web (`.claude/agents/`),
     découpés par domaine (`gouvernance-transparence` C5+C7,
     `gouvernance-independance` C8+C9+C11, `debunkages` C1). Ils **lisent les
     snapshots exportés** (levier anti-403) et n'écrivent **jamais** en DB :
     artefacts JSON dans `.context/media_eval/<run_id>/` → validés (Pydantic)
     puis insérés par `ingest_artifacts.py` (WARNING de couverture si un
     `type_signal` gouvernance reste sans signal).
   - **Voie C — HUMAIN** : paywall, double évaluation C9/C11, golden set. Un
     artefact d'agent préfixé `humain:…` est ingéré en `voie=humain` (D6) — pas
     de nouveau script.
2. **Évaluation** : 1 sous-agent par critère, **sans accès web**, qui ne lit que
   `eval_inputs/<media>_<critere>.json` (signaux + barème verbatim) et rend un
   JSON structuré citant des `signal_ids`. Le **score faisant foi est dérivé par
   code** (`derive_score`) depuis des `determinations` énumérables — jamais choisi
   librement par le LLM.
3. **Garde-fous mécaniques codés en dur** (jamais dans les prompts) :
   - *amont* (`build_eval_input.py`) : fraîcheur (> 730 j exclu), raccourci JTI
     (C8 plein sans agent), déclencheur fallback C1 (< 3 débunkages / 2 ans) ;
   - *aval* (`ingest_evaluations.py`) : signal_ids existants/bon média/bon
     critère, corroboration (≥ 2 sources indépendantes pour un score plein,
     sinon plafonné au palier inférieur), `bloque_acces` → `revue_requise`
     (jamais 0), score dérivé par code.
4. **Synthèse** (`synthese_fiche.py`) : renormalisation sur les critères
   applicables, lettre A–E, confiance haute/moyenne/basse.

## Flow d'un run

```
create_run.py ───────────────► media_eval_runs (date_reference = fraîcheur)
seed_medias.py ──────────────► media_eval_medias
collect_*.py (voie A) ───────► signaux + snapshots (DB directe)
agents collecteurs (voie B) ─► .context/media_eval/<run_id>/*.json
ingest_artifacts.py ─────────► signaux + debunkages (validés Pydantic)
build_eval_input.py ─────────► eval_inputs/<media>_<critere>.json (+ garde-fous amont)
🛑 GOLD GATE (D4) ───────────► gold_v0.json noté EN AVEUGLE (avant les évaluateurs)
agents évaluateurs ──────────► evaluations_<media>_<critere>.json (réponse = JSON brut)
ingest_evaluations.py ───────► media_eval_evaluations (+ garde-fous aval)
synthese_fiche.py ───────────► media_eval_fiches + fiche markdown
export_evaluations.py ───────► evaluations_export.json (schéma GoldenSet)
evaluate_golden_agreement.py ► rapport d'accord vs golden set humain
rapport_pilote.py ───────────► docs/media-eval/rapports/<run_id>.{md,html} (verdict V0)
```

L'orchestration est décrite pas-à-pas dans la commande **`/media-eval-run`**
(`.claude/commands/media-eval-run.md`) : pré-vol → run + seed → voie A → voie B →
ingest → build_eval_input → **GOLD GATE — STOP** → évaluateurs → ingest →
synthèse → export + accord + rapport. Règle : `.context/` jamais commité, aucun
agent n'écrit en DB, aucune édition manuelle d'un artefact évaluateur.

**Création du run explicite (D1)** : `create_run.py` (upsert idempotent) fixe la
`date_reference` qui pilote la fraîcheur ; elle **ne peut pas être mutée**
silencieusement. Collecteurs et `build_eval_input` appellent `require_run()` qui
**lève** si le run n'existe pas — pas de création implicite.

**Protocole golden (D4)** : Laurin note depuis les **mêmes** `eval_inputs/*.json`
+ rubriques que les agents, à une étape **GOLD GATE** insérée entre
`build_eval_input` et le spawn des évaluateurs. `rapport_pilote.py` vérifie
`gold.note_at` < horodatage des évaluations et émet un WARNING sinon.

## Périmètre V0 (décisions PO du 07/07/2026)

- **Critères vague 1** : C1 (volet données tierces), C5, C7, C8, C9, C11 (volet
  manifeste) — 54 pts max.
- **Médias pilotes** : CNEWS (`cnews.fr`, audiovisuel → ARCOM applicable) et
  Reporterre (`reporterre.net`, presse en ligne, niche → teste
  `donnees_insuffisantes` + renormalisation avec N/A).
- **Hors scope V0** : corpus d'articles (table créée mais vide), C2/C3/C4/C6/C10,
  paywall, procédure contradictoire, UI/API, lien avec `sources.reliability_score`,
  scheduling, multi-évaluateurs, SDK Anthropic.

## Critères de succès V0 (verrouillés)

1. **100 %** des artefacts évaluateurs passent la validation programmatique sans
   édition manuelle.
2. **Accord vs golden set** (exact sur niveaux C9/C11 ; |Δ| ≤ 20 % du barème sur
   C1/C5/C7/C8) sur **≥ 4 critères / 6 par média** ; aucun désaccord N/A-vs-score
   inexpliqué.
3. **Reporterre** : C1 sort en N/A `donnees_insuffisantes` (pas 0) et la fiche
   renormalise sur 34 pts.
4. **Zéro écriture DB par agent** (par construction, vérifié en revue d'artefacts).

## Contenu du dossier

| Fichier | Rôle |
|---|---|
| `methodologie-v1.3.md` | **Grille active** (10 critères, 60/20/20) + sections transverses consolidées + Annexe B (correspondance v1.2↔v1.3) + Annexe C (décisions PO) |
| `methodologie-v1.1.1.md` | Méthodologie publiée (import du PDF du 02/04/2026) — supersédée, source des sections transverses |
| `methodologie-v1.2-amendements.md` | Amendements v1.2 actés (JTI, pondération débunkages, temporalité…) — partiellement révisés en v1.3 |
| `architecture-v1.2.md` | Architecture collecte/évaluation C1–C11 (import du doc du 07/07/2026) |
| `rubrics/v1.3/_common.md` + `rubrics/v1.3/C{1..10}.md` | **Rubriques v1.3** : barème §4 verbatim + sortie structurée (niveau) + types de signaux |
| `rubrics/_common.md` + `rubrics/C{1,5,7,8,9,11}.md` | Rubriques **v1.2 legacy** (numérotation à 11 critères), lues par `build_eval_input` pour les runs v1.2 — restent à plat tant que le code ne résout pas la rubrique par version ; seront déplacées dans `rubrics/v1.2/` avec ce changement de code (PR code) |
| `golden/gold_v0.template.json` | Gabarit du golden (12 entrées, à copier + noter en aveugle) |
| `golden/gold_v0.json` | Golden set humain (Laurin) — rempli au run pilote |
| `fiches/*.md` | Fiches générées au run pilote |
| `rapports/*.md` | Rapport d'accord + rapport pilote ASCII (verdict V0) |
| `rapports/*.html` | Rapport pilote HTML propre (2 lentilles : propreté data + accord/verdict), autonome single-file |

`version_prompt` d'une évaluation = **sha256 du fichier rubrique** utilisé
(calculé par `build_eval_input.py`) : toute retouche de rubrique invalide la
comparabilité des runs, c'est voulu.

## Conventions

- Fenêtre de fraîcheur des signaux événementiels V0 : **730 jours** (décision PO,
  plus stricte que les 36 mois des amendements v1.2 — à réconcilier à la
  publication de la v1.2 finale).
- CNEWS chaîne TV vs site : le média évalué est **`cnews.fr`**,
  `type_media='audiovisuel'` → signaux ARCOM applicables. Pour la presse en
  ligne, l'absence de données ARCOM est un **N/A structurel, neutre**.
- `media_eval_medias` est un référentiel **niveau domaine**, distinct de
  `sources` (niveau feed). `source_ids` fait le lien applicatif futur, sans FK dure.
