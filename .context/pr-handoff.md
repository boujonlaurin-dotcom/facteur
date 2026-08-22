# feat(perspectives): analyse des angles 6C — génération structurée + persistance sujet (PR 1)

## Contexte

Le design 6C du Reader remplace la section perspectives par deux blocs qui exigent
des **constats attribués** (jusqu'à 3 accords + 2 désaccords, chacun porté par des
domaines de médias, avec un « +N »). Le backend n'en produisait aucun :
`analyze_divergences` renvoie du markdown en prose, où les médias sont du gras dans
une phrase, pas une donnée.

Mesure prod à l'origine du lot : `perspective_analyses` — la table que le Reader
interroge — contient **0 ligne depuis l'origine**, alors que l'analyse LLM est payée
tous les matins et écrite dans le JSONB du digest. Le premier gain est un
branchement, pas une génération.

Plan : `.context/plans/reader-analyse-des-angles-6c-backend-d-abord.md`
Story : `docs/stories/core/35.1.reader-analyse-des-angles-backend.md`

## Ce que fait cette PR (backend, chemin digest uniquement)

- **Migration additive `ca01`** : `coverage_analyses` (une ligne par sujet) +
  `coverage_analysis_articles` (`(analyse, content_id)`, PK composite, FK
  `contents ON DELETE CASCADE`). Backend-only : RLS activée, `REVOKE ALL FROM anon,
  authenticated`. `perspective_analyses` est laissée en place et marquée dépréciée —
  la retirer est un `DROP`, donc un cycle hebdo ultérieur.
- **`PerspectiveService.analyze_consensus()`** : remplace `analyze_divergences` à
  l'étape 3C. **Même appel, même endroit** — son JSON est un superset qui garde les
  deux clés historiques (`analysis` markdown + `divergence_level`), donc le bloc
  « Analyse Facteur » du digest ne bouge pas, et ajoute les constats structurés +
  les deux variantes courtes du CTA. Coût : ~250 tokens de sortie en plus, zéro
  appel supplémentaire. Les blocs de prompt v2 (rôle, méthode, règles) sont extraits
  en constantes partagées — le prompt de `analyze_divergences` est **byte-identique**
  à avant.
- **Post-traitement déterministe** (`normalize_consensus`, `compute_angle_qualifier`
  dans le nouveau `editorial/consensus.py`) : `support_count` recalculé sur le corpus
  réel, domaines hallucinés écartés, constats sans appui rejetés, troncature à la
  phrase (plafonds dérivés du budget annoncé au modèle : 130 car. en section, 85 dans
  le CTA), plafonds 3/2, qualificatif
  polarized/varied/convergent — et pas de qualificatif hors état `available`.
- **Câblage + persistance** dans `_process_perspectives`, avec un cache
  `content_id → analyse` par instance : le même événement analysé en `pour_vous`
  n'est pas repayé en `serein` (on rattache les articles à la ligne existante).
- **Gate `divergence_llm_min_perspectives` 4 → 2** : le design veut des constats dès
  2 médias, et le gate à 4 laissait 9 sujets sur 20 sans analyse. Rollback sans
  déploiement via `DIVERGENCE_LLM_MIN_PERSPECTIVES=4`.
- **`scripts/dryrun_consensus.py`** : rejoue l'analyse sur les sujets des digests
  récents et imprime constats + attributions + « +N », pour la relecture PO du ton.
  Read-only en base.

## Limite connue, à traiter en PR 2

Le cache inter-modes ne vit que sur l'instance de pipeline. Le job du matin réutilise
la même pour `pour_vous` et `serein` (`digest_generation_job.py:274`), mais
`digest_selector.py:419` en construit une **neuve par requête** : un recompute
on-demand repaie les appels et écrit une seconde ligne `coverage_analyses` pour un jeu
d'articles voisin. `content_id → analyse` est donc déjà 1:N — la PR 2 doit résoudre par
`SELECT` sur `coverage_analysis_articles.content_id` (index créé par `ca01`) avec
fenêtre de fraîcheur et tie-break sur `generated_at`. Aucune migration à ajouter.

## Hors périmètre

Exposition Reader (`GET /contents/{id}/perspectives` : blocs `consensus` / `display`,
attribution par user, états `pending`/`unavailable`) → **PR 2**. Front Flutter → lot
suivant. `DROP perspective_analyses` → cycle hebdo ultérieur.

## Vérification

- `pytest` : **3196 passed, 21 skipped, 2 xfailed**, 0 échec.
- Alembic : 1 head (`ca01_coverage_analyses`), chaîne complète sur DB **vide**, re-run
  no-op, `downgrade -1` puis re-upgrade OK. RLS active et zéro grant `anon` /
  `authenticated` sur les 2 tables (vérifié en SQL).
- Boot API contre le schéma migré : `startup_check_migrations_ok`, `/api/health` 200,
  `/api/health/ready` 200, perspectives sans auth → 403 (pas de 500).
- **Chemin legacy inchangé au caractère près** : le prompt système *et* le message
  utilisateur de `analyze_divergences` sont recomposés depuis les constantes/helpers
  partagés et comparés à `HEAD` — identiques (3739 car. pour le système). Le bloc
  « Analyse Facteur » du digest ne bouge pas.
- Nouveaux tests : `tests/editorial/test_consensus.py` (post-traitement, troncature,
  plafonds, CTA, qualificatif, invariant budget-prompt/plafond, index de corpus sur
  objets **et** dicts) et `tests/editorial/test_pipeline_consensus.py` (un seul appel
  LLM, payload persisté, `unavailable` sur sortie inexploitable, mutualisation des
  modes, delta de liens, upsert idempotent en DB de test).
- `scripts/dryrun_consensus.py` : smoke imports + SQL contre une base migrée, sans
  dépense LLM.
- `ruff check app/` + `ruff format --check app/` verts (ruff 0.15.14, la version CI).

## Revue qualité (`/simplify`)

Appliqué : corps d'appel LLM partagé entre `analyze_divergences` et
`analyze_consensus` (~45 lignes dupliquées supprimées, prompts système hissés en
constantes) ; post-traitement 6C sorti de `schemas.py` vers `editorial/consensus.py`
(schemas.py revient à l'identique, plus d'arête d'import vers `perspective_service`
pour ses dix importeurs) ; `subject_key` = `TitleAnnotationService.compute_cluster_signature`
au lieu d'un second hash de cluster ; upsert via `excluded` ; `normalize_consensus`
sorti du `try` best-effort (une régression du post-traitement doit se voir, pas se lire
comme un incident DB) ; plafonds de troncature dérivés du budget annoncé au modèle ;
`build_corpus_index` partagé avec le dry-run (le gate PO relit ce que la prod servira) ;
pas d'écriture de liens quand le second mode n'apporte aucun article ; factories de
tests sorties de `test_pipeline.py`.

Écarté : cache adossé à la base plutôt qu'à l'instance, et upsert groupé après le
`gather` — les deux changent le comportement et relèvent de la PR 2 (cf. « Limite
connue »). Client LLM long partagé : motif hérité de `analyze_divergences`, désormais
centralisé en un seul endroit.

## Reste à faire avant merge

**Gate PO** : `PYTHONPATH=. python scripts/dryrun_consensus.py --tag 6c-pr1` puis
relecture du ton — accords à l'indicatif sans « selon les médias », désaccords
formulés en axe et jamais en verdict, variantes CTA autoportantes. Le contrat est
facile à tester, la copy ne l'est pas.

**Après merge** : comparer `api_usage_events` (call_site `editorial`) au point de
référence du plan, ~130 k tokens in / ~15 k out par jour.
