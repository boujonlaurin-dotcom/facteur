# Bug: Surlignage progressif des titres invisible en prod (Couverture médiatique)

## Status: IN PROGRESS (round 2 — vraie cause racine)

## Date: 2026-05-18 (round 1), 2026-05-19 (round 2)

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

---

## Round 2 — re-test post-déploiement PR #624 : toujours invisible

PR #624 mergée + déployée sur Railway. Re-test mobile : **aucun surlignage**.
Les Causes B et C ci-dessus étaient des effets, pas les vraies racines. Deux
bugs indépendants se cumulent et la PR #624 n'en règle aucun pour le chemin
réellement utilisé par l'utilisateur ("Couverture médiatique" = modale).

### Cause racine #1 — Backend : spaCy n'est plus installé en prod

`packages/api/requirements-ml.txt` (ligne 9) :
```
# spacy==3.8.11 (NER, ~100MB RAM)
```
…liste spaCy parmi les *"Previous local dependencies (removed)"*. Le
`requirements.txt` ne contient effectivement plus `spacy`, et le `Dockerfile`
ne télécharge plus le modèle `fr_core_news_md`.

Chaîne de dégradation 100 % silencieuse :
1. `ner_service.py:_load_model()` catche `ImportError` → `self._nlp = None`
   (log unique `ner.spacy_not_installed`)
2. `title_annotation_service.py:__init__` log `title_annotation.nlp_unavailable`
   puis continue avec `_nlp = None`
3. `compute_strong_tokens` / `compute_strong_tokens_batch` retournent `[]` dès
   que `_nlp is None`
4. `routers/contents.py:_attach_highlight_spans` (lignes 838-847) catche toute
   exception et pose `highlight_spans=[]` partout

→ Le batch off-cluster `nlp.pipe()` que la PR #624 a "réactivé" en supprimant
l'early-return ne tourne donc **jamais** : il n'y a pas de `nlp` à appeler.

### Cause racine #2 — Mobile : la modale ignore complètement DiffTitle

"Couverture médiatique" ouvre :
- `apps/mobile/lib/features/digest/widgets/topic_section.dart:878` →
  `showModalBottomSheet(PerspectivesBottomSheet(...))`
- `apps/mobile/lib/features/feed/widgets/article_viewer_modal.dart:165` →
  idem

Dans cette modale, `_PerspectiveCard.build()`
(`perspectives_bottom_sheet.dart:611`) rend le titre via un **`Text()` brut** —
pas `DiffTitle`. Les champs `highlightSpans` / `sharedTokens` ajoutés sur l'objet
`Perspective` par la PR #624 arrivent bien sur l'objet mais sont **totalement
ignorés** par ce widget.

Le widget inline `_VariantRow` (ligne 1785 du même fichier) utilise bien
`DiffTitle`, mais ce n'est pas le chemin que l'utilisateur emprunte depuis
"Couverture médiatique".

→ Conséquence : même après le fix Cause racine #1 (backend), le titre de la
modale resterait gris uni. La PR #624 a corrigé deux faux problèmes.

## Fix round 2

### Backend
- `packages/api/requirements.txt` : ajouter `spacy==3.8.11`
- `packages/api/Dockerfile` : ajouter `RUN python -m spacy download fr_core_news_md`
- `packages/api/requirements-ml.txt` : retirer le commentaire "removed" sur spacy
- Nouvel endpoint `/api/internal/admin/ner-health` : retourne
  `{nlp_available, model_version, sample_tokens}` pour un titre canonique →
  permet de diagnostiquer sans redéployer à l'aveugle la prochaine fois.

### Mobile
- `perspectives_bottom_sheet.dart` (`_PerspectiveCard`, ligne 611) :
  migration `Text(...)` → `DiffTitle(...)` en suivant le pattern de
  `_VariantRow` ligne 1785.
- `maxLines: 4` propagé sur tous les usages de `DiffTitle` (le défaut à 2
  coupait trop tôt et masquait la moitié des mots-clés divergents).

### Leçons apprises
- **Une suppression "soft" de spaCy (retirée du requirements.txt + commentée
  dans requirements-ml.txt) sans audit des appelants laisse des chaînes de
  code qui tournent dans le vide.** Les logs `nlp_unavailable` étaient bien
  émis, mais personne ne les surveillait.
- **Pas d'endpoint de santé interne pour les services ML** → la seule façon
  de détecter ce drift était d'observer l'UX cassée. À corriger avec
  `/admin/ner-health`.
- **Les tests existants mockaient `FakeNlp`** : ils ne pouvaient pas détecter
  l'absence réelle de spaCy en prod. Limite connue, à compléter à terme par
  un smoke test E2E qui appelle l'endpoint health au boot.
