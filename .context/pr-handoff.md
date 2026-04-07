# PR — Backend: ajout `recul_intro` au pipeline éditorial

## Quoi

Ajout du champ `recul_intro` (1 phrase courte générée par le LLM) à toute la chaîne backend : schemas éditoriaux → prompt writing → parser → pipeline injection → digest_service → API response. Le champ donne une accroche engageante pour l'article de fond ("Prendre du recul").

## Pourquoi

Le bloc "Prendre du recul" dans la carte expanded est quasi invisible (simple chip + titre + "Lire →"). Pour créer une hiérarchie visuelle et rendre le recul engageant, le LLM génère désormais une phrase d'accroche courte (8-15 mots) par sujet ayant un deep article. Le mobile pourra l'afficher sous le titre de l'article de fond.

## Fichiers modifiés

**Backend :**
- `packages/api/app/services/editorial/schemas.py` — `recul_intro: str | None = None` sur `MatchedDeepArticle` et `SubjectWriting`
- `packages/api/app/services/editorial/writer.py` — parsing `recul_intro` depuis le JSON LLM
- `packages/api/app/services/editorial/pipeline.py` — injection `sw.recul_intro → s.deep_article.recul_intro`
- `packages/api/app/services/digest_service.py` — propagation dans le dict deep_article + construction `DigestTopicArticle`
- `packages/api/app/schemas/digest.py` — `recul_intro` ajouté à `DigestTopicArticle` et `DigestItem`

**Config :**
- `packages/api/config/editorial_prompts.yaml` — instructions `recul_intro` + JSON output mis à jour dans `writing` et `writing_serene`

## Zones à risque

1. **`editorial_prompts.yaml`** — Le LLM (Mistral Large) doit respecter le nouveau champ `recul_intro` dans le JSON output. Si le modèle ne le produit pas, le champ reste `None` (backward compat OK). À valider sur un digest réel.

2. **`pipeline.py` injection** — L'injection ne se fait que si `sw.recul_intro AND s.deep_article` existent. Pas de risque de crash, mais vérifier que le LLM génère bien `null` (et non une string vide) quand il n'y a pas de deep article.

## Points d'attention pour le reviewer

- **Backward compat totale** : tous les ajouts sont `str | None = None`. Les anciens digests en DB, les anciens JSON sans `recul_intro` restent lisibles. Aucune migration Alembic nécessaire.

- **Prompt instructions** : les instructions demandent "8-15 mots, pas de paraphrase du titre, forme impersonnelle, factuelle, dense". Identiques dans `writing` et `writing_serene`.

- **JSON output template** : le format passe de `"transition_text": null` à `"transition_text": null, "recul_intro": "...ou null"`. Le LLM pourrait omettre le champ → `s.get("recul_intro")` retourne `None`, ce qui est le comportement voulu.

## Ce qui N'A PAS changé (mais pourrait sembler affecté)

- **`EditorialSubject`** : pas de champ `recul_intro` ajouté ici — il vit sur `MatchedDeepArticle` (le deep article lui-même), pas sur le subject.
- **Mobile** : aucun changement Flutter dans cette PR. Le champ sera consommé dans un PR suivant.
- **Tests existants** : 77 tests editorial passent sans modification. Le champ est optionnel avec default `None`.

## Comment tester

### Backend
```bash
cd packages/api
pytest tests/editorial/ -v    # 77 tests, tous passent
```

### Validation fonctionnelle
1. Déclencher un digest éditorial (ou attendre le cron)
2. Vérifier dans les logs que le JSON retourné par le LLM contient `recul_intro` pour les sujets avec deep article
3. Vérifier via l'API `/digests/{id}` que le champ `recul_intro` apparaît dans les articles avec badge `pas_de_recul`
4. Vérifier qu'un sujet sans deep article a bien `recul_intro: null`
