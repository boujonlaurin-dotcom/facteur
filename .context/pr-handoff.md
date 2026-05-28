# fix(perspectives): strip source suffix backend + intro inline + clamp legacy spans

## Contexte

Trois symptômes en prod sur la feature « Diff Highlighting » (Story 7.4) :

1. **Tout au même alpha** — pas de niveau de surlignage différencié visible.
2. **Aucun texte d'intro** dans la vue inline « Couverture médiatique » du
   reader d'article (seul le modal en avait un).
3. **Noms de journaux surlignés à tort** (`« - Le Monde »`, `« | Libération »`)
   et un strip client fragile qui décalait les positions.

Diagnostic SQL prod confirmé avant code :

| | Résultat |
|---|---|
| `cluster_title_annotations` (LLM) | **0 rows** |
| `contents.cluster_id` 7j | **0 / 13 532** |
| `MISTRAL_API_KEY` Railway | présent (autres uses-cases du matin OK) |

→ Symptôme 1 est ops : `_persist_content_cluster_ids` ne produit pas en prod
malgré Sprint 3 mergé. À traiter hors PR — cette PR couvre uniquement les
symptômes 2 + 3 et prépare le terrain pour quand les annotations LLM
arriveront enfin.

## Changements

### Backend

- **`perspective_service.py`** : nouveau `_strip_source_suffix(title,
  source_name)` appliqué à l'ingestion RSS Google News. Path primaire = match
  exact contre `<source>` (100% safe). Fallback regex restrictive
  `\s+[-–|]\s+[A-ZÀ-Ý][A-Za-zÀ-ÿ0-9\s'.&-]{0,40}\s*$` : 7,3% des titres prod
  matchent un séparateur, mais l'échantillon de 30 montre que la regex large
  initialement proposée aurait massacré des titres légitimes
  (`« Flipper One - Le Linux de poche qui terrifie ses propres créateurs »`,
  `« Etats-Unis – Iran : Finkielkraut espère »`, suffixes
  `« - 26/05 »`). La regex restreinte (uppercase initial, pas de `:`,
  ≤ 40 chars) les préserve. Dedup `title.split(" - ")[0]` retirée — devenue
  redondante puisque le titre stocké est déjà clean.

- **`routers/contents.py` `_attach_highlight_spans`** : clamp défensif des
  spans LLM lus depuis `semantic_equiv` (`0 <= start < end <= len(title)`).
  Protège la mise en page Flutter contre les rows historiques calculés sur
  les titres bruts pré-strip.

- **`llm_bias_annotation_service.py`** : prompt enrichi — la catégorie
  `exclude_spans.noise` mentionne explicitement les suffixes médias résiduels.
  `LLM_VERSION` → `mistral-medium-latest-v2`, snapshot regénéré (anti-dérive
  silencieuse). Safe : 0 annotations existantes en prod à invalider.

### Frontend

- **`perspectives_bottom_sheet.dart`** :
  - `kHighlightIntroText` extrait en constante partagée (single source of
    truth pour modal + inline).
  - `_PerspectiveCard.build()` : strip client `.replaceAll(RegExp(...))`
    retiré, simple `.trim()` puisque l'API émet désormais des titres clean.
  - `_buildExpandedBody` (vue inline « Couverture médiatique » expanded
    dans le reader) : intro 2 lignes ajoutée en haut du groupe, une seule
    fois, conditionnelle sur `variants.isNotEmpty`.

## Tests

- `tests/test_perspective_service.py` : 4 nouveaux tests
  (`test_strip_source_suffix_*`) — primary path, fallback, préservation des
  titres légitimes avec tirets, vides/whitespace. Fixture existante mise à
  jour pour refléter le strip à l'ingestion.
- `tests/routers/test_contents_perspectives_highlights.py` :
  `test_attach_highlight_spans_clamps_out_of_bounds_llm_spans` — span valide
  conservé, end > len(title) / start négatif / zero-width tous filtrés.
- `tests/snapshots/llm_system_prompt.txt` : regénéré.
- `apps/mobile/test/features/feed/widgets/perspectives_inline_intro_test.dart`
  (nouveau) : intro présente en mode expanded avec perspectives, absente si
  vide ou collapsé. Le widget test du modal existant continue à passer grâce
  à la constante partagée.

### Résultats

```
472 passed  (pytest tests/routers/ tests/services/ tests/editorial/ tests/test_perspective_service.py)
48  passed  (flutter test test/features/feed/widgets/)
```

`flutter analyze` : 0 nouvel issue sur les fichiers modifiés.

## Test plan

- [x] `pytest -q` backend sweep complet sur les zones touchées
- [x] `flutter test test/features/feed/widgets/`
- [x] `flutter analyze` sur `perspectives_bottom_sheet.dart`
- [x] Échantillon prod (30 titres) confirme que la regex restrictive ne casse
      pas les titres légitimes
- [ ] **À faire post-merge** : ouvrir un article avec ≥ 2 perspectives,
      vérifier (a) l'intro 2 lignes apparait en haut de la section
      « Couverture médiatique » expanded, (b) aucun titre n'affiche
      ` - Source` en clair, (c) `curl -D - .../perspectives | grep -i x-bias`
      pour le header (restera `spacy` tant que ops n'a pas réparé le
      pipeline LLM annotation — suivi séparé).

## Suivi ops (hors PR)

`with_llm=0` et `clustered=0/13532` indiquent que `_persist_content_cluster_ids`
ne tourne pas en prod malgré Sprint 3 mergé ce matin (#698). La clé Mistral
est fonctionnelle. Hypothèses à investiguer côté ops :

- Le pipeline 07:30 a-t-il tourné depuis le merge de #698 ?
- Si oui, regarder les logs Railway pour `editorial.llm_annotation.*` /
  `editorial.persist_cluster_ids.*`.
