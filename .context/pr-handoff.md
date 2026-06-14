feat(onboarding): préférences « profondes » ré-aiguillées + swipe désambiguateur (Story 2.8)

Recentre les questions d'intro de l'onboarding sur les axes qui distinguent les **sources d'un même thème**, et les **câble enfin** au recommender (jusqu'ici `approach`/`response_style` étaient collectés mais jamais utilisés). Additif, **aucune migration**.

## Ce que ça change

- **Profondeur** (ré-aiguillage de `approach`) : sources qui vont à l'essentiel (`direct`) vs qui creusent (`detailed`).
- **Indépendance** (nouvelle question) : références établies vs indépendants. Cadré comme un **goût**, pas un jugement de fiabilité.
- **Posture (ex-`response_style`) RETIRÉE** du parcours (décision PO : ne discrimine pas, presque tout le monde veut voir les perspectives). Le signal de perspective vient désormais du seul swipe (carte « autre angle »).
- **Swipe désambiguateur** : page active (parcours « curieux » ; sautée si « je connais déjà »), cartes étalées sur les axes (fond / actu / indépendant / référence / perspective) ; chaque swipe = vote *révélé* qui repondère le recommender. Sources likées **pré-sélectionnées** au reveal.

## Câblage & stockage (additif, sans migration)

- `SourceRecommender.recommend()` reçoit `depthPref`, `independencePref`, `swipeLiked`, `swipeDisliked` → deltas de score (réutilise le scoring thème/fiabilité existant) + `buildSpanningSet()` pour le swipe.
- `score_independence`/`bias_stance`/`source_tier` déjà sérialisés côté API (aucun champ source ajouté).
- Backend : `OnboardingAnswers` gagne `independence_pref`/`swipe_liked`/`swipe_disliked` (optionnels, payload sans eux reste valide) ; `save_onboarding` persiste `independence_pref` + agrégats `swipe_liked_count`/`swipe_disliked_count` (≤ 100 car., aucune migration).
- Version onboarding Hive **5 → 6** (réindexation d'enums).

## Changements connexes (heads-up review)

- **Fix d'un `changelog.json` malformé pré-existant** sur `main` (entrée « Corrections » du #842 fusionnée avec « Grille » sans séparateur → JSON invalide, `json.decode` cassé). Corrigé + entrée `Onboarding` ajoutée.
- **Feed filters** : la priorisation « Rester serein » lisait `responseStyle == 'nuanced' || perspective == 'big_picture'` (deux signaux désormais morts) → re-câblée sur l'objectif vivant `anxiety`.

## Vérification

- Backend : `pytest` ciblé → **17 passed** (parsing, persistance, backward-compat sans les nouveaux champs).
- Mobile : `flutter analyze` → **0 erreur** ; `flutter test test/features/onboarding/ test/features/feed/personalized_filters_provider_test.dart` → **64 passed**.
- Swipe bâti sur `Dismissible` (built-in) → **aucune dépendance ajoutée**.

## Follow-ups explicites (hors scope, cf. story 2.8)

- Intégrer les axes dans les pillars du feed serveur + persister l'affinité par source issue du swipe.
- Backfill `tone` via le pipeline d'évals (futur axe « ton »).

🤖 Generated with [Claude Code](https://claude.com/claude-code)
