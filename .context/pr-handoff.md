# PR — Refactoring pipeline digest : actu matching global (pas per-user)

## Quoi
Le matching d'articles actu est deplace de la phase per-user vers la phase globale du pipeline editorial. Au lieu de filtrer par `user_source_ids`, on prend le meilleur article du cluster tout court (le plus recent, non-paywall). Ajout de garde-fous pour sujets vides et logging diagnostique.

## Pourquoi
Quand un user suit peu de sources, `ActuMatcher._find_best_article()` ne trouvait rien car il filtrait par `user_source_ids` → sujets avec 0 articles → cartes invisibles dans le digest. Decision MVP V2 : le digest editorial est identique pour tous les users. La personnalisation viendra plus tard par ponderation, pas filtrage.

## Fichiers modifies

### Backend — Pipeline editorial
- `packages/api/app/services/editorial/actu_matcher.py` — Ajout de `match_global()` + `_find_best_article_global()` (2 nouvelles methodes, code existant inchange)
- `packages/api/app/services/editorial/pipeline.py` — Appel `match_global()` dans `compute_global_context()` apres le deep matching (ETAPE 3A)
- `packages/api/app/services/digest_selector.py` — Remplace `run_for_user()` par construction directe de `EditorialPipelineResult` depuis `global_ctx`
- `packages/api/app/services/digest_service.py` — Garde-fou sujets vides dans `_create_digest_record_editorial()` + warning log quand `content_id` introuvable

### Tests
- `packages/api/tests/editorial/test_actu_matcher.py` — 6 nouveaux tests pour `match_global()` (classe `TestMatchGlobal`)

## Zones a risque
1. **`digest_selector.py` lignes 273-305** — Le remplacement de `run_for_user()` par construction directe. Si un champ de `EditorialPipelineResult` est oublie, le digest sera incomplet.
2. **`digest_service.py` `_create_digest_record_editorial()`** — Le return type change de `DailyDigest` a `DailyDigest | None`. Les appelants doivent gerer le `None`.
3. **`pipeline.py` compute_global_context()** — L'actu matching est maintenant dans la phase globale async. Si `match_global()` echoue, les subjects n'auront pas d'actu_article.

## Points d'attention pour le reviewer

1. **Return type `_create_digest_record_editorial`** — Passe de `DailyDigest` a `DailyDigest | None`. Verifier que l'appelant dans `digest_service.py` (`get_or_create_digest`) gere deja le cas `None` (il y a un guardrail existant `if is_editorial_format and not digest_items.subjects` qui devrait couvrir, mais le nouveau garde-fou agit apres le stockage).
2. **`match_for_user()` et `_find_best_article()` conserves** — Choix delibere pour permettre un rollback rapide. Le reviewer peut verifier qu'ils ne sont plus appeles nulle part.
3. **`is_user_source=False` toujours** — Le champ reste dans le schema pour backward compat avec le format `editorial_v1` stocke en DB. Le mobile l'utilise-t-il pour un badge ? A verifier.
4. **Pas de `excluded_content_ids` dans `match_global()`** — En per-user, on excluait les contenus deja vus. En global, ce filtre n'a plus de sens (le digest est le meme pour tous). Est-ce acceptable ?

## Ce qui N'A PAS change (mais pourrait sembler affecte)
- **`match_for_user()` et `_find_best_article()`** restent intacts dans `actu_matcher.py` — dead code pour l'instant, conserve pour rollback
- **`EditorialGlobalContext` schema** — Inchange, les subjects qu'il contient ont juste `actu_article` popule maintenant
- **`_build_digest_response_editorial()`** — Le format de stockage `editorial_v1` est identique, seul le contenu change (actu articles proviennent de toutes les sources, pas juste les sources user)
- **Les 7 tests existants `TestMatchForUser`** — Non modifies, toujours valides

## Comment tester

1. **Tests unitaires** :
   ```bash
   cd packages/api && source venv/bin/activate
   python -m pytest tests/editorial/test_actu_matcher.py -v
   ```

2. **Verification integration** (staging) :
   - Creer un user avec 0 ou 1 source suivie
   - Generer un digest editorial
   - Verifier que les 3 sujets ont un `actu_article` non-null dans la reponse API
   - Verifier dans les logs : `editorial_pipeline.actu_matching_done` apparait dans la phase globale (avant `editorial_pipeline.global_context_ready`)

3. **Regression** :
   - Verifier qu'un user avec beaucoup de sources suivies recoit le meme digest qu'un user avec peu de sources (memes articles actu)
   - Verifier que `editorial_digest.all_subjects_empty` n'apparait pas dans les logs (sauf si vraiment aucun article disponible)
