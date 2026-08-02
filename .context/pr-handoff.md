# fix(curation): fold couverture (B-2) + arrêt de la fabrication d'intérêts (C-1)

Base `main`. **Une migration Alembic** (`cq01_subtopics_uniq_muted`).
Backend-only (0 fichier mobile).

## Contexte

Deuxième livrable du lot « qualité de la curation », après PR 1 (B-1
métadonnées, #1047). La cible du lot est
`score = w_imp · norm(importance) + w_perso · norm(perso)` (PR 4-5). Les deux
termes sont aujourd'hui faux : `importance` compte de la redondance (B), `perso`
est un signal plat et fabriqué (C). **Cette PR répare les deux termes avant que
PR 4 ne les mélange.** Elle ne change volontairement **pas** le tri.

Diagnostic complet : `docs/bugs/bug-curation-essentiel-personnalisation.md`.

## PR 2 — B-2 : ne compter que les rédactions qui portent un jugement

`importance_detector.py` : `_is_aggregator` → `_counts_toward_coverage`, appliqué
aux **deux** collections (`source_ids` **et** `source_domains`).

- **Critère** : `SourceType.REDDIT` **OU** (`is_curated` falsy **ET**
  `reliability_score ∈ {low, mixed}`). Réglable sans déploiement :
  `EDITORIAL_COVERAGE_FOLD_RELIABILITY` (défaut `low,mixed`),
  `EDITORIAL_COVERAGE_FOLD_ENABLED` (kill switch, défaut `true`).
- **`unknown` volontairement exclu** : « jamais évaluée » ≠ « peu fiable » ;
  l'inclure folderait 39,5 % du corpus `politics` (déjà à 1,3 % du top-5).

### Dry-run comparatif (prod, lecture seule, 24 h) — livrable bloquant

`scripts/dryrun_coverage_fold.py --hours 24 --tag b2-fold` (read-only, sans LLM,
exit ≠ 0 si > 50 % du top-15 change). Résultat sur 1 565 contenus / 1 086
clusters :

- **top-15 (entrée LLM) change de 13 %** (2 sortants, 2 entrants) ;
- **18 clusters franchissent `2→1`**, 9 franchissent `3→2` ; `4+ domaines` :
  22 → 13 ;
- **`politics` net = +0** (non enterré ; sortants = 1 environment, 1 culture ;
  entrants = 1 science, 1 sport).

Artefacts : `.context/dryrun_coverage_fold_b2-fold.{json,md}`.

## PR 3 — C-1 : arrêter de fabriquer des intérêts

Correctif **au moment de l'écriture** (une fois la ligne créée, rien ne distingue
un intérêt déclaré d'un intérêt fabriqué) :

- `_adjust_interest_weight` (lecture) → **UPDATE seul** (no-op si absent).
- `_adjust_subtopic_weights` → paramètre `allow_create` (défaut `False`). Créent
  seulement les signaux **explicites** : like/save/note (`content_service`),
  feedback (`routers/contents.py`), actions digest **SAVE/LIKE**
  (`digest_service`). Lecture (READ) et signaux négatifs = update seul.
- **Double-comptage confirmé (§3.1)** : le tail « interest par thème source » de
  `_adjust_subtopic_weights` fabriquait **aussi** un `user_interests` sur lecture
  (en plus de `_adjust_interest_weight`). Il est désormais gardé par le même
  `allow_create` → plus aucune fabrication d'intérêt sur lecture. La magnitude du
  renforcement d'un intérêt *existant* sur lecture (0,05 + 0,03) est inchangée
  (hors périmètre C-1, relève de PR 4).
- Onboarding (`user_service.py`) : `db.add(UserSubtopic)` → upsert
  `on_conflict_do_nothing` (ne casse pas sur la nouvelle contrainte).

### Migration `cq01_subtopics_uniq_muted` (down_revision `sa02_alerts_v2`)

1. **Dédup** `user_subtopics` sur `(user_id, topic_slug)` (garde le plus grand
   weight) — la contrainte d'origine avait été droppée par accident
   (`4d497ce7bcc2`).
2. **`UNIQUE uq_user_subtopics_user_topic`** + **`INDEX ix_user_subtopics_user_id`**
   (la table n'avait aucun index → seq scan à chaque lecture feed/digest).
3. **`DELETE`** idempotent des `user_interests` contredisant un `muted_themes`.

Idempotente, `__table_args__` posé sur le modèle. Testée : `alembic upgrade head`
sur DB vide (chaîne complète), downgrade/re-upgrade, exactement **1 head**.

**Risque expand-contract assumé** (DB partagée staging/prod) : pendant ≤ 1
semaine, le backend `production` (ancien code) fait encore du check-then-insert ;
une course produira une `IntegrityError` ponctuelle (mesuré **5×** sur toute la
vie de la table) au lieu d'un doublon silencieux. Décision PO §5 : contrainte
dans cette PR.

## Tests

- `test_importance_detector.py::TestReliabilityFold` — 7 cas (fold low/mixed,
  repli cluster 100 % foldé, curée medium compte, **`unknown` compte** — non-rég
  Libération, `source_ids` **et** `source_domains`, kill switch, CSV env).
- `test_digest_per_user_projection.py::test_rehydrated_clusters_do_not_depend_on_source_domains`
  — invariant : cluster réhydraté n'a pas de `source_domains`, le décompte passe
  par `source_ids` (déjà foldé en global).
- `test_subtopic_weight_concurrency.py` (nouveau) — read n'crée pas / like crée /
  cap 3.0 / clamp 0.1.
- `test_interest_weight_concurrency.py` — réécrit : read n'crée pas / read
  incrémente un existant.
- `tests/alembic/test_cq01_subtopics_uniq_muted.py` (nouveau) — dédup garde
  max-weight + idempotence, DELETE muté (seulement muté, idempotent, thème
  re-déclaré préservé, no-op sans mute).
- Non-régression `test_like_feature.py` / `test_user_service_persist.py` mis à
  jour (`allow_create`, upsert onboarding).
- **Suite backend complète : 2862 passed, 18 skipped, 2 xfailed.** `ruff check` OK.

## Vérification C-1 (avant/après)

Bloc « C-1 » ajouté à `docs/qa/scripts/baseline_curation.sql` (M8-M11). À lancer
via le rôle service (`claude_analytics_ro` n'a pas le `SELECT` sur
`user_interests`/`user_subtopics`). Valeurs live prod (via MCP Supabase) :

| # | Métrique | Avant (live 02/08) | Après |
|---|---|---|---|
| M8 | `user_interests` sur un thème muté | **42** (27 comptes) | **0** après migration |
| M11 | Doublons `(user_id, topic_slug)` | **5** | **0**, impossible |

(M8 = 53 au snapshot 02/08 ; le chiffre dérive tant que `production` fabrique
encore — d'où le rejeu post-release ci-dessous.)

## Après merge

1. `alembic upgrade head` rejoué automatiquement au boot Railway (staging + prod).
2. **Après la release hebdo suivante** : rejouer une fois le `DELETE` des thèmes
   mutés (le temps que `production` prenne le correctif de code) :

   ```sql
   DELETE FROM user_interests ui USING user_personalization up
   WHERE up.user_id = ui.user_id
     AND ui.interest_slug = ANY(COALESCE(up.muted_themes, '{}'));
   ```

## Ce que cette PR ne fait pas

- Ne change pas le tri (`is_multi`, `subject_rank_key`) — **PR 4**.
- Ne rebranche pas le pool personnalisé (« l'IA » qui remonte) — **PR 5**.
- N'atteint pas les cibles M1-M4 seule : elle rend les deux termes du futur score
  honnêtes, le mélange c'est PR 4-5.
