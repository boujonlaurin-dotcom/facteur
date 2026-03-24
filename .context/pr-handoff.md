# PR — feat: onboarding wow — refonte écrans thèmes/subtopics + sources personnalisées

## Quoi
Refonte majeure de l'onboarding Section 3 : séparation thèmes/subtopics en 2 écrans distincts (cloud de thèmes puis cards structurées par thème), ajout d'entités par défaut hardcodées (fallback quand le backend n'en retourne pas), refonte complète de l'écran sources (3 sections personnalisées : Pour vous / Élargissez votre vision / Pépites), suppression des questions Age et Perspective, ajout d'une Page 2 sources.

## Pourquoi
L'onboarding précédent était plat : un seul écran thèmes+subtopics mélangés, des thèmes trop pauvres (Science: 2 entries, Sport: 1, Politics: 1), et un écran sources qui listait toutes les sources curées sans personnalisation. L'objectif est un "wow moment" qui engage l'utilisateur dès le premier contact, avec des recommandations de sources basées sur ses choix de thèmes/subtopics.

## Fichiers modifiés

### Mobile — Data
- `available_subtopics.dart` — Subtopics enrichis (tous les thèmes ont 2-10 entries, isPopular flag, plus de doublons nom=thème), nouvelle map `defaultEntities` (~45 entités hardcodées comme fallback)
- `source_recommender.dart` — **NOUVEAU** : Algorithme de recommandation de sources basé sur thèmes/subtopics/objectives
- `theme_to_sources_mapping.dart` — **SUPPRIMÉ** (remplacé par source_recommender)

### Mobile — Screens
- `subtopics_question.dart` — **NOUVEAU** : Écran Q9b avec cards par thème, subtopics + entities merge, custom topics, CTA "Ajouter un sujet"
- `sources_question.dart` — **REWRITE** : Remplace la liste plate par 3 sections (matched/perspective/gems) avec `SourceRecommendationCard`
- `sources_page2_question.dart` — **NOUVEAU** : Page 2 sources (catalogue + CTAs)
- `themes_question.dart` — Simplifié (cloud pur, plus de subtopics)
- `onboarding_screen.dart` — Routing adapté (ajout subtopics, suppression age/perspective, remplacement sourcesReaction par sources_page2)
- `age_question.dart` — **SUPPRIMÉ**
- `perspective_question.dart` — **SUPPRIMÉ**

### Mobile — Widgets
- `theme_with_subtopics.dart` — Chips pill-shaped (FacteurRadius.pill), padding compact, trending icon sur isPopular
- `recommendation_section.dart` — **NOUVEAU** : Header de section recommandation
- `source_recommendation_card.dart` — **NOUVEAU** : Card source avec raison de recommandation
- `premium_sources_sheet.dart` — **NOUVEAU** : Bottom sheet abonnements presse (extrait de l'ancien onboarding_screen)

### Mobile — Provider/Models
- `onboarding_provider.dart` — Suppression questions age/perspective, ajout step subtopics, nouvelle méthode `selectSubtopics()`, `continueFromSourcesPage2()`, version bump (2→3)
- `onboarding_strings.dart` — Nouvelles chaînes pour subtopics/sources
- `source_model.dart` — Ajout champ `isCurated` + `theme` sur le modèle Source

### Backend
- `packages/api/app/schemas/source.py` — Ajout champs `is_curated` et `theme` dans le schéma Source

## Zones à risque

1. **`source_recommender.dart`** — Nouveau fichier, logique de scoring non testée. Vérifie que les noms de sources hardcodés matchent bien la DB.
2. **`onboarding_provider.dart`** — Version bump (2→3) : les users avec onboarding v2 en cours seront-ils correctement migrés ? Le flow skip certaines questions (age, perspective) qui peuvent avoir des réponses sauvegardées.
3. **`subtopics_question.dart:105-121`** — Les appels `followTopic()` fire-and-forget avec `.catchError((_) => null)` silencent toutes les erreurs. Acceptable pour l'onboarding, mais les topics pourraient ne pas être sauvés si l'API échoue.
4. **`source_model.dart`** — Ajout de `isCurated` et `theme` sur le modèle. Si le backend ne les renvoie pas encore, vérifier que les valeurs par défaut (false/null) ne cassent pas l'écran sources.

## Points d'attention pour le reviewer

- **Slugs subtopics** : Tous les slugs dans `available_subtopics.dart` doivent exister dans `SLUG_TO_LABEL` de `classification_service.py:115-167`. Vérifier qu'aucun slug orphelin n'a été introduit.
- **Entités default vs backend** : Le merge dans `subtopics_question.dart:195-207` déduplique par nom (case-insensitive). Vérifier que ça ne crée pas de doublons visuels si le backend renvoie "OpenAI" et le default aussi.
- **Source recommender** : Les noms de sources hardcodés dans `source_recommender.dart` sont-ils bien les noms exacts en DB ? Un mismatch = source ignorée silencieusement.
- **Schema backend** : `source.py` ajoute `is_curated` et `theme`. Vérifier que l'API renvoie bien ces champs, sinon le front va recevoir des `null`/`false` pour toutes les sources → l'écran sources serait vide.

## Ce qui N'A PAS changé (mais pourrait sembler affecté)

- **Auth flow** — Aucun changement dans l'auth ou les JWT
- **Feed/Digest** — Non impacté, même si des thèmes/subtopics changent
- **Backend services** — Seul le schema source.py est touché (2 champs ajoutés), aucun endpoint modifié
- **Section 1 & 2 de l'onboarding** — Seules les questions supprimées (age/perspective) changent, les autres sont intactes

## Comment tester

1. **Reset onboarding** : supprimer les données Hive locales ou utiliser un nouveau user
2. **Parcourir Section 1** : vérifier que age et perspective n'apparaissent plus
3. **Section 3 — Thèmes** : sélectionner 3+ thèmes, valider → doit arriver sur SubtopicsQuestion
4. **SubtopicsQuestion** : vérifier que chaque thème a des subtopics (trending icon sur les populaires), des entités (avec "..." à la fin), et un CTA "Ajouter un sujet" (style pill, couleur primary)
5. **Ajouter un custom topic** (ex: "NBA") puis valider → ne doit PAS crasher (fix `.catchError`)
6. **Sources** : vérifier que les 3 sections apparaissent (Pour vous, Élargissez votre vision, Pépites)
7. **Sources Page 2** : vérifier l'accès au catalogue et aux CTAs
8. **Back navigation** : revenir en arrière depuis sources → subtopics → thèmes, vérifier que les sélections sont conservées
