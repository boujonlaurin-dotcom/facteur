# Bug — Couverture médiatique : surlignages absents + spectrum invisible

> **Statut** : RÉSOLU (fix front, 1 PR).
> **PR** : à créer via `/go` après ce doc.
> **Branche** : `boujonlaurin-dotcom/couverture-mediatique-fix-surlignages` (depuis `boujonlaurin-dotcom/couverture-mediatique-front`).
> **Date** : 2026-05-18.

## Symptômes observés

Suite à la PR #619 (refonte hi-fi) et #618 (back `shared_tokens` + `reference_pivot`), test live PO sur un article réel (séisme Chine, 5 sources couvrant — Le Monde / France 24 / L'Humanité / Ouest-France / Le Figaro) :

1. **Bug 1 — Tous les titres variants rendus en `text_tertiary` (gris pâle)**, uniformément. Aucun wash coloré sur les key spans. Aucune cascade animée visible.
2. **Bug 2 — Bandeau cm-panel-inline déformé** : `CoverageSpectrumBar` repoussé hors écran ou clippé.

## Cause racine

### Bug 1 — `DiffTitle._rebuildChunks()` dim tout en l'absence de spans

`apps/mobile/lib/features/feed/widgets/diff_title.dart:162` (avant fix) :

```dart
if (!useSharedAsTertiary) {
  for (var i = 0; i < chunks.length; i++) {
    if (chunks[i].type == _ChunkType.plain) {
      chunks[i] = _Chunk(text: chunks[i].text, type: _ChunkType.dimmedFallback);
    }
  }
}
```

Ce bloc convertit tous les chunks `plain` en `dimmedFallback` (textTertiary) dès que `sharedTokens` est vide — **sans vérifier que `highlightSpans` est non-vide**. Quand le back renvoie `highlight_spans=[]` ET `shared_tokens=[]` (cas légitime : article sans `cluster_id`, cf. `contents.py:743-747`), `_rebuildChunks()` produit un unique chunk plain couvrant tout le titre, puis ce bloc le passe en `dimmedFallback` → tout le titre devient textTertiary.

### Bug 2 — `DecoratedBox` sans enfant peint à hauteur 0

`apps/mobile/lib/features/feed/widgets/coverage_spectrum_bar.dart:37-57` (avant fix) — la `Row` interne du `CoverageSpectrumBar` utilisait le `crossAxisAlignment.start` par défaut, ce qui donne aux enfants des contraintes cross-axis **loose** (0..9). Or chaque enfant est un `Expanded > Padding > DecoratedBox(no child)` : un `DecoratedBox` sans enfant prend la taille **minimale** de ses contraintes, donc 0 en cross-axis sous contraintes loose.

Résultat : les 5 segments se peignent à **96 × 0 pixels** → invisibles. Le PO voyait correctement "Couverture médiatique", "X médias" et le caret du bandeau, mais aucun bandeau coloré entre.

**Diagnostic erroné initial** : j'avais d'abord soupçonné un overflow horizontal (mon widget test mesurait 131 px d'overflow en viewport 390 px). C'était un faux positif : sans GoogleFonts chargé dans le test, le titre se rendait avec un font fallback plus large que la réalité. Sur device, GoogleFonts est chargé et le `Row` ne déborde pas. Le test d'overflow a été conservé comme garde-fou défensif, et la 2e modification (`Expanded` + ellipsis sur le titre) a été conservée pour robustesse sur des viewports très étroits.

## Fix

### Front uniquement, 3 fichiers :

1. **`apps/mobile/lib/features/feed/widgets/diff_title.dart:162`**
   Ajouter garde `&& _animatedSpanCount > 0` au bloc Mode 2 (et déplacer l'assignation `_chunks/_animatedSpanCount` avant pour pouvoir lire `_animatedSpanCount`). **Fix de Bug 1.**
2. **`apps/mobile/lib/features/feed/widgets/coverage_spectrum_bar.dart:40-42`**
   Ajouter `crossAxisAlignment: CrossAxisAlignment.stretch` à la `Row` interne pour que les `DecoratedBox` sans enfant reçoivent des contraintes cross-axis tight et se peignent à hauteur 9px. **Fix de Bug 2 (vraie cause racine).**
3. **`apps/mobile/lib/features/feed/widgets/perspectives_bottom_sheet.dart:1342-1377`**
   Remplacer `Text + Spacer()` par `Expanded(child: Text(..., overflow: ellipsis, maxLines: 1))` + `SizedBox(width: 12)`. Garde-fou défensif contre un overflow sur viewports très étroits.

## Tests

- **`diff_title_test.dart:122`** (existant, renforcé) — vérifie explicitement que le chunk d'un titre sans spans est en `textPrimary`, pas `textTertiary` (regression test direct du Bug 1).
- **`coverage_spectrum_visible_test.dart`** (nouveau) — pump le `CoverageSpectrumBar` seul et vérifie que chaque `DecoratedBox` a une taille > 0 en width ET height (regression test direct du Bug 2 : avant fix, le test capturait `segment[0] height = 0`).
- **`perspectives_inline_overflow_test.dart`** (nouveau) — pump le bandeau en viewport 390×844 et vérifie `tester.takeException() == null` (garde-fou défensif).

## Vérification PO

Après merge :

1. Relancer l'app sur l'article séisme Chine. Bandeau cm-panel-inline : titre + spectrum 5-segs distincts + count + caret tous visibles sans clipping.
2. Ouvrir la carte dépliée. Si le back retourne `highlight_spans` non-vide → washes colorés sur tokens divergents + cascade animée. Si vide (article sans cluster) → titre rendu en `textPrimary` normal sans wash (comportement attendu pour articles solos, scénario 6 du QA handoff).

## Notes

- Le back PR #618 (`shared_tokens` + `reference_pivot`) confirmé mergé sur `main` (commit `d23e2436`).
- **Confirmé via Supabase (2026-05-18)** : les articles testés par le PO ont tous `cluster_id: NULL` :
  - `8a9377f9-f4ee-4535-8c80-7b4a2aae56aa` — "En Chine, un séisme fait deux morts, des milliers de personnes évacuées"
  - `5dc91fb6-e9a9-46e0-a472-ce40858b5485` — "Hantavirus: le MV Hondius attendu aux Pays-Bas avec 27 passagers"

  Les perspectives sont retournées (fetch live Google News, 5 sources) mais le back ne peut pas calculer les annotations spaCy (cf. `contents.py:743-747`) → `highlight_spans=[]` et `shared_tokens=[]` pour tous les variants. **C'est précisément le scénario que mon fix Bug 1 traite correctement** : titres rendus en `textPrimary` normal au lieu de tout-gris.
- **Limitation persistante** : pour ces articles sans cluster, les washes colorés ne s'afficheront pas (rien à diff). Ce n'est pas un bug du présent fix mais une limitation du pipeline d'annotation backend — qui pourrait éventuellement être étendu pour calculer les spans à la volée sur les variants Google News hors-cluster. Hors scope du présent fix.
