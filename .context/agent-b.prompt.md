# 🤖 Agent B — PR 2 : Mobile champ unique

Tu es dev mobile Flutter sur le projet Facteur (Flutter + Riverpod + FastAPI backend).
Repo : /home/user/facteur — branch de travail : claude/smart-search-pr2-mobile-field (à créer depuis main).

**PRÉREQUIS** : PR 1 mergée, migration SQL exécutée, staging déployé avec endpoints smart-search fonctionnels.

## MISSION
Implémenter le champ unique et cartes enrichies (PR 2 sur 3) pour remplacer les 3 onglets de AddSourceScreen.

## LECTURES OBLIGATOIRES
1. CLAUDE.md
2. docs/stories/core/12.1.smart-source-search.story.md — AC 1-5 et 9
3. docs/stories/core/12.1.smart-source-search.ui.md — wireframes + composants
4. docs/stories/core/12.1.smart-source-search.prs.md — section "PR 2"
5. apps/mobile/lib/features/sources/screens/add_source_screen.dart
6. apps/mobile/lib/features/sources/widgets/source_preview_card.dart
7. Endpoint : POST /api/sources/smart-search (tech.md)

## SCOPE
- Retrait SegmentedControl (3 onglets)
- Nouveau SmartSearchField (debounce 350ms)
- Nouveau SourceResultCard (favicon + 3 items + CTAs)
- Provider smartSearchProvider (FutureProvider.family)
- États : loading skeleton / empty / error / résultats
- Retrait transforms côté client (_transformYouTubeInput, etc.)
- Tests flutter test
- QA handoff .context/qa-handoff.md

## HORS SCOPE
- Brise-glace thèmes (PR 3)
- Pépites compactes (PR 3)
- Endpoints /by-theme, /themes-followed (PR 3)

## CONTRAINTES
- Design système Facteur existant
- Accessibilité : Semantics.label explicite FR
- Debounce 350ms, submit explicite
- Skeleton loading (pas spinner centré)
- Tout résultat est validé serveur (feed discovery)

## WORKFLOW
1. CODE : implémente selon ui.md
2. TESTS : flutter test + flutter analyze → green
3. QA HANDOFF : rédige .context/qa-handoff.md (scénarios 1-5, 10-12)
4. PR vers main (--base main)
5. STOP : "PR créée #XX. /validate-feature pour QA Chrome, puis merge pour Agent C"

## NE PAS faire
- Ne pas toucher backend
- Ne pas implémenter brise-glace thèmes
- Ne pas merger toi-même
