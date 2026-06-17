# Maintenance — Ranking PR1 : la jauge + hygiène boucle sujets

> **Objectif global (2 PRs)** : améliorer le ranking utilisé partout (L'Essentiel,
> Flâner, Veille) **sans vectorisation** — préférer des signaux granulaires
> *explicables/contrôlables*. PR1 = poser la **mesure** (jauge) + corriger 2 défauts
> structurels de la boucle sujets. PR2 (séparée) = **affinité entités**.

Classification : **Maintenance** (instrumentation + hygiène structurelle, zéro migration).

---

## Constat (validé sur le code)

- `user_subtopics.weight` (0.1→3.0) est appris sur like/save/read/dismiss
  (`content_service.py::_adjust_subtopic_weights`) et multiplie `TOPIC_MATCH` (45 pts)
  dans `pertinence.py::_score_subtopics`. **Trous** : (a) aucun decay → dérive
  permanente ; (b) tous les sujets matchés pondérés à égalité alors que
  `content.topics` est ordonné par confiance LLM (`topics[0]` = principal).
- Le ranking **pilote à l'aveugle** : `PillarScoreResult.pillar_scores` est calculé
  (`scoring_engine.py:147`) puis **jeté** — dans `digest_selector.py:1442` il n'est
  plus que loggé. Aucun CTR par sujet/entité/position.

## PR1.1 — Persister le breakdown par pilier (zéro migration)

`daily_digest.items` est un JSONB schemaless ⇒ ajout de clés sans DDL. Mobile parse
par clés nommées (`digest_models.g.dart`, json_serializable permissif) ⇒ **clés
inconnues ignorées, aucun risque de casse**. Vérifié.

`pillar_scores` n'est pas porté jusqu'à la sérialisation ⇒ il faut le **threader** :

1. `digest_selector.py::_score_candidates` (≈L1380-1465) : le tuple `scored`
   passe de `(content, final_score, breakdown)` à
   `(content, final_score, breakdown, pillar_scores)` (dict déjà dispo L1442).
2. `digest_selector.py::_select_with_diversity` (≈L1467) : propager `pillar_scores`
   (tuple sortant `(content, score, reason, breakdown)` → ajouter `pillar_scores`).
3. `DigestItem` dataclass (`digest_selector.py:137`) : nouveau champ
   `pillar_scores: dict[str, float] | None = None` + construction L589-598.
4. **Sérialisation** `digest_service.py::_create_digest_record` (L1722-1758) :
   ajouter au `item_data` →
   `"pillar_scores": item.pillar_scores or {}` et `"final_score": float(item.score)`.
   (Note : `score` == `final_score` déjà ; on émet la clé nommée demandée.)

Path secondaire « on-demand » (`digest_generation_job.py:1104`) : ajout optionnel des
mêmes clés pour cohérence — non bloquant (path de fallback).

## PR1.2 — Script offline de mesure

Nouveau `packages/api/scripts/evaluate_feed_ranking.py`, calqué sur la **structure**
de `evaluate_veille_curation.py` (argparse + rapport markdown lisible).
⚠️ contrairement à `evaluate_veille_curation.py` (fixture JSON, pas de DB), ce script
**a besoin de la DB** : connexion via `DATABASE_URL` (réutiliser l'engine async de
`app/database.py` ou un `asyncpg`/SQLAlchemy direct).

CTR = consommés / montrés, en joignant :
`daily_digest.items` (`rank`, `content_id`, `pillar_scores`) ↔ `user_content_status`
(`status == CONSUMED` = clic, `last_impressed_at` = montré) ↔ `contents`
(`topics`, `entities`).

Sorties : CTR **par slug de sujet**, **par entité**, **par rang/position**, **par
bande de score pilier**. C'est la jauge qui calibrera PR2 et validera 1.3.

## PR1.3 — Hygiène boucle sujets (structurel, sûr)

**a. Decay des poids** — job batch quotidien accroché au scheduler APScheduler
(`app/workers/scheduler.py`, près de `daily_digest` 07:30 Paris). Un seul UPDATE bulk :
```sql
UPDATE user_subtopics SET weight = 1.0 + (weight - 1.0) * :decay
```
→ normalise tout vers 1.0, O(1) requête/jour, aucun schéma.
(Alt. notée et écartée : colonne `updated_at` additive + decay paresseux = migration.)

**b. Pondération par position** dans `pertinence.py::_score_subtopics` (L297-301) :
aujourd'hui `score += TOPIC_MATCH * w` à égalité. Pondérer par l'index du sujet dans
`content.topics` : facteur `1.0` pour index 0, puis `SUBTOPIC_POSITION_FACTOR` par cran
(≈0.6 → index1=0.6, index2=0.36). `TOPIC_MAX_MATCHES=2` inchangé.
⚠️ `_score_subtopics` calcule `matches = content_topics & user_subtopics` puis
`sorted(matches)` — il **perd l'ordre** de `content.topics`. Il faut récupérer
l'index de chaque match dans `content.topics` (et non l'ordre alpha) pour appliquer
le bon facteur.

Nouvelles constantes dans `scoring_config.py` :
`SUBTOPIC_DECAY = 0.98`, `SUBTOPIC_POSITION_FACTOR = 0.6`.

## Tests

- `packages/api/tests` : étendre les tests de pertinence — vérifier que
  `topics[0]` contribue plus que `topics[1]` (pondération position) ; test du job decay
  (poids > 1 décroît vers 1.0, poids < 1 croît vers 1.0).
- DB locale `facteur_test` (port 54322, `DATABASE_URL` depuis `.env`) ;
  `cd packages/api && pytest -v`.
- Lancer `python scripts/evaluate_feed_ranking.py` et lire le rapport.

## Hors-scope PR1

Affinité entités (bonus positif sur `contents.entities`) = **PR2**, calibrée par la
jauge de PR1.
