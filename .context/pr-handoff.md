# feat(reco): personas, corpus gelé et harnais de sensibilité (PR-3, lot reco 2)

Base `main`. **Aucune migration Alembic.** Backend-only (0 fichier mobile),
**aucun changement de comportement en prod** : trois scripts, des fixtures, deux
fichiers de tests et un runbook.

De quoi **mesurer** avant de toucher une constante de scoring. Sans ça, le
« Journal des constantes modifiées » du lot reste vide et PR-5 est bloquée :
*aucune constante ne bouge sans mesure*.

Runbook : `docs/maintenance/maintenance-scoring-tuning-harness.md`.
Suivi du lot : `docs/maintenance/maintenance-reco-optimisation-lot2.md`.

## Ce que ça pose

| Fichier | Nature |
|---|---|
| `scripts/build_persona_dataset.py` | 8 personas (6 médoïdes + 2 extrêmes) dérivés de 62 comptes réels — k-medoids stdlib **déterministe** |
| `scripts/build_scoring_corpus.py` | corpus 24 h **append-only** depuis `DATABASE_URL_RO` |
| `scripts/evaluate_scoring_personas.py` | `--sensitivity` / `--invariants` / `--gold` / `--sweep` / `--compare` |
| `scripts/validate_personas.py` | **supprimé** — écrivait de faux profils dans une DB vivante |
| `tests/scripts/test_evaluate_scoring_personas.py` | 48 tests, ni DB ni réseau |
| `tests/scripts/test_build_persona_dataset.py` | 19 tests — déterminisme, anonymisation |

Le harnais rejoue le **vrai** `PillarScoringEngine.compute_score` ; un test
d'identité casse si quelqu'un en recopie une variante.

## Méthodo (elle commande l'ordre des modes)

8 personas × ~30 candidats ≈ **240 labels pour 113 constantes** : 2 labels par
paramètre. Tuner au gold d'abord serait de l'overfit. D'où **sensibilité (0
label) → invariants → gold en portail de non-régression**, jamais en fonction à
maximiser.

## Recette

`--sweep ENTITY_AFFINITY_BASE=8,16,32,64` → **courbe plate** (churn 0,000
partout). Le harnais **redécouvre l'inertie déjà établie** de l'affinité
entités. C'était la condition d'acceptation : un instrument qui ne retrouve pas
ce qu'on sait déjà est faux.

Première lecture : **20 constantes actives · 1 faible · 27 inertes · 64
hors-périmètre**, menées par `THEME_MATCH`, `recency_base` et `TOPIC_MATCH`.

## Faits mesurés qui corrigent le cadrage

1. `claude_analytics_ro` lit `contents`/`sources` mais est **refusé sur toutes
   les tables `user_*`** → corpus en direct, personas par dump MCP (convention
   `--raw` de `build_event_dataset.py`).
2. **2 comptes** au plafond `weight = 3,0`, pas 32.
3. **64 des 112 constantes balayables sont hors du moteur de piliers.** Le
   rapport distingue *hors-périmètre* (jamais lue par `compute_score`)
   d'*inerte* (lue, sans effet mesurable) — les confondre ferait passer un cap
   d'arrangement de la Tournée pour un dial de scoring.
4. `DIGEST_SPORT_PENALTY` **ne vit pas dans le moteur de piliers** : elle est
   appliquée par `digest_selector` après combinaison.
5. **Le sport suivi est déjà enterré avant la pénalité** : rangs 134 / 50 avant
   les −80, 187 / 172 après. **PR-5 qui ne toucherait que cette constante
   déplacerait peu de chose.**
6. Question ouverte n°1 du lot tranchée : **`essentiel_service.py` ne passe pas
   par `PillarScoringEngine`** (vérifié, aucun call site — seulement une mention
   en docstring).

## Garde-fous anti-overfit (dans le code, pas seulement dans le doc)

- Corpus **append-only** : le script refuse d'écraser un fichier existant.
- `--compare` **lève** si le `corpus_file` diffère — **et** si l'échantillon
  diffère (`--corpus-sample` change le jeu de candidats sans changer le nom du
  corpus).
- `--sweep` publie la courbe complète et qualifie sa forme
  (`PLATE` / `MONOTONE` / `UNIMODALE` / `NON MONOTONE — bruit, ne pas calibrer`).
- **Held-out** : les 2 extrêmes sont exclus du mode gold par défaut.
- Le gold livré est un **squelette vide** : PR-3 livre le chargeur et le schéma,
  pas des labels. Un gold vide rapporte « aucun label », **jamais** `p@5 = 0,000`.
- `NOW` figé au `generated_at` du corpus, jamais l'horloge du run.

Deux pièges gardés par des tests : le moteur doit être **construit dans** le
`with weights_override(...)` (sinon `PILLAR_WEIGHTS` est un no-op silencieux), et
aucune perturbation ne doit faire tomber un pilier à 0 (une exception avalée
par `compute_score` produirait un faux « actif »).

## Vérification

- `pytest tests/scripts/` : **484 passés**, 82 erreurs = baseline DB locale
  indisponible (port 54322), inchangée.
- `ruff check` + `ruff format` : propres sur les nouveaux fichiers ; `app/`
  (le gate CI) intact.
- **Alembic : exactement 1 head, aucune migration** — attendu sur tout ce lot.
- Bout en bout sur données réelles : corpus 1 763 articles / 112 sources →
  8 personas → `--sensitivity` → `--sweep`.

## Suite

PR-4 (mobile, ordre des blocs par score top-3) part **après** le merge de
celle-ci, sur une branche neuve depuis `main`.
