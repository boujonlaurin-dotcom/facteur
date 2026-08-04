# Maintenance — Runbook du harnais de tuning du scoring

> **Date** : 2026-08-03
> **Branche** : `boujonlaurin-dotcom/plan-pr3-pr4`
> **PR ciblée** : `main` (PR-3 du lot 2)
> **Type** : outillage de mesure (**aucune constante n'est modifiée**)
> **Scripts** : `packages/api/scripts/build_persona_dataset.py`,
> `build_scoring_corpus.py`, `evaluate_scoring_personas.py`
> **Tests** : `packages/api/tests/scripts/test_evaluate_scoring_personas.py`
> **Doc sœur** : [`maintenance-reco-optimisation-lot2.md`](./maintenance-reco-optimisation-lot2.md)
> **Jauge en ligne** : [`maintenance-feed-ranking-gauge.md`](./maintenance-feed-ranking-gauge.md)

## À quoi sert ce harnais

Mesurer **avant** de toucher une constante de `ScoringWeights`. La jauge sœur
(`evaluate_feed_ranking.py`) mesure le CTR *après coup, en ligne* ; celle-ci
mesure *hors ligne, avant*, sur des profils réels et un corpus gelé.

C'est le préalable dur de PR-5 : le « Journal des constantes modifiées » du lot
reste vide tant qu'aucune mesure n'existe, et **aucune constante ne bouge sans
mesure**. L'A/B est hors de portée (DAU 16, 1,5 à 5 ans par bras) — les
décisions de tuning se prennent ici.

Le harnais rejoue le **vrai** `PillarScoringEngine.compute_score`. Pas de fork
de la porte : `test_harness_uses_the_production_engine` casse si quelqu'un en
recopie une variante.

## Prérequis d'accès

Deux chemins, parce que les permissions diffèrent **par table** :

| Donnée | Rôle | Chemin |
|---|---|---|
| `contents`, `sources` | `claude_analytics_ro` (`DATABASE_URL_RO`) | lecture directe ✅ |
| toutes les tables `user_*` | `claude_analytics_ro` | **`permission denied`** ❌ |
| toutes les tables `user_*` | `postgres` (MCP Supabase) | dump manuel, convention `--raw` |

Vérifié le 2026-08-03 : le RO lit `contents` (72 791) et `sources` (412), et
échoue sur `user_interests` avec `permission denied for table user_interests`.
`BYPASSRLS` ne suffit pas — ce sont les `GRANT` de table qui manquent.

D'où la convention de `build_event_dataset.py` : **`build_persona_dataset.py` ne
touche jamais la DB**. Le SQL vit dans sa constante `PERSONA_DUMP_SQL`
(`--print-sql` pour l'afficher), il est joué via le MCP Supabase, le dump
atterrit dans `.context/` (non versionné) et le script le transforme.

## Construire personas + corpus

### 1. Corpus (lecture directe)

```bash
cd packages/api
PYTHONPATH=. python scripts/build_scoring_corpus.py --hours 24 --sample 200
```

Sortie : `tests/fixtures/scoring_corpus_<date>.json`. Le corpus complet 24 h
pèse ~2,3 Mo (1 763 articles / 112 sources au 2026-08-03), donc au-delà de 2 Mo
il part dans `.context/scoring-corpus-full-<date>.json` et seul l'échantillon
déterministe de 200 est versionné.

> **Règle append-only, la plus importante du lot.** Un corpus n'est **jamais
> muté** : un nouveau snapshot est un nouveau fichier daté. Le script refuse
> d'écraser un fichier existant. Sans ça, deux runs « comparés » porteraient sur
> deux jeux de candidats différents et rien dans les chiffres ne le dirait —
> c'est exactement ce que `--compare` refuse.

### 2. Personas (dump MCP puis transformation)

```bash
PYTHONPATH=. python scripts/build_persona_dataset.py --print-sql   # → MCP Supabase
# le résultat est sauvé dans .context/persona-raw-<date>.json
PYTHONPATH=. python scripts/build_persona_dataset.py \
  --raw ../../.context/persona-raw-2026-08-03.json \
  --out tests/fixtures/scoring_personas.json
```

**8 personas** = 6 médoïdes + 2 extrêmes délibérés, dérivés de 62 comptes actifs
sur 30 j. k-medoids écrit à la main (stdlib, zéro `random`, seeding
farthest-point) : `numpy` **n'est pas** dans `requirements.txt`, et le harnais
doit tourner en CI. Un médoïde **est** un compte réel, donc un contexte de
scoring cohérent — un centroïde k-means serait un profil moyen qui n'existe
pas (4,3 thèmes et 0,7 sujet).

Personas obtenus au 2026-08-03 :

| persona | n | sélection | profil |
|---|---:|---|---|
| `persona_01` | 3 | médoïde | 34 sources · 9 thèmes · 51 sujets · w_max 2,96 · J+89 |
| `persona_02` | 27 | médoïde | 21 sources · 5 thèmes · 17 sujets · w_max 1,30 · J+21 |
| `persona_03` | 7 | médoïde | 0 source · 1 thème · 3 sujets · w_max 1,07 · J+3 |
| `persona_04` | 2 | médoïde | 82 sources · 10 thèmes · 61 sujets · w_max 3,00 · J+163 |
| `persona_05` | 5 | médoïde | 26 sources · 8 thèmes · 43 sujets · w_max 1,00 · J+34 |
| `persona_06` | 18 | médoïde | 23 sources · 5 thèmes · 12 sujets · w_max 2,34 · J+168 |
| `persona_07` | 2 | **vétéran** (held-out) | 53 sources · 8 thèmes · 35 sujets · w_max 3,00 · J+65 |
| `persona_08` | 1 | **compte neuf** (held-out) | 0 source · 0 thème · 4 sujets · J+1 |

`persona_02` couvre à lui seul 27 des 62 comptes : c'est le profil médian, et
c'est sur lui qu'un réglage a le plus d'effet en volume.

> **Correction au plan de cadrage** : celui-ci annonçait « 32 comptes au plafond
> `weight = 3,0 » ». La mesure en donne **2** (`users_at_cap = 2` sur 130
> comptes ayant des intérêts). Le persona vétéran reste utile — c'est le régime
> où `THEME_MATCH` sature — mais il représente 2 comptes, pas 32.

**Anonymisation** : `persona_01…08`, aucun `user_id`, aucun email, aucun
`display_name`. Les `source_id` et slugs de thèmes sont conservés : ce sont des
identifiants de catalogue partagés, pas des données personnelles, et le scoring
en dépend entièrement.

**Le total peut descendre sous 8.** Un extrême est sauté s'il est déjà sorti
comme médoïde (il *est* alors représentatif) ou si la population n'en contient
aucun. Le script l'écrit (`⚠️ extrême « … » absent`) — sans ça, un jeu de 7
laisserait croire à un held-out de 2 alors qu'il n'en reste qu'un.

`scripts/validate_personas.py` (legacy : écrivait des faux profils dans une DB
vivante, sans argparse) est **supprimé** — remplacé par cette chaîne.

## Les trois modes, dans l'ordre

L'ordre n'est pas cosmétique. 8 personas × ~30 candidats jugeables ≈ **240
labels pour 113 constantes numériques**, soit 2 labels par paramètre. Tuner
directement contre un gold à cette densité, c'est de l'overfit.

### 1. `--sensitivity` — zéro label requis

```bash
PYTHONPATH=. python scripts/evaluate_scoring_personas.py --sensitivity --tag baseline
```

Perturbe chaque constante sur une grille **multiplicative** ×{0,5 ; 0,75 ;
1,25 ; 2,0} (repli additif ±1 pour les constantes nulles) et publie **deux
métriques côte à côte**, parce qu'aucune ne suffit seule :

- **Kendall τ-b sur un ensemble fixe** — on gèle le top-20 baseline de chaque
  persona et on re-classe *ces mêmes 20 articles*. Un « τ sur le top-5 » ne
  serait pas défini : les deux top-5 n'ont pas les mêmes éléments, et on ne
  corrèle pas deux classements sur des univers différents.
- **Churn du top-5** (`1 − |A∩B|/5`) — ce que l'utilisateur voit. C'est lui qui
  **classe** les constantes dans le rapport.

Quatre verdicts, à ne surtout pas confondre :

| verdict | signification |
|---|---|
| **actif** | au moins une perturbation déplace le top-5 d'au moins un persona. **C'est ici, et nulle part ailleurs, que se prend une décision de tuning.** |
| **faible** | réordonne le top-20 sans jamais changer l'ensemble des 5 premiers. Effet réel, invisible pour l'utilisateur. |
| **inerte** | lue par le moteur, aucun effet observable. On ne règle pas un signal inerte. |
| **hors-périmètre** | jamais lue par `compute_score`. Le harnais ne dit **rien** de son effet en prod — ne pas lire « inerte ». |

Le partage actif/faible/inerte est **mesuré** ; le partage hors-périmètre est
**statique** (scan des `ScoringWeights.X` dans `pillars/`, `helpers/` et
`scoring_engine.py`). Le rapport dit lequel est lequel.

`--corpus-sample 200` par défaut sur ce mode (112 × 4 × 8, sinon le run se
compte en heures) ; `--only PREFIX` pour cibler.

### 2. `--invariants` — falsifiable, pass/fail

Quatre assertions par persona, sans notion d'optimum :

1. `muted_source_never_surfaces` — aucun article de source mutée dans le top-20.
2. `top5_majority_followed_theme` — ≥ 3 des 5 relèvent d'un thème suivi.
3. `no_source_dominates_top5` — aucune source n'occupe > 2 des 5.
4. `followed_sport_survives_penalty` — un sport suivi n'est pas annihilé.

Un persona qui ne porte pas le signal testé donne **`n/a`, pas `pass`** : un
`pass` vacueux gonfle le compteur en donnant l'illusion d'une couverture.

### 3. `--gold` — portail de non-régression, jamais une cible

`precision@5` contre `tests/fixtures/scoring_gold_labels.json`. **PR-3 livre le
chargeur, le schéma et un gold jouet — pas des labels.** Le gold réel est un
travail PO, et il ne se fait que sur les 3 à 5 constantes que `--sensitivity`
aura signalées comme actives.

**Held-out** : `persona_07` et `persona_08` sont exclus sauf `--include-heldout`.

Un gold vide rapporte « **aucun persona labellisé — squelette vide** », jamais
`precision@5 = 0,000`. Un zéro se lirait comme une régression catastrophique
alors qu'il ne s'est rien passé : c'est exactement le faux négatif silencieux
que la jauge sœur a payé une fois (rapport vide lu comme « pas de signal »).

## Garde-fous anti-overfit

Ils sont dans le code, pas seulement dans ce document :

1. **Corpus append-only.** `build_scoring_corpus.py` refuse d'écraser un fichier
   existant. Un corpus muté déplacerait la cible sous la mesure.
2. **`--compare` refuse deux corpus différents.** C'est la règle qui rend la
   campagne falsifiable ; elle lève, elle n'avertit pas. Elle refuse **aussi**
   deux échantillons différents du *même* fichier : `--corpus-sample 200` et
   `--corpus-sample 30` tirent leurs top-5 d'univers distincts sans que le nom
   du corpus change.
3. **La courbe complète, jamais l'argmax.** `--sweep` publie tous les points et
   qualifie la forme (`PLATE` / `MONOTONE` / `UNIMODALE` / `NON MONOTONE —
   bruit, ne pas calibrer`). Lire l'argmax d'une courbe en dents de scie, c'est
   calibrer sur du bruit d'échantillonnage.
4. **Plancher d'effet explicite.** Une constante sans effet mesurable est
   déclarée inerte plutôt que réglée au hasard.
5. **Held-out.** Les deux extrêmes ne sont jamais regardés en mode gold par
   défaut.
6. **Une seule constante par cycle contre le gold.** Deux constantes bougées
   ensemble, et un gold à 240 labels ne peut plus attribuer l'effet.
7. **Journal.** Toute constante modifiée est consignée dans le « Journal des
   constantes modifiées » du lot, avec le `corpus_file` de la mesure.

### Le piège `PILLAR_WEIGHTS`

`PillarScoringEngine.__init__` fait `self.weights = ScoringWeights.PILLAR_WEIGHTS`
(`scoring_engine.py:207`). Un moteur construit **avant** un
`weights_override(PILLAR_WEIGHTS=…)` garde l'ancien dict et le sweep devient un
no-op silencieux. Règle sans exception : **un moteur neuf par configuration**,
instancié dans le `with`. Deux tests gardent la propriété, dont une
contre-épreuve qui montre le moteur périmé ne rien voir.

### Le faux « actif » par exception avalée

`PillarScoringEngine.compute_score` attrape les exceptions de pilier et met le
score à `0.0` ; structlog écrit sur stderr, **hors du `logging` stdlib**. Une
constante entière perturbée en float qui casserait un `range()` ou une tranche
produirait donc un pilier à zéro — soit un churn maximal, soit un verdict
« actif » entièrement faux, sans le moindre signal.

`test_no_perturbation_makes_a_pillar_collapse` balaie toute la grille sur le
corpus jouet et échoue si un pilier vivant tombe à 0. Sur le run réel du
2026-08-03, zéro `pillar_scoring_error` sur les 112 constantes.

### Le NOW figé

`NOW` = le `generated_at` du corpus, jamais l'horloge du run. Sinon le pilier
Fraîcheur dérive d'un jour à l'autre et deux runs sur le même corpus cessent
d'être comparables.

## Première lecture (2026-08-03, corpus 200 articles, 8 personas)

**112 constantes balayées** (les 113 numériques moins `SUBTOPIC_DECAY`, exclue
parce que `weights_override` lève dessus à raison — elle est liée au chargement
du module et un `setattr` runtime serait inerte).

**20 actives · 1 faible · 27 inertes · 64 hors-périmètre.**

Les dix premières par churn max :

| constante | valeur | churn max | τ-b min |
|---|---:|---:|---:|
| `THEME_MATCH` | 50,0 | 0,80 | 0,358 |
| `MAX_FRAICHEUR_RAW` | 115,0 | 0,80 | 0,479 |
| `recency_base` | 100,0 | 0,80 | 0,479 |
| `MAX_PERTINENCE_RAW` | 160,0 | 0,60 | 0,305 |
| `TOPIC_MATCH` | 45,0 | 0,60 | 0,305 |
| `MAX_SOURCE_RAW` | 95,0 | 0,60 | 0,358 |
| `TRUSTED_SOURCE` | 35,0 | 0,60 | 0,368 |
| `STANDARD_SOURCE` | 15,0 | 0,60 | 0,421 |
| `MAX_QUALITE_RAW` | 32,0 | 0,60 | 0,453 |
| `CURATED_SOURCE` | 10,0 | 0,40 | 0,495 |

Trois lectures, à confirmer sur un second corpus avant d'en tirer une roadmap :

1. **Les `MAX_*_RAW` sont dans le peloton de tête, et ce ne sont pas des
   réglages éditoriaux.** Ce sont les dénominateurs de normalisation des
   piliers : les toucher rééquilibre un pilier entier, exactement comme
   `PILLAR_WEIGHTS`. À traiter comme de l'architecture, pas comme un dial.
2. **Le trio de tête est thématique et temporel** (`THEME_MATCH`,
   `recency_base`, `TOPIC_MATCH`). C'est cohérent avec la lecture du lot : la
   pertinence déclarée et la fraîcheur dominent, les signaux appris ne pèsent
   quasiment rien.
3. **`ENTITY_AFFINITY_BASE` ressort « faible »** (churn 0,00 — τ-b 0,989) :
   perturbée de ×0,5 à ×2, elle ne déplace **aucun** top-5. C'est la validation
   de recette du harnais — il **redécouvre l'inertie déjà établie** de
   l'affinité entités (cf. `maintenance-reco-quality-step-up.md`). Un harnais
   qui ne retrouve pas ce qu'on sait déjà est faux.

### Recette du harnais — le sweep de contrôle

C'est le test d'acceptation de PR-3 : si le harnais ne retrouve pas ce qu'on
sait déjà, il est faux et la PR ne part pas.

```bash
PYTHONPATH=. python scripts/evaluate_scoring_personas.py \
  --sweep ENTITY_AFFINITY_BASE=8,16,32,64 --corpus-sample 200
```

| valeur | churn moyen vs baseline | τ-b moyen |
|---:|---:|---:|
| 8 (baseline) | 0,000 | 1,000 |
| 16 | 0,000 | 0,999 |
| 32 | 0,000 | 0,999 |
| 64 | 0,000 | 0,999 |

**Forme : `PLATE — constante inerte sur cet intervalle`.** Multiplier par 8 le
bonus d'affinité entités ne déplace **aucun** top-5 d'**aucun** persona.
L'inertie établie est redécouverte. ✅

### Invariants

**15 pass · 3 fail · 14 n/a**. Les trois échecs :

- `no_source_dominates_top5` sur `persona_02` (3 des 5 viennent de la même
  source) — le profil médian, donc le cas qui compte.
- `followed_sport_survives_penalty` sur `persona_01` et `persona_04`, **sans
  même appliquer `DIGEST_SPORT_PENALTY`**. Le rang du meilleur article sport
  d'une source suivie :

  | persona | moteur de piliers seul | `--sport-penalty` (−80) |
  |---|---:|---:|
  | `persona_01` | 134 | 187 |
  | `persona_04` | 50 | 172 |

  La pénalité de −80 fait bien son travail, mais elle n'est **pas la cause
  première** : l'article était déjà aux rangs 134 et 50 avant qu'elle
  s'applique. PR-5 qui ne toucherait que cette constante déplacerait donc peu de
  chose. ⚠️ Réserve : sur un échantillon de 200 articles le vivier sport est
  mince — à reconfirmer sur le corpus complet avant d'en faire un constat ferme.

## Ce que le harnais ne mesure pas

- **Tout ce qui est hors `compute_score`.** 64 des 112 constantes pilotent
  l'arrangement de la Tournée, le digest, l'Essentiel ou la veille.
  `DIGEST_SPORT_PENALTY` en fait partie : elle est appliquée par
  `digest_selector` **après** la combinaison des piliers. Le harnais la rejoue
  sur demande (`--sport-penalty`, prédicat et constante de prod), mais elle
  n'apparaîtra jamais dans le classement de sensibilité.
- **L'affinité de source apprise** (`source_affinity_scores`) : elle est
  calculée depuis l'historique d'interactions, pas stockée, et n'est donc pas
  dans les personas. Toute conclusion sur `SOURCE_AFFINITY_MAX_BONUS` est à
  prendre comme une borne basse.
- **Les post-traitements** : interleaving par source, diversité, caps,
  randomisation. Le harnais classe des candidats ; la prod re-arrange ensuite.
- **La satisfaction.** `precision@5` est un jugement éditorial, pas un signal
  d'usage. Le CTR réel, c'est la jauge sœur — et elle attend que PR-1 remplisse
  `article_impression`.
- **Le rappel.** Rien n'est dit des bons articles jamais entrés dans le corpus.
- **La généralisation depuis les extrêmes.** Les deux held-out sont
  *délibérément atypiques* (vétéran saturé, compte J+1). Ils protègent contre
  l'overfit sur les 6 médoïdes, mais ils ne constituent **pas** un échantillon
  de validation représentatif : un gold qui passe sur eux ne prouve rien sur un
  compte médian.
