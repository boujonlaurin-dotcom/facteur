# Maintenance — Pénalité Sport dans le scoring du digest

> **Branche** : `boujonlaurin-dotcom/less-sport`
> **Date** : 2026-04-20
> **Type** : Maintenance (calibration algo digest — réduction articles Sport)

---

## Contexte

Le digest quotidien (5-7 articles, **identique pour tous les utilisateurs**, modes `pour_vous` et `serein`) donne trop de place aux articles de type Sport par rapport à l'intention produit.

### État existant (avant)

Il existe déjà une dépriorisation au niveau des **clusters éditoriaux** :
- `editorial/pipeline.py:147` appelle `cap_low_priority_clusters(..., max_sport=1)`
- Résultat : au plus 1 cluster Sport parmi les topics du jour

**Gap identifié** : aucune pénalité n'est appliquée au scoring des **articles individuels** dans `digest_selector._score_candidates()`. Conséquence :
- Un article Sport avec bonus source suivie + topic user + très récent peut toujours remonter au top
- Le cap cluster filtre les *topics*, pas la pondération finale des articles

### Intention produit

Réduire mécaniquement la probabilité de sélection d'un article Sport, **sans exclusion dure**. Un Sport vraiment pertinent (source suivie + topic ciblé + très récent) peut encore passer.

### Scope

**IN-SCOPE** : `digest_selector._score_candidates()` — les deux modes (`pour_vous` et `serein`).

**OUT-OF-SCOPE** :
- Le feed chronologique (pas de changement)
- Le cap cluster éditorial (conservé tel quel, complémentaire)
- La classification ML des thèmes/topics (inchangée)

## Implémentation

### 1. Détection Sport unifiée

Nouveau helper `is_sport_content(content)` dans `packages/api/app/services/recommendation/filter_presets.py`, symétrique à `is_sport_cluster` existant. Détecte un article Sport via :
1. `content.theme ∈ LOW_PRIORITY_SPORT_THEMES` (= `{"sport","sports"}`)
2. `"sport" ∈ content.topics`
3. Titre/description matche un `LOW_PRIORITY_SPORT_KEYWORDS` (liste existante : football, rugby, tennis, PSG, Ligue 1, etc.)

Réutilise les constantes déjà définies (lignes 377-408 de `filter_presets.py`).

### 2. Constante de pénalité

Nouvelle constante dans `scoring_config.py` :
```python
DIGEST_SPORT_PENALTY = -40.0
```
Valeur alignée sur `MUTED_THEME_MALUS` (-40). Un Sport avec theme match (+50) + source suivie (+35) + recency récent (+25) = +110 pts bruts peut encore battre un neutre moyen (~60-80 pts).

### 3. Application dans le scoring

Dans `digest_selector._score_candidates()`, juste après `final_score = base_score + recency_bonus` :
- Si `is_sport_content(content)` → `final_score += DIGEST_SPORT_PENALTY`
- Breakdown enrichi avec label "Sport (priorité réduite)" pour transparence algorithmique

### 4. Tests

- `tests/test_low_priority_cap.py` → classe `TestIsSportContent` (5 cas)
- `tests/test_digest_selector.py` → `test_sport_article_gets_penalty` (article Sport vs neutre)

## Fichiers modifiés

- `packages/api/app/services/recommendation/filter_presets.py`
- `packages/api/app/services/recommendation/scoring_config.py`
- `packages/api/app/services/digest_selector.py`
- `packages/api/tests/test_low_priority_cap.py`
- `packages/api/tests/test_digest_selector.py`

Pas de migration DB, pas de changement front mobile, pas de changement d'API.

## Vérification

```bash
cd packages/api && pytest tests/test_low_priority_cap.py tests/test_digest_selector.py -v
cd packages/api && pytest -v
```

Manuel : `GET /api/digest/today` pour un user test → vérifier ≤ 1 article Sport dans les 5-7 et breakdown "Sport (priorité réduite)" pour articles Sport.
