# Bug — `/api/essentiel` ignore les préférences utilisateur

## Symptôme

PO signale (mai 2026) : « La sélection des top articles par l'endpoint
`/api/essentiel` ne semble pas du tout utiliser les préférences utilisateur. »

L'endpoint (Story 9.1, PR #647) alimente la carte hi-fi « L'Essentiel du jour »
du feed mobile. Aujourd'hui il fait un round-robin pur sur `digest.topics`
(article rank=1 de chaque topic, puis rank=2 si <5 topics) — donc tous les
utilisateurs ayant le même digest voient strictement le même top 5, alors que
le digest sous-jacent est, lui, déjà per-user.

## Cause

`packages/api/app/services/essentiel_service.py::_pick_transversal_articles`
ne consomme aucun signal utilisateur supplémentaire au-delà du digest. Pas de
re-ranking par sources suivies / topics suivis / multiplicateur de priorité.

## Fix (read-only, pas de migration)

1. Nouveau dataclass `EssentielUserContext` chargé par
   `_fetch_user_essentiel_context(db, user_id)` :
   - `followed_source_ids: set[UUID]` + `source_priority_multipliers: dict`
     depuis `UserSource`.
   - `topic_weights: dict[str, float]` union de `UserInterest.weight` et
     `UserSubtopic.weight` (max en cas de doublon).
2. Scorer composite `_score_article(topic, article, ctx)` :
   - `+100 * priority_multiplier` si source suivie (sinon +50 si
     `article.is_followed_source` déjà flaggé par le digest).
   - `+50 * topic_weight` si `topic.theme` dans `topic_weights`.
   - `+5 * perspective_count` (l'esprit transversal de l'Essentiel).
   - `- rank * 0.5` (tie-break vers les ranks bas).
3. Sélection :
   - **Round diversité** : pour chaque topic (par `topic.rank`), prendre
     l'article au meilleur score (1 article max par topic), jusqu'à 5.
   - **Round remplissage** : compléter par tous les articles restants
     triés par score décroissant, dédupe par `content_id`, jusqu'à 5.
4. Fallback no-prefs : si pas de sources/topics suivis, le scorer dégénère
   en `+5 * perspective_count - rank * 0.5`. Le rank=1 de chaque topic
   reste prioritaire — comportement proche de l'actuel.

## Tests ajoutés (`tests/test_essentiel_endpoint.py`)

- `test_followed_source_promoted_above_unfollowed_competitor`
- `test_user_topic_weight_promotes_lower_ranked_topic`
- `test_no_prefs_falls_back_to_rank_order`
- `test_perspective_count_breaks_ties_when_no_prefs`
- Test endpoint HTTP qui injecte un `UserSource` + `UserInterest` en DB et
  vérifie que l'article suivi sort en rank=1.

## Non-objectifs

- Pas d'appel LLM au request time.
- Pas de migration Alembic.
- Pas de changement du schéma de réponse `EssentielResponse`.

## Risques / mitigations

- **Régression du fallback no-prefs** : couvert par
  `test_no_prefs_falls_back_to_rank_order` (sans prefs, comportement
  équivalent à l'ancien ordre rank-driven).
- **Coût latence** : 2 requêtes SQL additionnelles (`UserSource`,
  `UserInterest+UserSubtopic` via UNION), toutes indexées sur `user_id`,
  négligeable devant le coût `read_digest_or_fallback`.
