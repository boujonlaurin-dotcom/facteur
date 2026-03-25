# PR — feat: hybrid perspectives search + UI refonte bottom sheet

## Quoi
Refonte complète de la feature "Autres points de vue" : le backend passe d'une recherche Google News par mots-clés titre à un système hybride 3 couches (DB entities → Google News entities quotées → fallback keywords). Le front-end est refondu avec groupement par biais politique, analyse LLM on-demand, et hiérarchie titre-first sur les cartes.

## Pourquoi
Deux problèmes en prod :
1. **Faux positifs** : des mots abstraits du titre ("remords") matchaient des articles sans rapport (ex: Jospin → Jubillar)
2. **Faible recall** : des sujets très couverts (TotalEnergies/Trump) ne retournaient qu'1-2 résultats

Cause racine : la recherche reposait uniquement sur `extract_keywords(title)` envoyés à Google News RSS, sans exploiter les entities LLM déjà en DB (82% de couverture).

## Fichiers modifiés

### Backend
- `packages/api/app/services/perspective_service.py` — Nouvelles fonctions : `_parse_entity_names()`, `search_internal_perspectives()`, `build_entity_query()`, `get_perspectives_hybrid()`, `analyze_divergences()`, `STANCE_LABELS`
- `packages/api/app/routers/contents.py` — Appel hybride remplace l'ancien keyword-only ; nouvel endpoint `POST /{content_id}/perspectives/analyze` avec cache 2h
- `packages/api/app/services/editorial/llm_client.py` — Nouvelle méthode `chat_text()` (appel Mistral plain-text, réutilisable)

### Mobile
- `apps/mobile/lib/features/feed/widgets/perspectives_bottom_sheet.dart` — Refonte majeure : groupement par biais (gauche/centre/droite), zone d'analyse LLM (CTA → skeleton → résultat), cartes titre-first, labels bias bar au-dessus, hauteur max 92%
- `apps/mobile/lib/features/feed/repositories/feed_repository.dart` — Nouvelle méthode `analyzePerspectives(contentId)`
- `apps/mobile/lib/features/feed/widgets/article_viewer_modal.dart` — Passe `contentId` au bottom sheet, icône scales → eye
- `apps/mobile/lib/features/detail/screens/content_detail_screen.dart` — Passe `contentId` au bottom sheet

## Zones à risque

1. **`search_internal_perspectives()` — query SQL `array_to_string + ilike`** : fonctionne mais `array_to_string` bypass le GIN index existant → full scan sur fenêtre 72h (~2500 articles). Acceptable pour le volume actuel, à surveiller si le volume grandit.
2. **`build_entity_query()` — quoted entities dans Google News RSS** : les guillemets dans l'URL encodée pourraient être interprétés différemment par Google News. Si les résultats Google deviennent vides, le fallback Layer 3 compense.
3. **`analyze_divergences()` — appel Mistral** : nouvel appel LLM externe, mais on-demand uniquement (user doit cliquer le CTA) + cache 2h.
4. **`_ShimmerLine` widget** : utilise `AnimatedBuilder` — vérifier que ça compile (le nom correct Flutter est `AnimatedBuilder`).

## Points d'attention pour le reviewer

1. **SQL injection potentielle** dans `search_internal_perspectives` : les `entity_names` viennent de la DB (JSON parsé), pas d'input user direct. SQLAlchemy bind les paramètres via `ilike()`, donc c'est safe — mais à confirmer visuellement.
2. **`or_(*entity_filters)` avec `.where()` comma-separated** : les filtres OR sont bien groupés par `or_()`, puis les autres conditions sont en AND via la virgule. Vérifier que la sémantique SQL générée est correcte (`(A OR B) AND C AND D`).
3. **Pas de test unitaire** pour les nouvelles fonctions backend. Le plan prévoit un script QA E2E (`verify_perspectives_hybrid.sh`) mais il n'est pas encore dans le diff.
4. **Le bottom sheet crée son propre `ApiClient` + `FeedRepository`** dans `_requestAnalysis()` au lieu de passer par un provider Riverpod — pattern inhabituel pour ce codebase (potentiel leak ou double-instance).
5. **`analyze_perspectives` endpoint réappelle `get_perspectives`** si pas en cache — cela re-exécute la requête hybride complète (DB + Google News). Vérifier qu'il n'y a pas de risque de boucle ou de timeout.

## Tuning DOMAIN_BIAS_MAP (2026-03-25)

Le diagnostic layer-by-layer a révélé que le bottleneck principal n'était PAS les paramètres du pipeline (time_window, entity caps, etc.) mais la couverture de `DOMAIN_BIAS_MAP`. Le filtre `unknown` dans `contents.py:524` supprimait les perspectives de domaines non mappés.

**Avant → Après (articles filtrés retournés par l'API) :**

| Article | Avant | Après | Bias groups |
|---------|-------|-------|-------------|
| Deepfakes/Fernandes | 1 | **8** | 3 (center, center-left, right) |
| Bardella | 7 | **10** | 5 (full spectrum) |
| Sihem/Nîmes | 6 | **10** | 3 |
| NBA (no entities) | 1 | 3 | 1 (sports domains = unknown) |
| Lille douane | 5 | **7** | 4 |
| Londres antisémite | 4 | **9** | 5 (full spectrum) |

**Changements :**
- +19 domaines ajoutés à `DOMAIN_BIAS_MAP` (79 total, avant 60)
- `cnews.fr` reclassifié de "far-right" → "right" (cohérent avec bias_distribution qui n'a pas de catégorie far-right)
- Suppression de "far-right" de `STANCE_LABELS`

**Paramètres pipeline inchangés** (déjà bien calibrés) :
- `time_window_hours=72` : L1 trouve 6 résultats pour Bardella (recall forte)
- `entity_cap=3`, `max_terms=3` : bon équilibre
- `context_words=[:2]` : ajoute de la précision dans la majorité des cas
- `fallback_threshold=6` : rarement déclenché car L2 remplit déjà

## Ce qui N'A PAS changé (mais pourrait sembler affecté)

- `extract_keywords()` — inchangé, toujours utilisé en fallback (Layer 3) et dans `build_entity_query` quand pas d'entities
- `search_perspectives()` — inchangé, toujours appelé pour Google News RSS (Layers 2 et 3)
- `_parse_rss()` / `resolve_bias()` — inchangés
- Le filtrage `unknown` bias et le calcul `bias_distribution` dans le router — inchangés
- Le cache 2h perspectives — inchangé (le nouvel endpoint `analyze` a son propre cache séparé)

## Comment tester

### Backend (API locale)
```bash
# 1. Lancer l'API
cd packages/api && source venv/bin/activate
uvicorn app.main:app --reload --port 8080

# 2. Générer un JWT test (voir CLAUDE.md section Tests E2E)

# 3. Test article avec entities (ex: article Jospin)
curl -s -H "Authorization: $TOKEN" \
  http://localhost:8080/api/contents/<content_id>/perspectives | jq '.perspectives | length'
# Attendu: plus de résultats, pas de faux positifs type Jubillar

# 4. Test analyse LLM
curl -s -X POST -H "Authorization: $TOKEN" \
  http://localhost:8080/api/contents/<content_id>/perspectives/analyze | jq '.analysis'
# Attendu: texte d'analyse en français ou null si Mistral indispo

# 5. Test article sans entities → comportement identique à l'ancien (fallback keywords)
```

### Mobile (Chrome)
```bash
cd apps/mobile
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080/api/
# Ouvrir un article → cliquer "Voir tous les points de vue"
# Vérifier: groupement par biais, bouton "Analyser les divergences", cartes titre-first
```
