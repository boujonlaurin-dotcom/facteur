# PR — fix: editorial_v1 pipeline crash + missing config prompts

## Quoi
Corrige 3 bugs qui empêchaient le pipeline éditorial de fonctionner en prod après activation de MISTRAL_API_KEY :
1. `TypeError: 'EditorialPipelineResult' has no len()` — crash à chaque force-regeneration
2. `'EditorialConfig' has no attribute 'writing_prompt'` — prompts writing/pepite jamais définis
3. JSON truncation sur query_expansion (max_tokens trop bas)

Ajoute aussi des guardrails : log explicite si YAML manquant, fallback si editorial vide, log du config summary au boot.

## Pourquoi
Après ajout de MISTRAL_API_KEY sur le service WEB Railway, le pipeline éditorial s'activait enfin mais crashait immédiatement (500 Internal Server Error sur chaque `POST /api/digest/generate?force=true`). Les 3 bugs proviennent de Story 10.24 (writer.py) qui référençait des champs config jamais ajoutés, et de `digest_service.py` qui n'avait pas été adapté pour le nouveau type de retour `EditorialPipelineResult`.

## Fichiers modifiés
**Backend :**
- `packages/api/app/services/digest_service.py` — fix `len()` sur EditorialPipelineResult (lignes 230, 302) + guardrail subjects vides
- `packages/api/app/services/editorial/config.py` — ajout 3 champs prompt (writing, writing_serene, pepite) + loader + logs manquant YAML + log config summary

**Config :**
- `packages/api/config/editorial_prompts.yaml` — ajout prompts writing, writing_serene, pepite + fix query_expansion max_tokens 150→500

## Zones à risque
- **`config.py` @lru_cache** : le cache est process-lifetime. Si le YAML est absent au premier appel, les defaults (editorial_enabled=False) sont cachés pour toujours. Le nouveau log `editorial_config_yaml_missing` rend ce cas visible. Un redeploy Railway reset le cache.
- **`editorial_prompts.yaml`** : les prompts writing/pepite sont des first drafts. Le LLM (Mistral) peut ne pas respecter le format JSON attendu → les handlers dans writer.py gèrent déjà le graceful degradation (return None).
- **`digest_service.py:258-266`** : nouveau guardrail "empty editorial subjects" force un fallback vers emergency candidates. Vérifier que le fallback ne crée pas de doublon de digest en DB.

## Points d'attention pour le reviewer
1. **Type safety du `len()`** : les 2 fix utilisent `isinstance(digest_items, EditorialPipelineResult)` — même pattern que le check existant à la ligne 240. Pas de risque de régression pour topics_v1/flat_v1.
2. **Prompts YAML** : les doubles accolades `{{...}}` sont nécessaires car le YAML est lu brut (pas de f-string). Le writer.py envoie le `system` prompt tel quel au LLM — les `{{` seront interprétés comme des littéraux JSON, pas des placeholders Python.
3. **`if not config_path.exists()`** : transforme le silent-default en error log explicite. Ne change PAS le comportement (defaults toujours utilisés) mais rend le problème visible dans Railway.
4. **`editorial_config_loaded` log** : appelé une seule fois (lru_cache). Vérifier dans Railway que les flags sont corrects après deploy.

## Ce qui N'A PAS changé (mais pourrait sembler affecté)
- `digest_selector.py` : aucune modif. Les 4 fallback branches (not_enabled, no_api_key, global_ctx_failed, exception) sont inchangées.
- `writer.py` : aucune modif. Les AttributeError sont résolus côté config, pas côté writer.
- `llm_client.py` : aucune modif. Le `is_ready` check fonctionne maintenant que MISTRAL_API_KEY est set.
- `editorial_config.yaml` : aucune modif (editorial_enabled: true, whitelist vide = tous users).
- Le flow `GET /api/digest` (lecture d'un digest existant) n'est pas affecté.

## Comment tester
1. **Vérif config au boot** : après deploy, chercher dans Railway logs :
   - `editorial_config_loaded` avec `editorial_enabled=true`, `has_writing_prompt=true`, `has_pepite_prompt=true`
   - Absence de `editorial_config_yaml_missing` ou `editorial_prompts_yaml_missing`

2. **Force-regeneration** :
   ```
   POST /api/digest/generate?force=true
   ```
   - Réponse doit avoir `format_version: "editorial_v1"` (pas `topics_v1`)
   - Chercher `digest_editorial_completed` dans les logs (pas de fallback)

3. **Fallback fonctionne toujours** :
   - Si MISTRAL_API_KEY est retirée → `digest_editorial_no_api_key` dans les logs → digest en topics_v1
   - Si prompts YAML vide → writing/pepite seront null (graceful) mais le digest éditorial sera créé

4. **Régression topics_v1** :
   - `GET /api/digest` pour un user qui a déjà un digest du jour → doit retourner le digest existant sans re-génération
