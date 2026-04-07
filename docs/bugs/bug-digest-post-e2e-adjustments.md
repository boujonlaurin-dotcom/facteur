# Bug + Evolutions — Post-E2E Digest Adjustments (story 10.29)

**Date** : 2026-04-06
**Branche** : `boujonlaurin-dotcom/fix-digest-post-e2e`
**Branche parente** : `boujonlaurin-dotcom/fix-digest-bugs` (story 10.29 complète)
**PR cible** : `--base main`

## Contexte

Corrections et évolutions UI identifiées lors du test E2E du digest éditorial (story 10.29). Mix de bugs (doublons, carrousel cassé) et d'ajustements UI (previews compactes, cartes dépliées).

---

## Plan Technique

### Phase 1 — Bugs structurels (A1, A2, A3)

**A1. Carrousel non utilisé en état déplié**
- Fichier : `topic_section.dart` → `_buildExpandedEditorial()`
- Problème : actu articles empilés verticalement au lieu du carrousel
- Fix : Le code utilise déjà `_buildPageView(actuArticles)` + `_buildSingleArticle()` dans `_buildExpandedEditorial()`. Le carrousel PageView EXISTE déjà pour isActuMulti. À vérifier visuellement — le code semble correct. Si le problème persiste c'est que isActuMulti est toujours false (un seul article actu par topic). À investiguer les données.

**A2. Badge "Actu du jour" en doublon**
- Fichier : `topic_section.dart`
- Problème : `EditorialBadge.chip('actu')` affiché dans le badges row de `_buildExpandedEditorial()` (l.551-552) ET dans `_buildSingleArticle()`/`_buildPageView()` (via `article.badge`)
- Fix : En mode expanded, supprimer le badges row (Wrap l.540-556) qui duplique les infos. Les badges article-level restent dans les FeedCards.

**A3. Source + temporalité en doublon**
- Fichier : `topic_section.dart`
- Problème : `_buildCollapseFooter()` affiche source/time, ET le FeedCard a son propre footer avec source/time
- Fix : Supprimer `_buildCollapseFooter()` en mode expanded et intégrer le bouton collapse dans un header en haut (voir C1)

### Phase 2 — Preview compacte (B1, B2, B4)

**B1. Supprimer l'intro tronquée**
- Fichier : `topic_section.dart` → `_buildCompactWithImage()` et `_buildCompactWithoutImage()`
- Fix : Retirer le `Text(description, maxLines: 1)` (l.360-371 et l.411-421)

**B2. Titre maxLines 2 → 4**
- Fichier : `topic_section.dart` → compact builders
- Fix : `maxLines: 2` → `maxLines: 4` (l.348 et l.400)

**B4. Retirer badges de la preview compacte**
- Fichier : `topic_section.dart` → `_buildCompactBadgesRow()`
- Fix : Supprimer l'appel à `_buildCompactBadgesRow()` dans les compact builders. Conserver uniquement le traitement "À la Une" (A0).

### Phase 3 — Toggle container (C1)

**C1. Bouton fermeture en haut**
- Fichier : `topic_section.dart`
- Fix : Remplacer `_buildCollapseFooter()` par un header en haut de `_buildExpandedEditorial()`. Container avec border + borderRadius 12, header Row avec titre tronqué + icône ▲ fermeture. Option B du handoff.

### Phase 4 — Blocs étendus (C2, C3a, C3b, C3c)

**C2. Carte "De quoi on parle ?"**
- Fichier : `topic_section.dart` → `_buildExpandedEditorial()`
- Fix : Encapsuler `introText` dans un Container styled (fond `colors.surface`, padding 12, borderRadius 12) avec header "De quoi on parle ?" en bold 13px. Positionner comme premier élément après le header fermeture.

**C3a. Header analyse renommé + badge sources**
- Fichier : `divergence_analysis_block.dart`
- Fix : Remplacer "🔍 Analyse des angles médiatiques" par "L'analyse Facteur". Ajouter `SourceCoverageBadge` dans le header (Row + Spacer).

**C3b. Markdown dans l'analyse**
- Fichier : `divergence_analysis_block.dart`
- Fix : Remplacer `Text(divergenceAnalysis)` par `MarkdownText(text: divergenceAnalysis)` (widget existant dans le projet).

**C3c. CTA "Comparer les sources" proéminent en haut**
- Fichier : `divergence_analysis_block.dart`
- Fix : Déplacer le CTA juste sous le header, le transformer en `OutlinedButton` ou `FilledButton.tonal`.

### Phase 5 — Logos + À la Une (B3, A0)

**A0. Traitement visuel "À la Une"**
- Fichier : `topic_section.dart` (compact card)
- Fix : Pour le topic avec `isUne == true`, ajouter un badge "À la Une" proéminent (accent border left sur la compact card) + conserver le badge chip.

**B3. Logos sources multi**
- Approche : Option 2 (frontend, extraire logos depuis `topic.articles[*].source.logoUrl`)
- Fichier : `topic_section.dart` → footer compact
- Fix : Remplacer le texte source name par une Row de logos circulaires (réutiliser pattern SourceLogos de `keyword_overflow_chip.dart`).

### Phase 6 — Deep matcher (A4) — Itération séparée

**A4. Qualité deep match**
- Fichier : `deep_matcher.py`
- Fix : Augmenter le seuil fallback de 0.5× threshold → 0.7× threshold. Ajouter un seuil minimum absolu (0.08). Si aucun bon match, retourner None plutôt que forcer.

---

## Fichiers impactés

| Fichier | Tâches |
|---------|--------|
| `topic_section.dart` | A1, A2, A3, B1, B2, B3, B4, C1, C2, A0 |
| `divergence_analysis_block.dart` | C3a, C3b, C3c |
| `deep_matcher.py` | A4 |

## Critères d'acceptation

- [ ] A0-A4 : les 5 bugs sont corrigés
- [ ] B1-B4 : les 4 évolutions preview implémentées
- [ ] C1-C3 : les 3 évolutions cartes dépliées implémentées
- [ ] Aucune régression formats `topics_v1` et `flat_v1`
- [ ] `flutter analyze` : 0 erreurs
- [ ] `pytest tests/ -x -q` : tous les tests passent
