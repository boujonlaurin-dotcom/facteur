# Epic 12 : Alignement Taxonomie v2

**Version:** 1.0
**Date:** 4 mars 2026
**Auteur:** BMad Architect + PO
**Statut:** Spécification — En attente d'implémentation

---

## Résumé Exécutif

Le pipeline de classification Mistral a été refactoré (PR #152/#153) avec une taxonomie enrichie de **51 topics** groupés en **9 thèmes**, plus un booléen `is_serene`. Cette classification est objectivement meilleure que l'ancienne.

Cependant, le reste de la plateforme (onboarding, UI, recommandations) utilise encore des taxonomies **désalignées** : slugs inventés dans l'onboarding, thèmes manquants, groupements UI incohérents. Cet epic aligne l'ensemble de la plateforme sur la source de vérité ML.

### Valeur Utilisateur

> "Mes préférences choisies à l'onboarding correspondent exactement aux articles que je reçois. Pas de décalage entre ce que je demande et ce que l'algorithme comprend."

### Décision Architecturale

**Convergence totale** : les 9 thèmes backend (`tech`, `society`, `environment`, `economy`, `politics`, `culture`, `science`, `international`, `sport`) deviennent la source de vérité unique partout — onboarding, UI, scoring.

---

## Problème

### État actuel : 3 systèmes désynchronisés

| Couche | Taxonomie | Problème |
|--------|-----------|----------|
| **ML Pipeline** (backend) | 51 topics, 9 thèmes | Source de vérité, fonctionne bien |
| **Onboarding** (mobile) | 8 thèmes, ~20 subtopics inventés | Slugs ne matchent pas les topics ML |
| **UI groupements** (mobile) | 8 macro-thèmes (Lifestyle, Business, etc.) | Différents des 9 thèmes backend |

### Conséquence directe

Les préférences utilisateur saisies à l'onboarding (`crypto`, `social-justice`, `housing`...) ne correspondent à **aucun** des 51 topic slugs ML. Le scoring/recommandation ne peut pas exploiter ces préférences correctement.

### Écarts détaillés

**A. Onboarding subtopics vs VALID_TOPIC_SLUGS (51)**

| Subtopic onboarding | Topic ML équivalent | Statut |
|---------------------|---------------------|--------|
| `crypto` | `finance` | MISMATCH |
| `social-justice` | `justice` | MISMATCH |
| `housing` | `realestate` | MISMATCH |
| `energy-transition` | `energy` | MISMATCH |
| `macro` | `economy` | MISMATCH |
| `elections` | `politics` | INEXISTANT dans ML |
| `institutions` | `politics` | INEXISTANT dans ML |
| `media-critics` | `media` | MISMATCH |
| `fundamental-research` | `science` | INEXISTANT dans ML |
| `applied-science` | `science` | INEXISTANT dans ML |

**B. Thèmes : Backend 9 vs Frontend 8**
- Backend `VALID_THEMES` : 9 thèmes incluant `sport`
- Frontend `AvailableThemes.all` : 8 thèmes, manque `sport`

**C. Macro-thèmes UI ≠ thèmes backend**
- Frontend `topic_labels.dart` utilise 8 groupes (Tech & Science, Societe, Lifestyle, Business, etc.)
- Backend utilise 9 thèmes (tech, society, culture, economy, sport, etc.)
- Ex: "Lifestyle" (travel, gastronomy, sport, wellness, family, relationships) n'existe pas en backend — ces topics sont mappés vers culture, society, sport

**D. ThemeToSourcesMapping avec slugs non-standard**
- `middle-east` vs `middleeast`, `physics`/`biology` (inexistants), `arts` vs `art`, etc.

---

## Stories

| # | Story | Priorité | Fichiers clés |
|---|-------|----------|---------------|
| 12.1 | Aligner subtopics onboarding → topic slugs ML | P0 | `available_subtopics.dart`, `users.py` |
| 12.2 | Ajouter thème "Sport" à l'onboarding | P1 | `onboarding_provider.dart`, `theme_to_sources_mapping.dart` |
| 12.3 | Converger macro-thèmes UI → 9 thèmes backend | P1 | `topic_labels.dart` |
| 12.4 | Aligner ThemeToSourcesMapping slugs | P1 | `theme_to_sources_mapping.dart` |
| 12.5 | Migrer données utilisateur existantes | P0 | Migration Alembic |
| 12.6 | Reclassifier articles 48h | P2 | Endpoint `/admin/reclassify` |

### Ordre d'exécution recommandé

1. **12.1 + 12.2 + 12.3 + 12.4** (frontend, parallélisable)
2. **12.5** (migration données, après que le code soit déployé)
3. **12.6** (reclassification, après migration)

---

## Contraintes

- **Python 3.12.x** uniquement (guardrail #1)
- `list[]` natif (pas `List` de typing)
- Reclassification limitée à **48h** (coûts Mistral)
- Pertes de préférences utilisateur minimisées (mapping explicite ancien → nouveau slug)
- Quelques pertes acceptables dans le contexte de la refonte du système de recommandations

---

## Fichiers critiques

| Fichier | Rôle |
|---------|------|
| `packages/api/app/services/ml/classification_service.py` | Source de vérité : 51 topics, SLUG_TO_LABEL |
| `packages/api/app/services/ml/topic_theme_mapper.py` | Source de vérité : 9 thèmes, TOPIC_TO_THEME |
| `apps/mobile/lib/features/onboarding/data/available_subtopics.dart` | Subtopics onboarding (à aligner) |
| `apps/mobile/lib/features/onboarding/providers/onboarding_provider.dart` | Thèmes onboarding (à compléter) |
| `apps/mobile/lib/features/onboarding/data/theme_to_sources_mapping.dart` | Sources recommandées (slugs à corriger) |
| `apps/mobile/lib/config/topic_labels.dart` | Labels + macro-thèmes UI (à converger) |
| `packages/api/app/routers/users.py` | Onboarding API |
| `packages/api/app/models/user_personalization.py` | Muted topics/themes |

---

## Métriques de succès

| Métrique | Cible |
|----------|-------|
| Subtopics onboarding ⊂ VALID_TOPIC_SLUGS | 100% |
| Thèmes onboarding = VALID_THEMES | 9/9 |
| Macro-thèmes UI = thèmes backend | 9/9 |
| Préférences utilisateur migrées | >95% |
| Articles 48h reclassifiés | 100% |
