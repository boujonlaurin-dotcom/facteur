# Bug Report : "L'Essentiel du jour" — 3 régressions en cascade

**Status:** IN PROGRESS 🔧
**Severity:** HIGH (qualité produit visible quotidiennement par tous les users)
**Created:** 2026-05-19
**Branch:** `boujonlaurin-dotcom/fix-essentiel-pipeline`

---

## Symptômes remontés par le user

1. **Clusters faibles** : le 19/05, les 5 sujets ont `source_count = [2, 2, 2, 1, 1]`.
   Vision produit : 5 plus gros clusters (≥ 3 sources) du jour, identiques pour tous les users.
2. **Article ancien en 1er slot** : 14/05 rang 1 = `deep_article` "JOURNAL DE 12H30 du 12 mai"
   (radio show, 7 jours) en absence d'actu. 17/05 rang 5 = deep du 28/04 (19 j).
   Devrait apparaître en slot 6/7 avec badge "Prendre du recul", pas en article principal.
3. **Génération à ~00h Paris au lieu de 07h30** : confirmé en DB —
   `first_gen` quotidien ≈ 00:02–01:38 Paris, pas 07:30.

## Cause racine (les 3 bugs sont liés)

`packages/api/app/services/digest_service.py:75` — `_schedule_background_regen`
se déclenche **dès qu'un user ouvre l'app et n'a pas de digest pour aujourd'hui**,
sans aucune garde horaire. À 00:00:01 Paris, `today_paris()` bascule,
`read_digest_or_fallback` ne trouve pas de digest pour aujourd'hui, sert le
fallback de la veille, et lance un bg regen.

Cascade :

- Le pool `published_at >= now - 48h` à 00:00 est saturé de l'édition de la
  veille (~22h). Les Unes du matin (Le Monde ~06h30, Figaro ~07h, Libé ~07h)
  n'existent pas encore → clusters petits, articles récents rares (bug 1 + 2).
- Le cron `daily_digest` à 07:30 ne régénère rien : le bg regen a déjà créé
  un digest `editorial_v1`, et `digest_background_regen_skipped_good_format`
  (digest_service.py:144-153) le préserve. Le watchdog à 08:15 voit > 90% de
  couverture → skip.
- Donc la pipeline tourne effectivement vers minuit Paris (bug 3).

Le fix `06:00 → 07:30` du cron (commit `30dd671d`) ne change rien tant que
le bg regen contourne le cron.

## Données prod qui confirment

```
target_date | first_gen Paris | last_gen Paris
2026-05-19  | 00:02:52        | 08:16:55
2026-05-18  | 00:14:11        | 08:16:50
2026-05-17  | 01:38:53        | 08:16:46
2026-05-15  | 00:40:50        | 07:31:20  ← 1 jour propre
2026-05-12  | 00:00:49        | 06:01:48
```

Digest 19/05 (généré 00:02 Paris) :

```
rank | source_count | actu_pub     | deep_pub
1    | 2            | 19/05 03:12  | null
2    | 2            | 19/05 05:01  | 23/04 (26j)
3    | 2            | 19/05 04:42  | 11/05 (8j)
4    | 1            | 19/05 05:42  | 14/05 (5j)
5    | 1            | 19/05 06:03  | null
```

## Plan de fix

### Fix 1 — garde horaire sur `_schedule_background_regen`

`packages/api/app/services/digest_service.py` (début de la fonction, avant
le rate-limit) — bloquer toute génération de `target_date == today` avant
`DIGEST_CRON_HOUR_PARIS:DIGEST_CRON_MINUTE_PARIS` (07:30 Paris).

Pattern repris à l'identique du startup catchup (`main.py:290-315`).

### Fix 1bis — clone yesterday-from-any-user

`packages/api/app/services/digest_service.py` —
- Étendre `_try_clone_global_editorial_digest` à accepter un fallback
  optionnel "tente target_date, sinon target_date - 1 jour".
- Ajouter un step dans `read_digest_or_fallback` entre l'étape 3 (own yesterday)
  et l'étape 4 (7-day own) : "clone yesterday's editorial_v1 from any user".

Couvre le cas du nouvel user inscrit à 02h Paris : il voit l'Essentiel de
la veille pré-existant (généré par le cron 07:30 d'hier pour les autres
users) en attendant le cron de ce matin.

### Fix 2 — drop subject sans `actu_article`

`packages/api/app/services/editorial/pipeline.py:343` — passer de
`if s.actu_article is None and s.deep_article is None` (AND) à
`if s.actu_article is None`. Le `_SUBJECT_BUFFER = 2` (oversample) absorbe
la perte. Un sujet sans actu fraîche n'est pas un sujet du jour.

**Note** : la vision produit (slot 6/7 "Prendre du recul" pour les deeps
orphelins) est un follow-up — schéma `DigestResponse` + UI à changer. Cette
PR se contente de stopper la régression "deep ancien en article principal".

### Fix 3 — filtre multi-source avant LLM curation

`packages/api/app/services/editorial/curation.py:228` — filtrer le pool
à `len(source_ids) >= 2` avant LLM, fallback à `available` si pool < count
(jours pauvres : week-end, fériés). Symétrique du `a_la_une_pool`
(`pipeline.py:176-179`).

## Fichiers modifiés

| Fichier | Lignes | Changement |
|---|---|---|
| `packages/api/app/services/digest_service.py` | ~75-105 | Garde horaire avant rate-limit |
| `packages/api/app/services/digest_service.py` | ~311-435 | Nouveau step "clone yesterday from any user" |
| `packages/api/app/services/digest_service.py` | ~1492 | `_try_clone_global_editorial_digest` accepte un `allow_yesterday` |
| `packages/api/app/services/editorial/pipeline.py` | 343 | Drop subject sans `actu_article` |
| `packages/api/app/services/editorial/curation.py` | 218-243 | Pool multi-source avant LLM |

## Vérification

1. **Tests unitaires** :
   - `pytest packages/api/tests/test_digest_readonly_hotpath.py -v`
   - `pytest packages/api/tests/test_digest_service.py -v`
   - `pytest packages/api/tests/editorial/test_pipeline.py -v`
   - `pytest packages/api/tests/editorial/test_curation.py -v`
2. **Post-deploy Railway**, le lendemain matin :
   ```sql
   SELECT target_date,
          MIN(generated_at AT TIME ZONE 'Europe/Paris') AS first_gen_paris
   FROM daily_digest
   WHERE target_date = CURRENT_DATE
   GROUP BY target_date;
   ```
   `first_gen_paris` doit être ≥ 07:30. `source_count` rang 1 ≥ 3. Aucun
   subject avec `actu_article = null`.

## Risques

- **Fix 1** : un user qui ouvre l'app entre 00h et 07h30 reçoit le digest
  de la veille (déjà le comportement actuel, juste plus prévisible).
- **Fix 1bis** : couvre le nouvel user à 02h. Sans cela, il aurait 0 contenu
  jusqu'à 07h30.
- **Fix 2** : potentiellement < 5 sujets certains jours (très rare, buffer
  `_SUBJECT_BUFFER = 2` couvre). Log `subjects_under_target` déjà en place.
- **Fix 3** : alourdit légèrement jours pauvres. Le fallback gère.
