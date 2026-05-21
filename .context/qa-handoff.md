# QA Handoff — Veille mobile V2 + curation LLM synchrone (Story 23.3)

> **Refonte majeure post-PR #633.** Le verdict PO sur PR #633 : Step 2 dupliquait Step 1, Step 3 vide sur cas niche, la curation LLM avait été tuée à tort en Story 23.1. Cette PR ramène la curation LLM **en synchrone** à l'instant du flow, et refait Step 1/2/3 + ajoute la tuile "Autre" + le HaloLoader narratif récupéré du git history.

## Feature développée

### Backend (Story 23.3)
- `packages/api/app/services/veille/llm/` (nouveau) : `angle_suggester.py` + `source_suggester.py` — appels Mistral synchrones, cache TTL 24h, fallback déterministe.
- `packages/api/app/services/editorial/llm_client.py` — réutilisé tel quel.
- `packages/api/app/config.py` — nouveau setting `veille_llm_model` (default `mistral-medium-latest`, override via env).
- `packages/api/app/schemas/veille.py` — 6 nouveaux schemas (`VeilleSuggest{Angles,Sources}{Request,Response}`, `VeilleAngleSuggestion`, `VeilleSourceSuggestion`).
- `packages/api/app/routers/veille.py` — 2 nouveaux endpoints : `POST /api/veille/suggest/angles` et `POST /api/veille/suggest/sources`. Helper `_source_theme_for("other")` mappe vers `"custom"` à l'ingestion source (pas de migration nécessaire, `ck_source_theme_valid` autorise déjà "custom").
- Tests : 14 unit (`tests/services/veille/test_angle_suggester.py` + `test_source_suggester.py`), 5 router (`tests/routers/test_veille_routes.py::TestSuggestEndpoints` + `TestOtherThemeIngestion`).

### Mobile (Story 23.3)
- **Récupéré du git** (`122e63d2~1`) : `widgets/halo_loader.dart` (3 anneaux pulsés + binoculars) + `screens/transitions/flow_loading_screen.dart` (labels narratifs "Le facteur écoute…"). Adapté pour brancher sur le nouveau provider.
- **Tuile "Autre"** : `kVeilleOtherThemeSlug = 'other'` injecté en 10ᵉ tile dans `veille_themes_provider.dart`. Quand sélectionnée, un input `customThemeLabel` s'affiche pour saisie libre du sujet (ex : "Musées contemporains Barcelone").
- **Step 1 refondu** : grid 10 thèmes + un seul champ "Précise ton angle" (fusion purpose + editorialBrief). Bouton "Continuer" → `startTransition(1)`.
- **FlowLoadingScreen with bifurcation** : à la fin de `/suggest/angles`, affiche 2 CTAs : **"Affiner ma veille"** (primary, → Step 2) / **"Passer aux sources"** (secondary, skip Step 2 → Step 3 avec auto-trigger de `/suggest/sources`).
- **Step 2 refondu** : affiche les angles LLM (`state.suggestedAngles`) avec checkboxes + chips keywords éditables (add/remove) + bouton "+ Ajouter un angle perso". Cap soft 8 keywords/angle.
- **Step 3 mis à jour** : affiche `state.suggestedSources` (LLM) en liste principale + sources catalogue (preset) sous "AUTRES SOURCES" + mode advanced URL (déjà OK). Sources LLM envoyées au POST `/api/veille/config` comme `niche_candidate` (dédup feed_url côté backend).
- **Provider extension** : nouveaux fields `customThemeLabel`, `suggestedAngles`, `selectedAngleIndexes`, `suggestedSources`, `selectedSuggestedSourceIndexes`, `loadingAngles`, `loadingSources`, `suggestionError`, `transitionFrom`. Actions : `setCustomThemeLabel`, `loadSuggestedAngles`, `loadSuggestedSources`, `toggleSuggestedAngle`, `updateAngleTitle`, `addKeywordToAngle`, `removeKeywordFromAngle`, `addCustomAngle`, `toggleSuggestedSource`, `startTransition`, `exitTransition`. `_buildUpsertRequest` flatten les keywords des angles cochés (cap 20) + push les sources LLM cochées comme niche_candidate.

### Tests
- **Backend** : 38/38 OK (`pytest tests/routers/test_veille_routes.py tests/services/veille/`).
- **Mobile veille** : 17/17 OK (`flutter test test/features/veille/`).
- **Mobile intégrations** : 61/61 OK (`flutter test test/features/my_interests/ test/features/flux_continu/`).

### POC LLM (rapport au PO)
- `.context/poc-veille-llm/POC_REPORT.md` + `results_mistral-{large,medium}.json`.
- Verdict : `mistral-medium-latest` retenu (~6-15s/appel, qualité acceptable sur les 3 cas réels — Musées Barcelone, Biotech FR, IA générative). Cache TTL 24h pour éviter le re-coût en édition.

## PR associée

À créer via `/go` après ce handoff (cible `--base main`, jamais `staging`).

## Écrans impactés

| Écran | Route | Modifié / Nouveau |
|-------|-------|-------------------|
| Step 1 thème | `/veille/config` | Refondu — 10 tiles (9 + Autre) + input customThemeLabel + 1 champ brief unifié |
| Transition LLM | (interne, `transitionFrom != null`) | **Nouveau** — HaloLoader + labels narratifs + bifurcation pour `from=1` |
| Step 2 angles | `/veille/config` step=2 | Refondu — affiche angles LLM éditables + chips keywords + ajout angle perso |
| Step 3 sources | `/veille/config` step=3 | Refondu — sources LLM en liste principale + advanced URL |

## Scénarios à valider via Chrome (viewport 390x844)

### Scénario 1 — Happy path "Tech IA générative"
1. Aller sur `/veille/config` (sans config existante).
2. Step 1 : sélectionner tile "Technologie", taper brief « IA générative et débats sur la régulation » → Continuer.
3. Vérifier `FlowLoadingScreen` (3 anneaux animés + labels "Le facteur écoute…", ~10-15s).
4. Bifurcation affichée → cliquer "Affiner ma veille".
5. Step 2 : vérifier 5-8 angles affichés avec leurs keywords. Décocher 1 angle. Retirer 1 keyword. Ajouter 1 keyword via "+ Ajouter". Ajouter 1 angle perso. → Continuer.
6. `FlowLoadingScreen(from=2)` → ~10-15s → auto-navigue vers Step 3.
7. Step 3 : vérifier 5-10 sources LLM affichées avec leurs URLs + scores. Décocher 1. Sélectionner advanced mode + ajouter 1 source par URL. → "Créer ma veille".
8. Toast "Veille créée" + redirect `/flux-continu`. Vérifier slot "Ma veille — Technologie" présent + favori dans "Mes intérêts".

### Scénario 2 — Cas niche "Musées contemporains Barcelone" (theme="other")
1. `/veille/config` → Step 1 → sélectionner tile **"Autre"** (10ᵉ).
2. Vérifier l'input "Quel sujet ?" apparaît. Taper « Musées contemporains Barcelone ». Brief : « Suivre les expos temporaires des musées d'art contemporain ».
3. Continuer → FlowLoadingScreen.
4. Vérifier que les angles proposés sont spécifiques (vernissages, expositions temporaires, artistes émergents, etc.), pas génériques.
5. "Passer aux sources" → vérifier que le 2ᵉ FlowLoadingScreen se lance directement → arrive sur Step 3.
6. Vérifier que les sources incluent MACBA, CCCB, Fundació Tàpies, médias locaux Barcelone (Time Out, etc.) — **PAS de "Le Monde / Mediapart" génériques**.
7. Créer → vérifier que le favori "Ma veille — Musées contemporains Barcelone" apparaît dans Mes intérêts.

### Scénario 3 — Édition existante
1. Avoir une veille active (créée via scénario 1).
2. Aller dans Mes intérêts → menu favori veille → "Modifier".
3. Vérifier hydratation du Step 1 (thème + brief).
4. Continuer → FlowLoadingScreen → vérifier que les angles arrivent (cache hit attendu, ~instantané).
5. Modifier 1 angle → Continuer → Step 3 → Créer.
6. Toast "Veille mise à jour".

### Scénario 4 — Fallback LLM
1. Si possible : désactiver MISTRAL_API_KEY côté staging (via Railway env vars), redémarrer.
2. `/veille/config` → Step 1 → Continuer.
3. Vérifier que le HaloLoader laisse place à un message d'erreur gracieux + bouton "Continuer" qui amène à Step 2 vide.
4. Step 2 vide → ajouter angle perso manuel → Continuer.
5. Step 3 sans sources LLM → mode advanced URL forcé → ajouter source par URL → Créer.

### Scénario 5 — Bifurcation "Passer aux sources" sans entrer Step 2
1. Scénario 1 jusqu'à la bifurcation.
2. Cliquer "Passer aux sources".
3. Vérifier que Step 2 n'est PAS affiché (skip direct).
4. Le 2ᵉ FlowLoadingScreen démarre.
5. Vérifier sur Step 3 que les sources sont quand même pertinentes (les angles ont été persisted en background).
6. Créer → vérifier dans le POST `/api/veille/config` (Network) que les topics inclus = les angles LLM tous cochés + leurs keywords flattenés.

## Critères d'acceptation

- [ ] Bifurcation post-Step1 affiche 2 CTAs avec wording "Affiner ma veille" / "Passer aux sources".
- [ ] Cas niche "Musées Barcelone" produit ≥ 5 angles spécifiques et ≥ 3 sources non-génériques.
- [ ] Tile "Autre" + input theme_label custom fonctionnent end-to-end.
- [ ] HaloLoader visible pendant 10-15s sans freeze de l'app.
- [ ] Édition d'une veille existante hydrate le Step 1 (thème + brief) et bénéficie du cache LLM.
- [ ] Aucun appel à `/api/veille/suggestions/*` (anciens endpoints 410 Gone) — c'est `/api/veille/suggest/*` (sans le "s" final).
- [ ] Slot Tournée + favori "Mes intérêts" continuent de fonctionner (régression Story 23.2 non cassée).

## Zones de risque

- **R1 — Latence Mistral medium** : 6-15s par appel observé en POC. `HaloLoader` dimensionné pour absorber. Si > 20s sur staging, switcher `veille_llm_model=mistral-large-latest` via env.
- **R2 — Theme "other" + boost** : `fetch_veille_feed` n'a pas de boost theme pour `theme_id='other'` (keyword-only). Acceptable V1 — vérifier que le feed n'est pas vide après création.
- **R3 — Cache LLM in-process** : si le pod Railway redémarre, le cache est perdu. Pas bloquant V1 (cache 24h pas critique). À monitorer si bench prod montre des appels Mistral excessifs.
- **R4 — Skip Step 2 → angles non visibles** : les angles LLM sont persistés en state mais l'user ne les a pas vus. Vérifier que le POST `/api/veille/config` les envoie bien dans `topics[]` + `keywords[]`.

## Commande pour lancer la QA

```
/validate-feature
```

(lit ce fichier et teste via Chrome viewport 390x844)
