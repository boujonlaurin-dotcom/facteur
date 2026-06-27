# Maintenance — Track B : montée en qualité des thèmes pauvres (post-onboarding)

> **Type** : Maintenance (opération de **curation**, pas de PR de code produit).
> **Objectif** : grossir la profondeur **Tier 2 « Catalogue évalué »** des thèmes
> pauvres pour que les sections thématiques de la Tournée du matin (« Étoffer
> [thème] », Track A / PR #903) aient un pool de sources de qualité assez
> profond pour pousser chaque jour de la news fraîche et pertinente.
> **Track A = la demande** (UX), **Track B = l'offre** (ce doc).
>
> **DML pure sur colonnes existantes** ⇒ **aucune migration Alembic**, insensible
> au drift connu. DB prod **partagée** staging/prod : on ne touche que la
> *donnée*, jamais le schéma. Tout apply est **gated PO** (dry-run + backup +
> `--allow-prod`).

Le gate **Tier 2** (`packages/api/app/services/source_recommendation_gate.py`,
`is_quality_catalog`) exige **les 3** : `is_curated = true` **ET**
`reliability_score ∈ {high, medium}` **ET** `bias_stance ∉ {alternative, unknown}`.
La section « Étoffer [thème] » affiche une source si
`Source.theme == slug OR secondary_themes.any(slug)`
(`packages/api/app/routers/sources.py`).

---

## 1. Baseline mesurée (DB prod partagée, 2026-06-26)

### 1.a Profondeur Tier 2 par thème **primaire**

| thème | actifs | curées | **Tier 2 (primaire)** | verdict |
|---|---:|---:|---:|---|
| **sport** | 4 | 0 | **0** | **vide** (les 4 actifs = basket US anglophone, non curés) |
| **politics** | 6 | 1 | **1** | critique en primaire |
| **science** | 11 | 3 | **3** | pauvre en primaire |
| **tech** | 78 | 6 | **6** | pauvre en primaire (78 actifs, beaucoup non curés) |
| environment | 9 | 7 | 6 | sain |
| economy | 17 | 7 | 7 | sain |
| international | 22 | 8 | 8 | sain |
| culture | 24 | 12 | 11 | sain |
| society | 105 | 22 | 20 | sain |
| custom (user-added) | 33 | 0 | 0 | pool brut communautaire |

### 1.b Profondeur **réelle de la section** (`theme OR secondary_themes`)

C'est ce que voit l'utilisateur (le routeur compte aussi les généralistes via
`secondary_themes`). **Reframing important** :

| thème | section (réelle) | lecture |
|---|---:|---|
| **sport** | **0** | **vrai goulot** : zéro source de qualité FR, et **aucun candidat de reclassification** (rien dans le pool Tier 2 n'est sportif) ⇒ **net-new uniquement** |
| science | 8 | déjà correct via généralistes ; gain = **spécialistes purs** |
| tech | 8 | idem |
| politics | 13 | déjà sain via généralistes (Le Monde, Mediapart, Le Point…) ; gain = **spécialistes purs** |

⇒ Le levier dominant n'est **pas** de gonfler un compte déjà correct, mais
**(1)** ajouter des **spécialistes** thématiquement purs aux thèmes pauvres
(reclassification, coût d'éval nul) et **(2)** combler **sport** par du net-new.

---

## 2. Sous-track 1 — Reclassification (quick win, gains Tier 2 sans ré-éval)

Des sources **déjà curées + évaluées** (donc déjà Tier 2) sont mal rangées :
leur ligne éditoriale réelle penche vers un thème pauvre mais le slug n'est pas
dans `secondary_themes`, donc elles ne remontent pas. Les re-ranger
(**additif**, le thème primaire est conservé) grossit la section **sans aucune
ré-évaluation**.

**Jugement éditorial source par source (doctrine PO : pas de règle brute)**,
fondé sur recherche web + descriptions DB (elles-mêmes web-sourcées au run
PR #844). Artefact : `sources/source_reclassification.csv` (11 propositions).

| source | thème actuel | + secondary | cible |
|---|---|---|---|
| Fouloscopie | society | science | science (chercheur Max Planck, science des foules) |
| PsykoCouac | society | science | science (docteur psycho cognitive) |
| Chez Anatole | culture | science, environment | science (vulgarisation scientifique, rapports GIEC) |
| France Culture | culture | science | science (forte programmation sciences) |
| Usbek & Rica | society | tech, science | tech (prospective : IA, technologies, sciences) |
| Monsieur Phi | culture | tech | tech (philosophie de l'IA, LLM/ChatGPT) |
| Le Canard Enchaîné | society | politics | politics (investigation politique) |
| Le Monde — Les Décodeurs | society | politics | politics (fact-check du débat politique) |
| La Croix — Analyses | society | politics | politics (vie démocratique/institutionnelle) |
| AprèsLaBière | culture | politics | politics (philosophie politique, pouvoir) |
| L'Incorrect | society | politics | politics (analyses politiques conservatrices) |

### Effet mesuré (simulation SQL sur DB prod, read-only)

| thème | section avant | section après | Δ spécialistes |
|---|---:|---:|---:|
| science | 8 | **13** | +5 |
| politics | 13 | **18** | +5 |
| tech | 8 | **10** | +2 |
| sport | 0 | 0 | (net-new requis) |

> Option PO : pour Fouloscopie / PsykoCouac (chaînes franchement scientifiques),
> on peut **basculer le thème primaire** society→science plutôt qu'additif. Choix
> conservateur retenu ici = **additif** (non destructif sur la DB partagée).

### Apply (gated PO)

Nouveau script garde-fou `packages/api/scripts/apply_source_reclassification.py`
(calqué sur `apply_source_evaluations.py`) : **dry-run par défaut**, additif par
construction (jamais d'effacement de secondary existant), backup JSON `.context/`,
validation des slugs contre la taxonomie (`VALID_THEMES`), idempotent.
`secondary_themes` n'étant touché par **aucun** script existant
(`retag_and_promote_sources.py` l'ignore), ce script comble le manque.

```bash
cd packages/api
python3 scripts/apply_source_reclassification.py                       # dry-run (diff)
python3 scripts/apply_source_reclassification.py --apply --allow-prod   # prod (gated PO)
```

---

## 3. Sous-track 3 — Net-new sourcing (le vrai levier sport)

`sport` = **0** et **aucun** candidat de reclassification. Shortlist de
sources **FR de qualité** ajoutée à `sources/sources_candidates.csv`
(statut « À valider », web-sourcée) :

| source | couverture | confiance |
|---|---|---|
| So Foot | football, angle culturel/sociétal, enquêtes | haute |
| Les Cahiers du Football | football, enquête/analyse alternative | haute |
| L'Équipe | multisport de référence | haute |
| RMC Sport | foot/rugby/tennis/cyclisme | moyenne |
| Eurosport France | multisport (cyclisme, tennis, athlé, hiver) | moyenne |
| Le Rugbynistère | rugby | moyenne |

Import : `packages/api/scripts/import_sources.py` (is_active, **not curated**).
⚠️ **Lag de promotion** : `retag_and_promote_sources.py` n'auto-promeut
(`is_curated=true`) qu'à partir de `articles_30d >= 20`. Pour un gain Tier 2
**immédiat**, prévoir une **curation manuelle** (`is_curated=true`) des net-new
à haute confiance (So Foot, Les Cahiers, L'Équipe) après un premier cycle
d'ingestion ; sinon ils n'entrent Tier 2 qu'après accumulation de contenu.

---

## 4. Sous-track 4 — Évaluer → benchmarker → appliquer (statut)

Cible d'éval restante (export read-only mesuré 2026-06-26) : **28 sources
actives non évaluées** (`bias_stance='unknown'`) + **33 communautaires
`theme=custom`**. Le backlog « ~167 non évaluées » de l'audit catalogue est
**périmé** (vidé par le run PR #844, 160 évals déjà en base).

**Méthode déjà calibrée et verte** : exact reliability **92 % vs 66 gold**
(rubrique §6, PR #844) ; les knobs (`0.7/0.3`, `0.72/0.50`, `0.55`) et la
rubrique sont **inchangés** ⇒ pas de régression de méthode introduite par
Track B.

**Statut** : le **run de génération** (sous-agents Claude + recherche web sur
chaque lot) est la seule étape encore **gated** (budget sous-agents). Pipeline
**turn-key** pour reprise :

```bash
cd packages/api
python3 scripts/export_source_eval_targets.py                          # -> .context/source_eval_targets.json (targets + gold)
python3 scripts/build_source_eval_prompt.py --out-dir .context/source_eval_prompts
# -> sous-agents sur chaque prompt_*.md, append dans sources/source_evaluations_llm.json
python3 scripts/evaluate_source_evaluations.py \
  --gold .context/source_eval_targets.json \
  --generated .context/source_evaluations_gold_blind.json              # cible: bias exact ≥85%, reliability ~92%, MAE ≤0.15
python3 scripts/apply_source_evaluations.py                            # dry-run
python3 scripts/apply_source_evaluations.py --apply --allow-prod --confidence-threshold 0.5   # gated PO
```

Sûr par construction : sous le seuil de confiance → `bias_stance=unknown` +
scores NULL ⇒ **exclu du gate Tier 2**.

---

## 5. Sous-tracks 2 & 5 — Import + promotion + re-mesure (post-merge, PO)

1. Import candidats sport (sous-track 3) + entrée des 28 + 33 custom dans la
   cible d'éval.
2. `retag_and_promote_sources.py --apply --allow-prod` (re-tag granular + auto
   promotion) + curation manuelle ciblée des net-new à fort signal.
3. **Re-mesurer** : rejouer la requête baseline (§1) ⇒ confirmer Tier 2 ↑,
   en particulier **sport > 0**.

---

## 6. Vérification & garde-fous

- **Tests** : `pytest tests/scripts/test_apply_source_reclassification.py -v`
  (9 tests, logique pure sans DB) ; suite complète `pytest -v`.
- **Dry-run revus** (reclassification + évals) avant tout `--apply`.
- **Re-mesure SQL** post-apply (section depth par thème).
- Toutes les écritures DB = **DML sur colonnes existantes** ⇒ **pas de
  migration**, insensible au drift Alembic.
- Pas d'em-dash dans la copy user-facing (règle PO) — descriptions inchangées
  par la reclassification (hors scope du script).

## 7. Artefacts livrés (PR légère vers `main`)

- `sources/source_reclassification.csv` (11 propositions web-sourcées)
- `packages/api/scripts/apply_source_reclassification.py` (+ test)
- `packages/api/tests/scripts/test_apply_source_reclassification.py`
- `sources/sources_candidates.csv` (+6 sources sport FR « À valider »)
- `docs/maintenance/maintenance-track-b-quality-ramp.md` (ce document)
