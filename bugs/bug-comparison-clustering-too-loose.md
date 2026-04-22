# Bug — Clustering trop large dans la fonctionnalité Comparaison (Perspectives)

**Date** : 2026-04-22
**Branche** : `boujonlaurin-dotcom/fix-comparison-clustering`
**Sévérité** : P1 — UX dégradée sur l'écran Comparaison (articles hors-sujet)
**Statut** : Implémentation en cours
**Lié à** : `bug-clustering-consistency.md` (#435 plan) — complémentaire, traite les compteurs

---

## 1. Reproduction

Capture utilisateur du 2026-04-22, écran Comparaison ouvert depuis un article France Info "Texas — Dix commandements écoles" :

| Article | Source | Orientation | Pertinence |
|---|---|---|---|
| "Le Texas autorisé à imposer l'affichage des Dix commandements dans les écoles" | France Info | Centre-G | ✅ seed |
| "Le Texas autorisé à imposer l'affichage des Dix commandements dans les écoles publiques" | Le Monde | Centre-G | ✅ même sujet |
| "Du Texas à New York, une méga tempête hivernale s'apprête à balayer les États-Unis" | France 24 | Centre-G | ❌ météo |
| "États-Unis : au Texas, le combat des femmes pour avorter" | L'Humanité | Gauche | ❌ avortement |

Les 4 articles ne partagent que la localisation "Texas" / "États-Unis".

---

## 2. Root Cause Analysis

### 2.1 Layer 1 (DB interne) — `or_(*entity_filters)` trop permissif

`packages/api/app/services/perspective_service.py:369-444` :

```python
entity_names = _parse_entity_names(content.entities, types={"PERSON", "ORG"})
entity_names = entity_names[:3]
entity_filters = [
    func.array_to_string(Content.entities, " ").ilike(f"%{name}%")
    for name in entity_names
]
stmt = select(Content).where(
    or_(*entity_filters),  # ← matche ANY entity
    Content.source_id != content.source_id,
    Content.published_at >= cutoff,  # 72h
    Content.id != content.id,
).limit(self.max_results)  # 10
```

→ N'importe quel article partageant **1** des 3 entités du seed (et publié dans les 72 h) devient candidat.
→ **Aucun filtre de similarité titre / topic / sémantique** au moment du merge.
→ Si Mistral NER tagge "Texas" comme ORG (cas avéré : "Texas Senate", "Texas State", noms d'orgs locales), le filtre `{"PERSON","ORG"}` n'écarte pas la localisation.

### 2.2 Layer 2 (Google News) — requête lâche

`perspective_service.py:446-468` (`build_entity_query`) :

```python
quoted = [f'"{name}"' for name in entity_names[:3]]
context_words = [...][:2]  # 2 mots du titre
return quoted + context_words
```

Requête type : `"Texas" "écoles" Dix commandements`. Google News élargit fortement, ramène potentiellement n'importe quel article récent mentionnant Texas + un de ces mots.

### 2.3 Layer 3 (fallback titre) — purement lexical

`perspective_service.py:501-510` : si <6 résultats, fallback `extract_keywords(content.title)`. Pour le seed Texas-Dix-commandements, l'extraction priorise les majuscules ("Texas", "Dix"). Ramène encore plus de résultats partageant juste ces mots.

### 2.4 `comparison_quality` informatif uniquement

`packages/api/app/routers/contents.py:626-638` calcule un score `high/medium/low` mais **n'est jamais utilisé pour filtrer** la réponse ni masquer le UI. Le mobile affiche tout.

### 2.5 Aucun re-ranking sémantique

- Pas d'embeddings (pas de pgvector sur `Content`).
- Pas de Jaccard titre↔titre au merge.
- Pas de comparaison `topics` ML-classifiés entre seed et candidats.

---

## 3. Plan d'implémentation (validé)

### Étape 1 — Backend : post-filtre `is_topically_coherent`

Nouveau helper dans `PerspectiveService`. Pour chaque candidat, calcule un score de cohérence vs le seed et rejette si **aucun** des signaux suivants n'est satisfait :

| Signal | Cible | Seuil |
|---|---|---|
| Jaccard titre normalisé | seed.title ↔ candidate.title | ≥ 0.30 |
| Topics ML partagés | seed.topics ∩ candidate.topics | ≥ 1 |
| Entités significatives partagées (PERSON/ORG/EVENT, hors LOCATION) | seed.entities ∩ candidate.entities | ≥ 2 |

**Différence interne vs externe** :
- Layer 1 (DB) : tous les signaux disponibles → filtre strict (3 signaux).
- Layers 2/3 (Google News) : seul le titre est connu → filtre titre Jaccard uniquement.

Réutiliser `normalize_title` + `jaccard_similarity` de `services/briefing/importance_detector.py`. Extraction dans un module `services/text_similarity.py` partagé pour éviter la dépendance circulaire.

### Étape 2 — Backend : `should_display` gate dans le router

`packages/api/app/routers/contents.py` (endpoint `/perspectives`) :

- Recalculer `comparison_quality` **après** le post-filtre.
- Ajouter champ `should_display: bool` dans la réponse.
- Critère : `len(perspectives) >= 2 AND bias_groups >= 2`.

### Étape 3 — Mobile : masquer le CTA Comparer si `should_display=false`

Identifier le widget qui ouvre l'écran Comparaison. Si `should_display=false` :
- Désactiver / masquer le CTA.
- Si l'écran est ouvert quand même (cas legacy / cache), afficher un état vide explicite.

### Étape 4 — Tests

**Backend** (`tests/test_perspective_service.py`) :
- Fixture Texas : seed + 3 candidats (Le Monde même sujet, France 24 tempête, Humanité avortement).
- Assert : seul Le Monde est conservé.
- Edge cases : aucun candidat → `should_display=False` ; 5 candidats on-topic 3 orientations → `quality="high"` + `should_display=True`.

**Mobile** : test widget pour CTA désactivé / état vide.

### Étape 5 — Métriques

Logger structurés dans `get_perspectives_hybrid` :
- `perspectives_filtered_out_count`
- `perspectives_filter_reason` (par candidat : `low_jaccard`, `no_shared_topics`, `no_shared_entities`)

Permet de tuner le seuil 0.30 en prod via Sentry / structlog.

### Étape 6 — Seuils tunables

Nouveau module `services/perspectives/config.py` (ou dans `scoring_config.py`) :

```python
PERSPECTIVE_TITLE_JACCARD_MIN = 0.30
PERSPECTIVE_MIN_VALID_RESULTS = 2
PERSPECTIVE_MIN_BIAS_GROUPS = 2
```

---

## 4. Fichiers modifiés

### Backend
- `packages/api/app/services/text_similarity.py` (nouveau — helpers Jaccard partagés)
- `packages/api/app/services/perspective_service.py` (post-filtre + intégration dans `get_perspectives_hybrid`)
- `packages/api/app/services/briefing/importance_detector.py` (importer depuis text_similarity, supprimer doublons)
- `packages/api/app/routers/contents.py` (`should_display` + recalc quality après filtre)
- `packages/api/app/services/perspectives/config.py` (nouveau — seuils)
- `packages/api/tests/test_perspective_service.py` (fixture Texas + edge cases)

### Mobile
- `apps/mobile/lib/features/<comparison>/...` (à identifier — CTA + état vide)
- `apps/mobile/test/features/<comparison>/...`

---

## 5. Test plan manuel

1. **Backend tests** : `cd packages/api && pytest tests/test_perspective_service.py -v`.
2. **Mobile tests** : `cd apps/mobile && flutter test`.
3. **API live** : `uvicorn app.main:app --port 8080`, hit `GET /contents/{texas_id}/perspectives` → vérifier que tempête/avortement sont absents.
4. **Mobile live** : naviguer vers article Texas, vérifier que Comparer est masqué OU que seul Le Monde apparaît.
5. **Non-régression** : ouvrir un article connu pour avoir un bon clustering (élection, événement multi-sources) → perspectives légitimes toujours là.

---

## 6. Hors scope

- Embeddings vectoriels (pgvector) : option long terme.
- Refonte NER (Mistral → spaCy) : hors scope.
- Re-ranking LLM "are these about the same topic?" : trop coûteux pour le ROI.
- Unification compteurs cluster/biais/recul : voir `bug-clustering-consistency.md` (#435).

---

## 7. Rollout

- Feature flag env `PERSPECTIVE_FILTER_ENABLED` (défaut true) pour rollback rapide.
- Déploiement Railway standard, monitoring Sentry sur log `perspectives_filtered_out_count`.
