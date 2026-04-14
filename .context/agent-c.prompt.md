# 🤖 Agent C — PR 3 : Mobile brise-glace thèmes

Tu es dev mobile Flutter sur le projet Facteur (Flutter + Riverpod).
Repo : /home/user/facteur — branch de travail : claude/smart-search-pr3-brise-glace (à créer depuis main).

**PRÉREQUIS** : PR 2 mergée et déployée. Endpoints /by-theme/{slug} et /themes-followed fonctionnels sur staging.

## MISSION
Implémenter le brise-glace thèmes-first (PR 3 sur 3) : ThemeExplorer + drill-down Curées/Candidates/Communauté + pépites compactes + exemples cliquables.

## LECTURES OBLIGATOIRES
1. CLAUDE.md
2. docs/stories/core/12.1.smart-source-search.story.md — AC 6-9
3. docs/stories/core/12.1.smart-source-search.ui.md — wireframes drill-down
4. docs/stories/core/12.1.smart-source-search.prs.md — section "PR 3"
5. apps/mobile/lib/features/sources/screens/add_source_screen.dart (post-PR2)
6. Composants trending existants (à compacter)
7. Endpoints : GET /by-theme/{slug}, GET /themes-followed (tech.md)

## SCOPE
- Nouveau ThemeExplorer (strip thèmes suivis)
- Nouveau ThemeSourcesScreen (drill-down groupes Curées/Candidates/Communauté)
- Nouveau CommunityGemsStrip (compactage carrousel trending)
- Nouveau ExampleChips (4 exemples cliquables)
- Providers : themesFollowedProvider, sourcesByThemeProvider
- Fallback "user sans thèmes" → thèmes par défaut (Tech / Actu FR / Produit)
- Animations : Hero chip → screen, crossfade empty → résultats
- Tracking analytics : add_source_theme_tap, add_source_example_tap, add_source_gem_tap
- Tests flutter test
- QA handoff .context/qa-handoff.md

## HORS SCOPE
- Backend (PR 1 fait)
- Champ unique et résultats (PR 2 fait) — brancher ExampleChips seulement
- Autocomplete live (v1.1)

## CONTRAINTES
- Design système
- Accessibilité : chips ≥ 44x44, Semantics.button
- Priorité visuelle : Thèmes > Pépites
- Dédup serveur déjà fait

## WORKFLOW
1. CODE : implémente selon ui.md
2. TESTS : flutter test + flutter analyze → green
3. QA HANDOFF : rédige .context/qa-handoff.md (scénarios 6-9, 11)
4. PR vers main (--base main)
5. STOP : "PR créée #XX. /validate-feature pour QA complète, puis merge. Feature prête → suivi post-merge (semaines 1/2/4)"

## NE PAS faire
- Ne pas ré-implémenter PR 1 + PR 2
- Ne pas ajouter autocomplete live
- Ne pas merger toi-même
