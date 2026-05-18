# Bug: Surlignage progressif des titres invisible en prod (Couverture médiatique)

## Status: IN PROGRESS

## Date: 2026-05-18

## Symptômes

- À l'ouverture de la section "Couverture médiatique" d'un article (perspectives) avec plusieurs sources, le surlignage progressif des éléments identifiés n'apparaît jamais.
- Comportement identique sur tous les articles en prod, depuis le déploiement de la feature.
- Aucune erreur visible côté client ou API.

## Investigation

### Preuves récoltées (Supabase prod `ykuadtelnzavrqzbfdve`)

| Vérif | Résultat |
|------|----------|
| Migration `cta01_cluster_title_annotations` appliquée | OUI (`alembic_version = 5de67819bc61`) |
| Table `cluster_title_annotations` — lignes | **0** |
| Table `perspective_analyses` — lignes | **0** |
| `contents` avec `cluster_id IS NOT NULL` | **0 / 41 045** |
| Table `clusters` | n'existe **pas** |
| `daily_digest` 7 derniers jours | 1 110 lignes (pipeline tourne) |
| Articles de perspective du dernier digest | 12 |
| Articles de perspective avec `highlight_spans` non-vide | **0 / 12** |

### Causes superposées

**Cause B — Live + fast path bloqués par early-return** *(racine en prod)*

`packages/api/app/routers/contents.py:791-795` :
```python
if not content.cluster_id:
    for p in perspectives_dicts:
        p["highlight_spans"] = []
        p["shared_tokens"] = []
    return None
```
Comme **0/41 045 contents** ont un `cluster_id` en prod (le clustering n'est jamais activé), ce early-return s'applique à tous les appels. Le batch off-cluster `nlp.pipe()` situé plus bas (qui pourrait calculer les annotations spaCy à la volée sans cluster) n'est jamais atteint.

Cette fonction est appelée par :
- Le **fast path** snapshot : `routers/contents.py:1012`
- Le **live path** Google News : `routers/contents.py:1166`

Donc les deux retournent toujours des listes vides → `highlight_spans: []` dans la réponse JSON.

**Cause C — Mobile drop les champs lors du mapping** *(bug latent)*

Deux conversions `PerspectiveData → Perspective` oublient `highlightSpans` et `sharedTokens` :
- `apps/mobile/lib/features/digest/widgets/topic_section.dart:879-887`
- `apps/mobile/lib/features/feed/widgets/article_viewer_modal.dart:168-175`

Même après le fix backend, ces deux entrées (modale "Couverture médiatique" depuis le digest, et modale article viewer depuis le feed) ne montreraient rien. Seule la vue inline `content_detail_screen.dart:2822-2831, 3380-3388` passe correctement les champs.

Le widget `DiffTitle` (`apps/mobile/lib/features/feed/widgets/diff_title.dart:37-39, 111-174`) a des defaults `const []` et bascule silencieusement en "Mode 2 fallback" quand les deux listes sont vides → aucune erreur, aucun rendu.

## Fix appliqué

### Backend (cette PR)

**Fichier modifié** : `packages/api/app/routers/contents.py`

`_attach_highlight_spans()` :
- Retire le early-return sur `content.cluster_id is None`.
- Protège l'appel à `get_or_compute_cluster_annotations()` (ne le déclenche que si `cluster_id` est présent, sinon `ClusterAnnotations()` vide — évite une scan complète de la table `contents` sur `WHERE cluster_id IS NULL`).
- Le batch off-cluster `compute_strong_tokens_batch()` existant calcule alors les tokens spaCy pour toutes les perspectives, et `compute_strong_tokens()` calcule `ref_tokens` pour le titre référence.
- `diff_spans()`, `compute_shared_tokens()` et `compute_reference_pivot()` produisent les données attendues par le mobile.

### Mobile (PR suivante)

Ajouter `highlightSpans` et `sharedTokens` dans les 2 mappings cassés. Aucun nouveau widget — `DiffTitle` est déjà utilisé par la vue inline qui marche.

## Vérification

### Local

```bash
cd packages/api && source venv/bin/activate
pytest -v tests/routers/test_contents_perspectives_highlights.py
uvicorn app.main:app --port 8080 &
curl -s http://localhost:8080/api/v1/contents/<id>/perspectives \
  -H "Authorization: Bearer <token>" | jq '.perspectives[0].highlight_spans'
# Doit renvoyer un array non-vide [{start, end, text, bias}, ...]
```

### Prod (après déploiement)

```sql
-- Doit passer de 0 à >0 après prochaine régénération de digest OU au prochain GET /perspectives
WITH recent AS (SELECT items FROM daily_digest ORDER BY created_at DESC LIMIT 1),
subjects AS (SELECT jsonb_array_elements(items->'subjects') AS subj FROM recent)
SELECT SUM((SELECT COUNT(*) FROM jsonb_array_elements(COALESCE(subj->'perspective_articles','[]'::jsonb)) p
            WHERE jsonb_array_length(p->'highlight_spans') > 0))
FROM subjects;
```

Note : la snapshot stockée dans `daily_digest.items` ne contiendra toujours pas `highlight_spans` (les snapshots sont écrites par la pipeline éditoriale, qui n'enrichit pas — c'est intentionnel). En revanche, à chaque `GET /perspectives`, le backend enrichit la snapshot lue à la volée via `_attach_highlight_spans()`. Donc pour valider en prod, appeler l'endpoint et inspecter la réponse plutôt que la table.

## Plan tests unitaires

Étendre `packages/api/tests/routers/test_contents_perspectives_highlights.py` :
- Cas "content sans cluster_id" → `highlight_spans` non-vide pour les perspectives qui divergent du titre référence.
- Cas "content avec cluster_id" inchangé (régression).
