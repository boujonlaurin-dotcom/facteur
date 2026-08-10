# Story — Reco médias onboarding « interest-aware » + polish copy

**Type** : Feature
**Statut** : CODE terminé, VERIFY en cours
**Branche** : `boujonlaurin-dotcom/onboarding-source-reco-interests`

## Problème / objectif

Sur la page d'onboarding « recommandations de médias » (deck à swiper +
carrousel « Tes médias, sur mesure »), les **premières** sources proposées ne
collent pas aux intérêts déclarés. Cas signalé : un utilisateur **sans « Sport »**
voit l'Équipe et Ouest-France (≈ 40 % de sport dans sa production réelle) en tête.

### Causes racines (confirmées)

Le ranking est **100 % côté client**
(`apps/mobile/lib/features/onboarding/data/source_recommender.dart`).

1. **Scoring purement additif, sans pénalité hors-intérêt** : `reliability == 'high'`
   → +1 et volume ≥ 90/30 j → +2 ⇒ une généraliste fiable et active atteint **3
   sans aucun match thématique**, à égalité avec un vrai match de thème (+3).
2. **Le deck du swipe n'utilise pas `_scoreSource`** : `buildSpanningSet` complète
   le pool avec le catalogue trié sur `followerCount` ⇒ les grosses audiences
   remontent sur les pôles peu couverts.
3. **La couverture réelle n'était pas exposée** : la colonne `sources.coverage_themes`
   (top thèmes réellement publiés sur 90 j, recalculée par
   `recompute_source_coverage_themes`) n'était pas sérialisée dans `SourceResponse`.
4. **Découverte pendant l'implémentation — le catalogue mobile ne voyait que
   `theme`.** `_build_source_response` (`source_service.py`) ne sérialisait
   **ni** `secondary_themes`, **ni** `granular_topics`, **ni** `source_tier`
   (jamais, depuis la création du helper : `git log -S` ne trouve aucune
   occurrence). Côté client, `secondaryThemes`/`granularTopics` étaient donc
   toujours vides et `sourceTier` toujours `mainstream` : match par sujet, badges
   « Spécialisé en X », pépites (tier `deep`) et pôle « fond » du swipe étaient
   **débranchés**. En base : 61/124 curées actives ont des `granular_topics`,
   29 sont `deep`, 17 ont des `secondary_themes`, 74 ont des `coverage_themes`.

Sans le point 4, la pénalité anti-hors-intérêt aurait été **nuisible** : faute de
thèmes secondaires et de sujets granulaires, des sources légitimes auraient été
classées « hors-intérêt ». Les deux correctifs vont ensemble.

### Décisions PO

1. Approche **data-driven** : exposer `coverage_themes` et pénaliser le
   hors-intérêt dans le scoring **et** dans le deck du swipe.
2. Manifeste : **emphase légère** (lien inline conservé, plus visible).

## Implémentation

### Partie A — Reco « interest-aware »

**Backend (additif, aucune migration).**
- `packages/api/app/schemas/source.py` — `SourceResponse.coverage_themes:
  list[str] | None = None` (calqué sur `articles_30d`).
- `packages/api/app/services/source_service.py` — `_build_source_response`
  sérialise `coverage_themes`, `secondary_themes`, `granular_topics` et
  `source_tier`. Colonnes déjà chargées sur l'objet `Source` ⇒ **aucune requête
  supplémentaire, aucun N+1**.
- `packages/api/app/models/source.py` — commentaire de `coverage_themes` mis à
  jour (elle sert désormais aussi de signal de **dilution**, en malus seulement).

**Mobile — modèle.**
- `features/sources/models/source_model.dart` — `coverageThemes` (`List<String>`,
  défaut `[]`), miroir exact de `secondaryThemes` (champ, constructeur,
  `copyWith`, `fromJson`).

**Mobile — scoring (`source_recommender.dart`).**
- Nouveau signal partagé `_InterestFit` (enum ordonné) + `_interestFit(source,
  themes, subtopics)` :
  `declared` (match thème/thème secondaire/sujet) > `covered` (pas de match mais
  `coverageThemes` recoupe les intérêts) > `unknown` (aucun signal connu) >
  `offInterest` (couverture connue et entièrement hors des intérêts).
- **Règle A (anti-pad générique)** : les bonus `reliability +1` et `_volumeBonus
  (+2/+1)` ne sont accordés qu'aux sources `declared`/`covered`. Une source
  hors-intérêt retombe donc à 0, **sous toute source matchée** (≥ 1).
  Malus supplémentaire `-1` si la couverture est connue et disjointe : elle passe
  aussi sous les sources à couverture *inconnue*.
- **Règle B (anti-dilution)** : `-1` par thème réellement publié hors des
  intérêts, **plafonné à -2** ⇒ Ouest-France passe **sous** une source focalisée
  sans être écartée.
- **Garde-fous** : la pénalité ne s'arme que si `themes.isNotEmpty` (bouton
  « Passer » ⇒ comportement historique intact) et **jamais** sur une source
  aimée au swipe (`swipeLiked`) — le signal *révélé* prime toujours. Les votes de
  pôle (±4) restent capables de faire remonter une source.
- Couverture inconnue (`coverageThemes` vide) = **jamais** pénalisante.

**Mobile — deck du swipe (`buildSpanningSet`).**
- Le backfill trie désormais par adéquation (`_InterestFit`) **avant**
  `followerCount`.
- Les pickers par pôle **excluent** les sources `offInterest` quand des thèmes
  sont déclarés ; elles ne reviennent qu'en **filler de dernier recours**, en fin
  de deck (donc en fin de groupe pour `buildSpanningGroups`).
- Le fallback « thèmes pauvres » reste garanti : un deck non vide même quand tout
  le catalogue est hors-intérêt.

### Partie B — Polish copy/UI onboarding

- `onboarding_strings.dart` — doubles majuscules corrigées : « Lire notre
  manifeste », « Notre manifeste », « Le projet », « Notre mission »,
  « Notre approche ».
- `screens/questions/intro_screen.dart` — emphase légère du lien manifeste :
  couleur d'accent (`colors.primary`) + demi-gras, soulignement, chevron et
  dépliage inline conservés (design-system-first, aucun changement de
  comportement).
- Écran « concentration des médias » — « diversifier tes médias » →
  « diversifier tes **sources** » (« médias » passe de 3 à 2 occurrences) ;
  variante non splittée alignée pour éviter le drift.
- Loader de recherche : `sourceSearchLoaderTitle` = « Recherche de tes médias »,
  `sourceSearchLoaderSubtitle` = « Basé sur tes intérêts » (tutoiement, cohérent
  avec le reste de l'onboarding). Nouveau widget
  `features/onboarding/widgets/source_search_loader.dart` (réutilise
  `MinimalLoader`), câblé sur les 4 spinners nus de `sources_question.dart` et
  `swipe_disambiguator_question.dart`. L'overlay « On affine tes médias… » de fin
  de tri garde sa propre copy.

## Fichiers modifiés

| Fichier | Nature |
|---|---|
| `packages/api/app/schemas/source.py` | `coverage_themes` sur `SourceResponse` |
| `packages/api/app/services/source_service.py` | sérialisation des 4 signaux de reco |
| `packages/api/app/models/source.py` | commentaire `coverage_themes` |
| `packages/api/tests/test_source_catalog_volume.py` | test de sérialisation |
| `apps/mobile/lib/features/sources/models/source_model.dart` | `coverageThemes` |
| `apps/mobile/lib/features/onboarding/data/source_recommender.dart` | `_InterestFit`, règles A/B, deck |
| `apps/mobile/test/.../source_recommender_test.dart` | 6 tests |
| `apps/mobile/lib/features/onboarding/onboarding_strings.dart` | copy |
| `apps/mobile/lib/features/onboarding/screens/questions/intro_screen.dart` | emphase manifeste |
| `apps/mobile/lib/features/onboarding/widgets/source_search_loader.dart` | NOUVEAU |
| `apps/mobile/lib/features/onboarding/screens/questions/sources_question.dart` | loaders |
| `apps/mobile/lib/features/onboarding/screens/questions/swipe_disambiguator_question.dart` | loaders |

## Tests

**Backend** — `tests/test_source_catalog_volume.py::test_catalog_serializes_relevance_signals` :
`coverage_themes` / `secondary_themes` / `granular_topics` / `source_tier`
sérialisés tels quels, `None` conservé pour une source sans signal dérivé.

**Mobile** — `source_recommender_test.dart`, tous les tests historiques conservés
**sans modification d'attente** (dont le fallback « thèmes vides → fiabilité »),
plus :
- source hors-intérêt à grosse audience (type l'Équipe) → absente des suggestions ;
- généraliste diluée (type Ouest-France) → classée **sous** une source focalisée ;
- like au swipe → rescape une source hors-intérêt ;
- couverture recoupant les intérêts sans match déclaratif → reste pertinente ;
- `buildSpanningSet` : une grosse audience hors-intérêt **ferme** le deck ;
- `buildSpanningSet` : couverture *inconnue* préférée à un hors-intérêt avéré.

## Risques / points d'attention

- **Effet de bord voulu du point 4** : l'onboarding voit enfin les sujets
  granulaires, les thèmes secondaires et le tier `deep`. Les sections
  « Spécialisé en X » et « Pépites » vont s'activer pour de bon (elles renvoyaient
  systématiquement 0 candidat). À valider visuellement (`/validate-feature`).
- `coverage_themes` est `NULL` pour 50/124 curées (volume trop faible) → traité
  comme « inconnu », jamais pénalisant.
- `_minMatched=10` et le tri `_byVolumeProxy` (`sources_question.dart`)
  réinjectent des sources moins pertinentes **en fin** de liste : acceptable tant
  qu'elles restent après les matchées.
- Aucune migration Alembic ; 1 seul head, inchangé.
