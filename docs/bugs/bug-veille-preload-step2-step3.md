# Bug : Pré-loading Step2→Step3 (Veille config) — skeleton visible

**Date** : 2026-05-05
**Statut** : Fix prêt
**Impact** : Moyen — UX dégradée à l'arrivée Step3 (et Step1→Step2) du flow
de configuration veille. La promesse "données déjà là à la fin de l'animation
halo" n'est pas tenue ; l'utilisateur voit un `CircularProgressIndicator`
avant les Source/Topic cards.

Régression introduite par PR #563 (V3 PR3 UX polish, T4 « pré-loading »).

---

## Symptômes

À l'arrivée sur **Step3 Sources** après l'animation halo `FlowLoadingScreen`,
l'utilisateur voit un spinner circulaire (fallback `loading` de
`step3_sources_screen.dart:86-90`) pendant 1 à 5 s avant que les
`VeilleSourceCard` n'apparaissent. Même symptôme suspecté sur Step1→Step2.

---

## Cause racine

**Race autoDispose** entre la fermeture de la subscription "helper" du
notifier et le `ref.watch` de l'écran cible.

Dans `_waitAndAdvance(from)`
(`apps/mobile/lib/features/veille/providers/veille_config_provider.dart`,
versions avant fix) :

1. `await minDelay` (1.5 s) puis `await providerReady` (cap 8 s).
2. `_disposePending()` — **ferme la subscription qui maintenait le provider
   `family.autoDispose` vivant**.
3. `state = state.copyWith(step: from + 1, loadingFrom: null)` — déclenche le
   rebuild de `VeilleConfigScreen`.
4. `AnimatedSwitcher` swap `FlowLoadingScreen` → `Step3SourcesScreen`.
5. `Step3.build` exécute son `ref.watch(veilleSourceSuggestionsProvider(params))`.

Entre 2 et 5, le provider n'a aucun listener (le `ref.read` de
`FlowLoadingScreen.initState` ne crée pas de souscription persistante).
Riverpod 2.x dispose les `autoDispose.family` orphelins → recréation au
`ref.watch` de Step3 → `Notifier` constructor → `state =
AsyncValue.loading()` → `_fetch()` → spinner.

---

## Fix

**Defer la fermeture de la subscription au post-frame** suivant le state
update. Le `ref.watch` du nouvel écran a alors souscrit, le provider a
toujours au moins un listener, l'autoDispose ne fire pas.

```dart
// veille_config_provider.dart — _waitAndAdvance
state = state.copyWith(step: from + 1, loadingFrom: null);
SchedulerBinding.instance.addPostFrameCallback((_) {
  _disposePending();
});
```

Cas de sortie de flow (close, reset, dispose) : le state-update n'est jamais
émis, on appelle `_disposePending()` immédiatement avant `return`. Le
notifier `dispose()` appelle aussi `_disposePending()`, donc tout
post-frame en vol devient un no-op (méthode idempotente).

Approches alternatives écartées :
- `ref.keepAlive()` : pas exposé proprement sur
  `StateNotifierProvider.autoDispose.family`.
- `ref.listen` dans `FlowLoadingScreen` au lieu de `ref.read` : déplace la
  garantie dans un widget cosmétique, dépend de l'ordering AnimatedSwitcher.
- Allonger `_loadingMinDuration` : masque le bug.

---

## Tests

- Unit : `veille_config_provider_test.dart` — assert que le compteur
  d'instanciation de `VeilleSourcesSuggestionsNotifier` reste à 1 entre
  la fin du pré-fetch et la souscription Step3.
- Widget : `step3_sources_screen_test.dart` — assert qu'à l'arrivée sur
  Step3 il n'y a pas de `CircularProgressIndicator` et au moins une
  `VeilleSourceCard`.

## Verification

```bash
cd apps/mobile && flutter analyze
cd apps/mobile && flutter test test/features/veille/
```

Manuel : flow `/veille/config` jusqu'à Step3, vérifier l'absence de
spinner après l'animation halo.
