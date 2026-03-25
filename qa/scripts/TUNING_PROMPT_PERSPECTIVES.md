# Prompt de tuning — Pipeline Hybride Perspectives

> **Utilisation** : copie ce prompt dans un workspace Conductor qui a accès au repo + à l'API locale.
> L'agent pourra lancer le script de diagnostic, analyser les résultats, et ajuster les paramètres.

---

## Prompt

```
Tu es un agent @dev qui optimise le matching de perspectives dans Facteur.

## Contexte

Le pipeline hybride de perspectives (`packages/api/app/services/perspective_service.py`) cherche des articles couvrant le même sujet depuis des sources de biais politique différent. Il a 3 couches :

- **Layer 1** (DB interne) : `search_internal_perspectives()` — cherche en DB les articles partageant des entités PERSON/ORG avec l'article source, fenêtre 72h
- **Layer 2** (Google News entities) : `build_entity_query()` → `search_perspectives()` — construit une query Google News avec entités quotées + mots contexte
- **Layer 3** (fallback keywords) : si < 6 résultats, relance Google News avec `extract_keywords(title)` classique

## Ta mission

1. Lance le script de diagnostic :
   ```bash
   bash docs/qa/scripts/verify_perspectives_hybrid.sh
   ```

2. Analyse les résultats de la Phase 6 (diagnostic détaillé) pour chaque article testé :
   - **Layer 1** retourne-t-il des résultats ? Si non, pourquoi ? (pas d'entities, fenêtre trop courte, pas d'articles du même sujet en DB)
   - **Layer 2** construit-il une bonne query ? Les entités quotées sont-elles pertinentes ? Les mots contexte ajoutent-ils de la précision ou du bruit ?
   - **Layer 3** se déclenche-t-il ? Si oui, apporte-t-il des résultats supplémentaires utiles ou des faux positifs ?

3. Identifie les problèmes et propose des ajustements sur ces **paramètres tuneables** :

### Paramètres à ajuster (avec localisation)

| Paramètre | Fichier | Ligne/Méthode | Valeur actuelle | Impact |
|-----------|---------|---------------|-----------------|--------|
| `time_window_hours` | perspective_service.py | `search_internal_perspectives()` | 72 | Fenêtre DB : plus grand = plus de recall, plus de bruit |
| Entity types Layer 1 | perspective_service.py | `search_internal_perspectives()` | `{"PERSON", "ORG"}` | Ajouter `"EVENT"` pour matcher les événements |
| Entity cap Layer 1 | perspective_service.py | `search_internal_perspectives()` | 3 | Nombre max d'entités cherchées en DB |
| Entity types Layer 2 | perspective_service.py | `build_entity_query()` | `{"PERSON", "ORG", "EVENT"}` | Types d'entités utilisés pour la query Google |
| `max_terms` | perspective_service.py | `build_entity_query()` | 3 | Nombre max d'entités quotées dans la query Google |
| Context words count | perspective_service.py | `build_entity_query()` | `[:2]` | Nombre de mots-contexte ajoutés aux entités quotées |
| Fallback threshold | perspective_service.py | `get_perspectives_hybrid()` | 6 | Seuil sous lequel le fallback Layer 3 se déclenche |
| `max_results` | perspective_service.py | `PerspectiveService.__init__()` | 10 | Cap total de résultats retournés |
| `max_keywords` | perspective_service.py | `extract_keywords()` | 5 | Nombre de keywords extraits du titre (fallback) |

### Critères de qualité

Pour chaque article testé, évalue :
- **Precision** : les perspectives retournées parlent-elles du même sujet ? (pas de Jubillar quand on cherche Jospin)
- **Recall** : un sujet très médiatisé retourne-t-il ≥ 5 perspectives ?
- **Diversité biais** : y a-t-il au moins 2 groupes de biais différents (gauche/centre/droite) ?
- **Pas de doublons** : pas 2 résultats du même domaine

### Workflow d'itération

Pour chaque ajustement :
1. Modifie le paramètre dans `perspective_service.py`
2. Relance le diagnostic (Phase 6 du script) sur les mêmes articles
3. Compare avant/après : plus de résultats ? Moins de faux positifs ? Meilleure diversité ?
4. Si amélioration → garde le changement. Si régression → revert.

### Exemples de scénarios à investiguer

- **Article politique (ex: Jospin)** : Layer 1 devrait trouver des articles en DB sur le même politique. Layer 2 devrait quoter "Lionel Jospin" et NE PAS matcher Jubillar.
- **Article économie (ex: TotalEnergies)** : Layer 1 devrait trouver des articles mentionnant TotalEnergies depuis d'autres sources. Recall attendu ≥ 5.
- **Article niche (ex: sujet peu couvert)** : Layer 1 vide, Layer 2 peu de résultats → Layer 3 fallback devrait compléter.
- **Article sans entities** : Layers 1+2 skip → Layer 3 seul = comportement identique à l'ancien pipeline.

## Output attendu

Résume tes findings dans un tableau :

| Article | Entities | L1 (DB) | L2 (Google ent.) | L3 (fallback) | Total | Precision | Issues |
|---------|----------|---------|-------------------|----------------|-------|-----------|--------|
| "Jospin..." | PERSON: Jospin | 2 | 4 | — | 6 | ✅ | — |
| "TotalEnergies..." | ORG: TotalEnergies | 1 | 3 | +2 | 6 | ✅ | L1 faible |
| ...

Puis liste les ajustements de paramètres que tu recommandes, avec justification.
```

---

## Notes pour l'humain

- Le script `verify_perspectives_hybrid.sh` fait la découverte automatique des articles de test en DB (PERSON, ORG, sans entities). Pas besoin de hardcoder des IDs.
- La Phase 6 du script fait un diagnostic layer-by-layer qui donne exactement les données dont l'agent a besoin pour tuner.
- Si le script échoue sur la DB, vérifier que `~/.facteur-secrets` contient bien `DATABASE_URL`.
- Pour tester sur un article spécifique : `curl -s -H "Authorization: Bearer ..." http://localhost:8080/api/contents/<id>/perspectives | jq .`
