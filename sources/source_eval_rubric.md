# Rubrique d'évaluation des sources (LLM) — source de vérité PO

> **Source de vérité unique** du jugement éditorial donné aux sous-agents Claude
> qui génèrent les évaluations (Composant 1). Le prompt de génération **lit ce
> fichier verbatim** (`build_source_eval_prompt.py`) : aucune rubrique inline en
> dur. Les décisions verrouillées par Laurin (PO) le 2026-06-13 sont intégrées
> ci-dessous.
>
> Garde-fous structurels (en dur, hors rubrique) : enums valides, scores [0,1],
> gate de confiance, rejet du tiret cadratin. Le **jugement éditorial** (ci-dessous)
> est, lui, ajustable et mesuré au benchmark vs gold (cf.
> [[feedback_highlight_no_brute_rules]] : éditorial via LLM+benchmark, pas stoplist).

## 0. Principe — chaque arbitrage doit être fact-checkable

Toute évaluation doit pouvoir être **vérifiée a posteriori**. Pour cela, l'agent
produit, **par dimension** (biais, indépendance, rigueur, ux), une **justification
courte** (1 phrase, le fait qui motive la note) et liste les **`sources_consulted`**
(URLs web réellement ouvertes). Pas d'affirmation sans appui : si l'agent ne trouve
rien de vérifiable sur une dimension, il abaisse sa `confidence` et/ou met le score à
`null`. Ces métadonnées vivent dans l'artefact JSON (revue PO + fact-check) ; elles
**ne sont pas écrites en DB**.

## 1. `bias_stance` (un seul, enum)

| valeur | définition |
|---|---|
| `left` | ligne clairement à gauche (militant social/écolo, anticapitaliste) |
| `center-left` | centre-gauche, progressiste mainstream |
| `center` | centriste / équilibré, factuel sans orientation marquée |
| `center-right` | centre-droit, libéral-conservateur |
| `right` | droite affirmée |
| `alternative` | média alternatif/indépendant hors axe gauche-droite, OU ligne militante/critique non partisane (pensée critique, philo engagée) |
| `specialized` | source thématique sans orientation politique marquée (l'angle est le SUJET : tech, sport, culture, science) |
| `unknown` | doute réel |

**Frontière `center-right` ↔ `right` (verrouillée PO)** : les chaînes/titres
**« bollorisés »** (emprise éditoriale du groupe Bolloré, ligne droitière assumée)
sont classés **`right` direct**. Ancrage : **CNEWS = `right`** ; **Europe 1 = `right`**
(tendance bollorisée). Ne pas les sous-estimer en `center-right`.

**Capture actionnariale et biais (verrouillée PO)** : généralise la doctrine
bollorisée. Le `bias_stance` n'est déplacé que si le **groupe propriétaire impose
une ligne éditoriale partisane documentée** sur l'info/opinion.
- Capture par un groupe à **ligne partisane documentée** ⇒ classer selon cette
  ligne (généralise CNEWS / Europe 1 = `right`).
- Capture par un **conglomérat / fonds sans ligne partisane** (Condé Nast, NYT Co,
  Vox, HBO, IDG, Ziff Davis, CMA CGM…) ⇒ n'affecte **que** `score_independence`,
  `bias_stance` **inchangé**. Ancrage : **BFMTV = `center`** (groupe CMA CGM/Saadé
  n'impose pas de ligne partisane) **+ indépendance basse** (≈ 0.2).
- **Verticale thématique apolitique** détenue par un groupe marqué (ex. Cuisiner /
  JDN, groupe Figaro/Dassault) ⇒ reste `specialized` (l'angle reste le sujet).

Aucune stoplist : ce jugement est appliqué par le LLM à partir de la recherche web,
pas d'une liste codée en dur.

`specialized` par défaut pour sport / jeux vidéo / tech / science sans angle
politique. `alternative` pour les agrégateurs communautaires (r/france) et la pensée
critique non partisane.

## 2. `reliability_score` — **dérivé**, plus un enum libre

Le LLM **ne choisit plus** `reliability_score`. Il est **calculé** depuis
`score_rigor` (dominant) et `score_independence` ; `score_ux` est **exclu** du calcul.
Formule de départ (knobs PO, calibrés vs les 66 gold avant le run) :

```
si rigor is None ou independence is None        -> "unknown"
si independence >= 0.6 et rigor < 0.55          -> "mixed"   # indépendant mais opinion-lourd
t = 0.7 * rigor + 0.3 * independence             # rigueur dominante
"high"  si t >= 0.72
"medium" si t >= 0.50
"low"   sinon
```

- **`mixed`** = source **indépendante mais à rigueur faible / opinion-lourde**
  (ex. agrégateur communautaire bien indépendant mais factualité variable).
- Les seuils (`0.72`, `0.50`, `0.55`) et les poids (`0.7`/`0.3`) sont les **knobs
  ajustables** : Laurin les revoit au step calibration (distribution présentée).
- Implémenté par `derive_reliability(rigor, independence)` dans
  `source_eval_schema.py` ; appliqué à l'écriture (`apply`) **et** côté généré au
  benchmark (`evaluate`).

## 3. Scores FQS (float 0.0–1.0, ou null si indéterminable)

| score | ancrage |
|---|---|
| `score_independence` | 1 = très indépendant (lecteurs/asso : Mediapart 1.0, Reporterre 1.0) ; 0 = capté par un grand groupe / annonceurs. **Au-delà du modèle de financement, peser l'emprise actionnariale reconnue sur la rédaction.** Ancrages bas : **BFMTV ≈ 0.2** (groupe CMA CGM) ; **CNEWS = 0** (very low, ligne dictée par l'actionnaire). |
| `score_rigor` | rigueur factuelle et méthodologique. **Signal `low` : sanctions réglementaires (Arcom), retoquages, démentis/corrections fréquents.** Ancrages : **CNEWS = low** (mises en demeure Arcom) ; **Contrepoints = lean low** selon la justif (opinion-lourd). |
| `score_ux` | qualité d'expérience de lecture (lisibilité, pub peu intrusive, paywall non agressif) ; 1 = excellente, 0 = mauvaise. **Confirmé pertinent par le PO.** Ancrages mauvaise UX : **Frandroid ≈ 0.2**, **Trashtalk** (pub/affiliation intrusive, lisibilité faible). |

`score_ux` n'entre **pas** dans le calcul de `reliability_score` (cf. §2), mais reste
écrit en DB et utile à la fiche source.

## 4. Règles de génération (sortie)

- **Doute réel → `unknown`** (biais) + `confidence` < 0.5 + scores `null`. La
  reliability dérivée vaudra alors `unknown` automatiquement (scores null).
- **`description`** : 2–3 phrases FR, neutres, factuelles, qui **replacent bien la
  source** : qui (éditeur), **ligne éditoriale**, **actionnariat**, spécificité. Ajouter
  **un fait moins connu mais important** (bonus de mise en perspective). Pas de
  superlatifs militants. **Jamais de tiret cadratin** (`—`) : virgule / point /
  deux-points (rejeté par le schéma).
- **`confidence`** : 0.0–1.0, confiance globale de l'agent.
- **Justifications par dimension** (fact-check, §0) : `bias_rationale`,
  `independence_rationale`, `rigor_rationale`, `ux_rationale` — **1 phrase courte
  chacune**, le fait qui motive la note.
- **`sources_consulted`** : liste des URLs web réellement ouvertes pour trancher.
- **Recherche web** : **3–4 requêtes pour les médias mainstream** (actionnariat,
  indépendance rédactionnelle, sanctions/réputation, ligne) ; **1–2 requêtes pour le
  niche**. Le `name`/`theme` stockés peuvent être faux : identifier la **vraie**
  source via l'URL.
- **PAS de `reliability_score` en sortie** : il est dérivé (§2).
- **`recommended_by` / `recommendation_reason`** : JAMAIS générés (voix perso équipe,
  laissés intacts).

### Spec JSON de sortie (par source)

```json
{
  "source_id": "<uuid>",
  "name": "<vraie source>",
  "description": "2-3 phrases, replace la source + 1 fait moins connu, sans tiret cadratin",
  "bias_stance": "left|center-left|center|center-right|right|alternative|specialized|unknown",
  "score_independence": 0.0,
  "score_rigor": 0.0,
  "score_ux": 0.0,
  "confidence": 0.0,
  "bias_rationale": "1 phrase",
  "independence_rationale": "1 phrase",
  "rigor_rationale": "1 phrase",
  "ux_rationale": "1 phrase",
  "sources_consulted": ["https://...", "https://..."]
}
```

## 5. Gate de confiance (appliqué à l'apply, pas à la génération)

`apply_source_evaluations.py --confidence-threshold` (défaut **0.5**, inchangé). Sous
le seuil : `bias_stance` → `unknown`, scores → `null` (donc reliability dérivée →
`unknown`), **description conservée**, `bias_origin='llm'`. ⚙️ seuil ajustable.

## 6. Calibrage observé

**Reliability dérivée (formule §2) vs les 66 gold curés** — matrice de confusion
exécutée read-only le 2026-06-14 (`.context/source-eval-calibration-gold-review-2026-06-14.md`) :
**exact 61/66 = 92 %**. Les 5 écarts sont un décalage gold ↔ rubrique (scores
génériques antérieurs aux ancrages §3), pas un défaut de seuil. Knobs (0.7/0.3,
0.72/0.50, 0.55) à valider/ajuster par Laurin à ce step.

**Pilot bias (13 gold, 2026-06-13)** : bias exact **85 %** / adjacent **100 %** ;
MAE scores 0.08–0.14. À reconfirmer au run complet (nouveau schéma).
