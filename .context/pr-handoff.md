# PR — Veille V3 PR3 « UX polish (intro + presets + pré-loading) »

## Summary

PR3 du V3 veille (suite de #561 PR1 critical fixes et #562 PR2 sources rankées). Trois améliorations UX du flow de configuration, focalisées sur la perception de fluidité et l'accès aux pré-sets :

- **T4** — Pré-loading actif des suggestions LLM entre les steps. L'animation halo (`FlowLoadingScreen`) reçoit désormais `topicsParams` / `sourcesParams` et déclenche le pré-fetch en arrière-plan dès le tap « Continuer ». Durée adaptive : 1.5 s minimum d'animation, puis on attend `data|error` du provider (cap 8 s). À l'arrivée sur Step2/Step3, plus de spinner secondaire dans le cas nominal.
- **T5** — Nouvel écran `VeilleIntroScreen` au premier accès `/veille/config` (pas de config active, pas de mode édition). Single-page minimaliste : pitch + halo animé + CTA « C'est parti ». Skipé en mode édition et après `applyPreset`.
- **T6** — Repositionnement des pré-sets dans Step1. Suppression de la section `_InspirationsSection` en bas du scroll. Ajout d'un teaser tappable « Pas inspiré ? Pioche un pré-set → » sous le header (visible sans scroll), qui ouvre une bottom sheet `VeillePresetsSheet` listant tous les pré-sets via `PresetCard` (workflow Step1.5 preview inchangé).

## Fichiers modifiés

- `apps/mobile/lib/features/veille/screens/veille_intro_screen.dart` (NOUVEAU)
- `apps/mobile/lib/features/veille/screens/veille_config_screen.dart` (T4 + T5)
- `apps/mobile/lib/features/veille/providers/veille_config_provider.dart` (T4 + T5 — durée adaptive, helpers params, `introCompleted`, `completeIntro`)
- `apps/mobile/lib/features/veille/screens/steps/step1_theme_screen.dart` (T6 — teaser + bottom sheet, suppression `_InspirationsSection`)
- `docs/stories/core/19.3.veille-v3-pr3-ux-polish.md` (NOUVEAU — story doc)

## Tests

- `flutter analyze` — pas de nouveau warning sur les fichiers veille.
- `flutter test test/features/veille/` — 51/51 verts.
- Suite complète : 554 verts. Les 37 échecs (digest, feed, custom_topics, etc.) sont **pré-existants** (vérifié sur `main` avant PR3, certains marqués « Test not implemented »).
- Playwright MCP : flow complet validé (intro → Step1 → preset bottom sheet → Step1.5 preview → Step2/3 avec animation halo + données chargées → Step4 → submit).

## Risques

- **Cohérence des params** entre `goNext()` / `FlowLoadingScreen` / `step2_suggestions_screen` / `step3_sources_screen` : les helpers `notifier.topicsParamsFromState()` et `notifier.sourcesParamsFromState()` factorisent la construction et garantissent une clé `family.autoDispose` identique (sinon double fetch).
- **`introCompleted: true` dans `applyPreset` et `hydrateFromActiveConfig`** : empêche l'intro de réapparaître après un preset apply ou en mode édition.
- **Annulation pendant loading** : `_waitAndAdvance` vérifie `state.loadingFrom != from` avant de pousser la transition pour éviter un push stale si l'utilisateur close le flow ou submit pendant l'animation.
