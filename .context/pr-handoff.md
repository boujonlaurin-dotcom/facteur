# PR — Top 3 "essentiel-grade" sur sections thématiques (Tournée du jour)

## Pourquoi

Sur Tournée du jour, chaque section thématique affichait 3 articles en pur ordre chronologique (Story 21.2 avait désactivé tout scoring pour éviter une sur-compression). Conséquence : le top 3 était souvent "plat" — 3 articles récents mais sans le bénéfice des signaux forts disponibles (cluster multi-sources, custom topics, qualité éditoriale). L'objectif est de promouvoir 3 articles vraiment "essentiels" sans casser la sémantique « Voir tout » chronologique.

## Ce qui change

### Cœur de la PR (Axes A1 + A3 + B3 + D2 du plan)

**Coverage bonus (A1)** : `PertinencePillar` lit `cluster_source_counts` depuis le contexte et applique un bonus log-calibré `min(30, 12·log2(n))` pour les articles dont le cluster est couvert par plusieurs sources distinctes dans les 24h. Un scoop isolé ne reçoit rien ; un sujet à 5 médias récupère ~28 pts.

**Diversification (A3)** : passe finale `diversify()` par `cluster_id` (fallback `topic_slug`) sur le top 3 des sections thématiques personnalisées. Mode "souple" — si on n'a pas 3 clusters distincts, on relâche pour ne jamais retourner moins de 3 cartes.

**Custom topic boost (B3)** : `CUSTOM_TOPIC_BASE_BONUS` 15 → 25. Le signal d'intention le plus précis dont on dispose pèse maintenant ~50 pts max (multiplier 2.0), au niveau d'un `TRUSTED_SOURCE`.

**Quality floor (D2)** : avant la diversification top 3, on exclut les articles sans visuel + sans contenu in-app + résumé < 100 caractères. Fallback gracieux si le pool devient trop pauvre.

### Mutualisation (partie B + C du plan)

Helpers partagés (nouveaux) :
- `packages/api/app/services/recommendation/helpers/coverage_score.py` → `compute_coverage_score(n)`
- `packages/api/app/services/recommendation/helpers/diversification.py` → `diversify(items, key_fn, ...)`

Consolidation `scoring_config.py` :
- `COVERAGE_BASE = 12.0`, `COVERAGE_CAP = 30.0` (canoniques)
- Aliases rétrocompat : `ESSENTIEL_PERSPECTIVE_BASE/CAP`
- Aliases canoniques : `TOPIC_IS_TRENDING_BONUS = TOPIC_TRENDING_BONUS = 50`, `TOPIC_IS_UNE_BONUS = TOPIC_UNE_BONUS = 35`

Migration `essentiel_service.py` (fonctionnellement équivalent côté code mais ajustement de valeurs) :
- `_perspective_score()` délègue à `compute_coverage_score()`
- `_W_TRENDING` : 40 → 50 (= `TOPIC_IS_TRENDING_BONUS`)
- `_W_UNE` : 30 → 35 (= `TOPIC_IS_UNE_BONUS`)
- ⚠️ Trade-off documenté : on aligne sur les valeurs déjà en prod côté digest topics (plus largement déployées) plutôt que sur les valeurs historiques d'Essentiel.

## Tests

Nouveaux (`packages/api/tests/recommendation/`) :
- `test_coverage_score.py` (4 tests) — monotonie log2, cap, singleton.
- `test_diversification.py` (7 tests) — strict, souple, max_per_key=N, None-keys.
- `test_pertinence_coverage.py` (5 tests) — bonus appliqué + label correct + stacking avec THEME_MATCH.

Suite existante :
- `tests/test_essentiel_endpoint.py` : 33 tests passent (les valeurs `_W_TRENDING/UNE` sont importées comme symboles, pas codées en dur dans les assertions).
- `tests/recommendation/` : pertinence existants OK.
- `tests/test_feed_filters.py`, `tests/test_feed_followed_first_stratification.py`, `tests/test_digest_selector.py` : 46 tests OK.
- `tests/test_custom_topics.py` (sous-classes non-DB) : 13 tests OK (assertion de calibration mise à jour).

## Hors scope (PR 2 / 3 du plan)

- C1/C3 affinity (source × topic, save/like adjacency) — table matérialisée à venir.
- B1 multiplicateur subtopic weight — déjà partiellement appliqué via `_score_subtopics`, à étendre.
- Centralisation du filtrage mute (`mute_helpers.py`) — PR 3 dédiée (risque indépendant, scope trop large).
- `is_une`/`is_trending` direct au feed — non exposés au niveau Content (calculés par `ImportanceDetector` côté digest). Le bonus de couverture (≥3 sources distinctes) capture l'équivalent `is_trending` opérationnel.

## Test plan QA

- [ ] Ouvrir Tournée du jour avec ≥1 thème suivi → vérifier que la section affiche 3 cartes
- [ ] Vérifier que les 3 articles couvrent 3 clusters distincts (pas 3 reprises du même fait)
- [ ] Vérifier qu'aucun article du top 3 n'est dépourvu d'image + de description < 100 chars
- [ ] Snapshot offline (50 users) : comparer overlap top 3 actuel vs nouveau, source diversity, cluster diversity
- [ ] Vérifier que « Voir tout » paginé fonctionne (offset > 0)
