# PR — fix: surlignage progressif des titres (Couverture médiatique) invisible en prod

## Summary

Surlignage progressif des titres invisible en prod (section "Couverture médiatique" / perspectives) car la pipeline backend renvoyait toujours `highlight_spans: []`. Vérifié sur Supabase : `0 / 41 045` contents ont un `cluster_id`, donc l'early-return `if not content.cluster_id` de `_attach_highlight_spans` court-circuitait pour tous les articles. Le batch off-cluster `nlp.pipe()` prévu plus bas n'était jamais atteint.

Bug doc complet : `docs/bugs/bug-perspectives-highlight-spans-missing.md`.

## Changes

### Backend — Cause racine
- `packages/api/app/routers/contents.py` (`_attach_highlight_spans`) : retire l'early-return sur `not content.cluster_id`. La fonction n'appelle `get_or_compute_cluster_annotations()` que si `cluster_id` est présent (évite un scan `WHERE cluster_id IS NULL` sur les 41 k contents standalone). Le batch off-cluster existant calcule alors les tokens spaCy pour toutes les perspectives, `ref_tokens` est obtenu via le fallback `compute_strong_tokens(title)`, et `diff_spans` / `compute_shared_tokens` / `compute_reference_pivot` produisent les données attendues par le mobile.

### Mobile — Bug latent
- `apps/mobile/lib/features/digest/widgets/topic_section.dart` et `article_viewer_modal.dart` : les 2 mappings `PerspectiveData → Perspective` oubliaient `highlightSpans` et `sharedTokens`. Le widget `DiffTitle` recevait `const []` et basculait silencieusement en Mode 2 fallback. Ajout des 2 champs dans les 2 mappings.

### Tests
- `packages/api/tests/routers/test_contents_perspectives_highlights.py` :
  - Remplace l'ancien test qui assertait `highlight_spans == []` sans cluster (comportement bogué) par `test_attach_highlight_spans_computes_for_content_without_cluster` validant le nouveau contrat.
  - Ajoute `test_attach_highlight_spans_without_cluster_skips_db_scan` pour garder l'invariant "pas de scan DB sur cluster_id IS NULL".

## Test plan

- [x] `pytest tests/routers/test_contents_perspectives_highlights.py` → 8/8 passent
- [x] Suite backend complète → 1167 passed, 13 skipped
- [x] `flutter analyze` sur les 2 fichiers mobile modifiés → 0 erreurs
- [x] `flutter test` widgets touchés (DiffTitle, PerspectivesInline, fromJson) → 20/20 passent
- [ ] **Validation prod après merge** : appeler `GET /api/v1/contents/{id}/perspectives` sur un article récent et vérifier que `.perspectives[0].highlight_spans` est non-vide. Visuellement, ouvrir la section "Couverture médiatique" d'un article avec ≥ 3 sources et observer le surlignage progressif des titres dans la vue inline (`PerspectivesInlineSection` → `DiffTitle`).

🤖 Generated with [Claude Code](https://claude.com/claude-code)
