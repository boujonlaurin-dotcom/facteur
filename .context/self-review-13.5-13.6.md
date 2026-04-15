# Self-Review — Carte « Construire ton flux » (Phase 2)

> Commit base : `171cbfa5` · Branche : `boujonlaurin-dotcom/review-flux-card`
> Date : 2026-04-15

---

## 🟢 Points validés

### Architecture
- Structure feature-first cohérente avec `saved/` et `custom_topics/` (config, models, providers, repositories, services, widgets)
- Sealed class state machine (`LcHidden`, `LcVisible`, `LcApplying`, `LcApplied`, `LcSnoozed`, `LcError`) — type-safe, exhaustive
- Manual JSON parsing cohérent avec `content_model.dart` (pas de Freezed pour les modèles read-only)
- Séparation claire : data → repo → notifier → widget

### Riverpod
- `ref.read` vs `ref.watch` correctement choisis partout
- `ref.read(cooldownProvider.future)` (pas `watch`) intentionnel et documenté dans le code — évite rebuild post-`_markCooldown()`, conserve LcApplied/LcSnoozed
- `Future.microtask()` post-build pour set session flag — évite invalidation pendant build
- `ref.listen` dans widget pour réagir aux transitions (apply/snooze → invalidate + toast)
- Providers bien scopés : FutureProvider (cooldown), StateProvider (session), AsyncNotifierProvider (main), Provider (repo, analytics)

### Gating
- 5 portes dans l'ordre correct : kill-switch → QA override → cooldown → session → fetch+signal
- Seuils alignés avec la spec : N≥3, max_signal≥0.6, cooldown 24h, 1/session
- Override QA via SharedPreferences (`learning_checkpoint_force_disabled`)

### Error handling
- Silent fail sur fetch (return empty list + log non-fatal) — ne bloque pas le feed
- Exceptions propagées sur apply → `LcError(error, previous)` avec `previous` préservé
- Repository : DioException + generic catch, timeout 2s

### Analytics
- 5 events correctement nommés : `construire_flux.shown`, `.expand`, `.dismiss_item`, `.validate`, `.snooze`
- Payloads alignés avec `plan-mobile.md` §Analytics (count, types, signal, etc.)

### Tests (pré-phase 2)
- Couverture des chemins critiques : gating G2-G8, actions G9/G11-G15
- Widget tests : card rendering (W1/W3/W4/W5), proposal row (P1-P3/P6/P7)
- Mocks cohérents, `SharedPreferences.setMockInitialValues` pour cooldown

---

## 🔴 Bugs corrigés (bloquants)

### B1 — Feed injection masquait la carte pendant LcApplying *(corrigé)*
- `feed_screen.dart:563` ne gating que `LcVisible`, masquant la carte pendant le POST
- Le widget gérait déjà `LcApplying` (spinner) mais le feed ne le laissait pas passer
- **Fix** : `lcValue is LcVisible || lcValue is LcApplying || lcValue is LcError`

### B2 — Touch targets < 48dp *(corrigé)*
- IconButton dans `proposal_row.dart` : `32x32` → **48x48**
- Dots dans `source_priority_slider.dart` : `16dp` → **48x48** (SizedBox wrapper)
- EntityToggle pill : `~26dp` → **minHeight: 48** (ConstrainedBox)

### B3 — LcError faisait disparaître la carte *(corrigé)*
- `construire_son_flux_card.dart:71` : `LcError` → `SizedBox.shrink()`, pas de retry possible
- **Fix** : si `LcError.previous != null`, affiche la carte avec bouton « Réessayer »
- `validate()` et `snooze()` acceptent maintenant l'état `LcError` en extrayant `previous`

---

## 🟡 Améliorations appliquées

### Y1 — Design tokens *(corrigé)*
- 5 widget files utilisaient des valeurs hardcodées (16, 12, 8, 4, 999, 180ms)
- **Fix** : remplacé par `FacteurSpacing.space{1-4}`, `FacteurRadius.{large,full}`, `FacteurDurations.fast`

### Y2 — `withOpacity` déprécié Flutter 3.27+ *(corrigé)*
- `entity_toggle.dart:32,47` : `.withOpacity()` → `.withValues(alpha: ...)`

### Y3 — Analytics expand non-dédupliqué *(corrigé)*
- `toggleExpanded()` émettait `construire_flux.expand` à chaque toggle
- **Fix** : ajout `expandTrackedIds` à `LcVisible`, dedup par proposal par session

### Y4 — Tests manquants *(ajoutés)*
- `source_priority_slider_test.dart` : rendering, tap interaction, semantics, 48dp (5 tests)
- `entity_toggle_test.dart` : mute/follow labels, toggle callbacks, semantics, 48dp (6 tests)
- `G10` dans provider test : dismiss-all → auto-snooze (1 test)

---

## Résumé des commits phase 2

| # | Hash | Message |
|---|------|---------|
| 1 | `0e13f6a4` | fix: keep card visible during LcApplying and LcError states |
| 2 | `4eb3a712` | fix: ensure all interactive elements meet 48dp touch target |
| 3 | `14f23dae` | refactor: replace hardcoded values with design tokens |
| 4 | `698e7280` | fix: replace deprecated withOpacity with withValues |
| 5 | `54cbc2b8` | fix: dedup expand analytics per proposal per session |
| 6 | `57985c5b` | test: add widget tests for slider, toggle, and auto-snooze |
| 7 | `e2f945f8` | fix: compile error in snooze/validate + update tests |

---

## Résultat tests

```
flutter test test/features/learning_checkpoint/ → 70 tests passed
flutter analyze (learning_checkpoint files) → 0 errors, 6 pre-existing info/warnings
```
