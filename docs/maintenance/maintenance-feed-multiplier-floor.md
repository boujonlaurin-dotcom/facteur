# Maintenance — Plancher `priority_multiplier` 0.5 → 0.2 + Malus thème non suivi

> **Branche** : `boujonlaurin-dotcom/feed-audit`
> **Date** : 2026-04-16
> **Type** : Maintenance (calibration algo feed — scope chronologique)

---

## Contexte

Signalement utilisateur (laurin_boujon@proton.me) sur le **Feed chronologique** :
1. **Le Monde sur-représenté** : 2-3 articles du Monde parmi les premiers rendus, malgré préférence "Moins" (1/3)
2. **Thèmes non suivis** qui remontent (moins grave)

Intention produit *(explicite, à préserver)* : un **feed chronologique** qui sélectionne les articles à **ne pas afficher** sur la base des intérêts utilisateurs. Mécanisme soustractif (filtrage), pas additif (scoring).

### Scope

**IN-SCOPE** : feed chronologique uniquement (items principaux `/api/feed` en mode par défaut).

**OUT-OF-SCOPE** (confirmé produit) :
- Le Digest quotidien
- Les 3 carousels du feed (hot cluster, perspectives, community 🌻) — rôle **intentionnel de découvrabilité**
- Les modes scored alternatifs (perspectives, deep_dive, serein)
- La réforme de la formule "ratio normalisé"

## Audit résumé

### Avant : préférence "Moins" (0.5) trop faible

Dans la formule de diversification chronologique (`recommendation_service.py:774-780`) :
```
quota = max(1, ceil(ratio × effective_limit × multiplier))
```

Avec Le Monde (ratio ≈ 0.10 sur 72h) et `effective_limit = 50` :
- multiplier 0.5 ("Moins") → `quota = ceil(0.10 × 50 × 0.5) = 3` slots
- multiplier 0.2 ("Moins" cible) → `quota = ceil(0.10 × 50 × 0.2) = 1` slot

Le plancher 0.5 était insuffisant pour un signal utilisateur fort.

### Avant : thèmes non suivis sans désavantage

`PertinencePillar` applique `THEME_MATCH = +50` en bonus, mais aucun malus quand le contenu est hors thèmes/sous-thèmes suivis. L'article "neutre" reste à score nul, parité avec un cas plus pertinent.

## Changements

### Backend (`packages/api`)

| Fichier | Action |
|---|---|
| `app/schemas/source.py:85-98` | Valeurs autorisées `UpdateSourceWeightRequest.priority_multiplier` : `{0.5, 1.0, 2.0}` → `{0.2, 1.0, 2.0}` |
| `app/routers/custom_topics.py:50-58, 84-92` | Idem pour `CreateTopicRequest` et `UpdateTopicRequest` (le slider Flutter est partagé) |
| `app/services/recommendation/scoring_config.py` | Ajout constante `THEME_MISMATCH_MALUS = -8.0` |
| `app/services/recommendation/pillars/pertinence.py` | Nouveau step `_score_theme_mismatch()` appliqué après les 5 steps existants. Conditions d'application : user a au moins un thème OU sous-thème OU custom topic déclaré + aucun n'a matché |
| `tests/recommendation/test_pertinence_pillar.py` | Nouveau test file (6 cas) : malus appliqué, non appliqué (match thème), non appliqué (sous-thème), cold start, match custom topic, clamp normalisation |
| `app/services/learning_service.py:307, 590` | Alignement du plancher learning sur la nouvelle grille : `max(0.5, …)` → `max(0.2, …)`. Évite que le learning propose/applique une valeur rejetée par le validator, et supprime le UP-clamp silencieux d'un user à 0.2 vers 0.5 |
| `app/routers/sources.py:428` ; `app/services/recommendation/scoring_engine.py:38` ; `app/models/source.py:159` | Docstrings/commentaires alignés `(0.2, 1.0, 2.0)` |
| `tests/test_learning_service.py` | Mocks `proposed_value` alignés `"0.5"` → `"0.2"` (3 fixtures) |

### Mobile (`apps/mobile`)

| Fichier | Action |
|---|---|
| `lib/widgets/design/priority_slider.dart:43` | `_multipliers = [0.5, 1.0, 2.0]` → `[0.2, 1.0, 2.0]` |
| `lib/widgets/design/priority_slider.dart:12-14, 64` | Commentaires MAJ pour refléter 0.2 |

Les comparaisons de seuil (`currentMultiplier <= 0.5`) fonctionnent encore correctement avec `0.2` car `0.2 <= 0.5` → le cran 1 est correctement identifié. Pas de changement de logique.

### Migration DB (one-shot Supabase SQL Editor)

```sql
-- Applique rétroactivement le nouveau plancher aux rows existantes
UPDATE user_sources SET priority_multiplier = 0.2 WHERE priority_multiplier = 0.5;
UPDATE user_topic_profiles SET priority_multiplier = 0.2 WHERE priority_multiplier = 0.5;

-- Aligne les propositions LearningService pending (générées avec l'ancien plancher 0.5)
UPDATE user_learning_proposals
SET proposed_value = '0.2'
WHERE proposal_type = 'source_priority'
  AND proposed_value = '0.5'
  AND status = 'pending';
```

**⚠️ À exécuter en post-merge, AVANT que les nouveaux déploiements backend rejettent les requêtes avec 0.5.**

## Effet attendu

### Le Monde (source à forte fréquence) avec "Moins"
- **Avant** : ~3 articles parmi les 50 premiers rendus
- **Après** : ~1 article parmi les 50 premiers rendus

### Article hors thèmes/sous-thèmes suivis (modes scored)
- **Avant** : pertinence brute = 0 → normalisée 0
- **Après** : pertinence brute = -8 → normalisée 0 (clamp), mais quand couplé à un autre signal positif (format, recency), le malus est soustrait, ce qui désavantage légèrement l'article sans l'exclure

## Ce qui reste hors scope (à considérer ensuite si insuffisant)

- Si Le Monde reste trop présent même à 0.2 : revoir la formule "ratio normalisé" (remplacer par plafond absolu ou ratio inverse)
- Si les thèmes non suivis remontent encore trop : étendre le malus au feed chronologique pur (probabilistic drop ou quota par thème) — actuellement le malus n'affecte **que les modes scored** car le chronologique n'utilise pas `PillarScoringEngine`
- Nettoyer les fuites identifiées dans les carousels (cf. audit initial) — traitement séparé, rôle découvrabilité à préserver

## Verification

### Tests automatisés
```bash
cd packages/api
pytest tests/recommendation/test_pertinence_pillar.py -v
pytest tests/test_custom_topics.py -v
pytest tests/test_source_management.py -v

cd apps/mobile
flutter test
flutter analyze
```

### Observation manuelle (staging)
1. Sur l'account `laurin_boujon@proton.me` : dump `GET /api/feed?limit=50` → count Le Monde articles
2. Appliquer la migration DB (`UPDATE user_sources SET priority_multiplier = 0.2 WHERE ...`)
3. Re-dump → count Le Monde articles → doit avoir baissé
4. Toggle "Normal" sur Le Monde → le feed re-inclut Le Monde à quota "Normal"

### Contrat API
- `PUT /api/sources/{id}/weight` avec `priority_multiplier=0.5` → 422 (rejet attendu)
- `PUT /api/sources/{id}/weight` avec `priority_multiplier=0.2` → 200
- Idem sur `POST/PATCH /api/custom-topics/*`

## Rollback

En cas de régression sévère :
1. Revert le PR
2. Rétablir les rows à 0.5 :
   ```sql
   UPDATE user_sources SET priority_multiplier = 0.5 WHERE priority_multiplier = 0.2;
   UPDATE user_topic_profiles SET priority_multiplier = 0.5 WHERE priority_multiplier = 0.2;
   UPDATE user_learning_proposals
   SET proposed_value = '0.5'
   WHERE proposal_type = 'source_priority'
     AND proposed_value = '0.2'
     AND status = 'pending';
   ```
