# feat(onboarding) : reco médias « interest-aware » + polish copy

## Problème

Pendant l'onboarding, les **premiers** médias proposés (deck à swiper +
carrousel « Tes médias, sur mesure ») ne collaient pas aux intérêts déclarés :
un utilisateur **sans Sport** voyait l'Équipe et Ouest-France (≈ 40 % de sport
publié) en tête.

## Causes racines

Le ranking est **100 % côté client** (`source_recommender.dart`) :

1. **Scoring additif sans pénalité** : `reliability high` (+1) + volume ≥ 90/30 j
   (+2) ⇒ une généraliste fiable et active atteint **3 sans aucun match
   thématique**, à égalité avec un vrai match de thème.
2. **Le deck du swipe n'utilise pas `_scoreSource`** : `buildSpanningSet`
   complétait ses pôles avec le catalogue trié sur `followerCount` ⇒ les grosses
   audiences menaient les thèmes peu couverts.
3. **`sources.coverage_themes` (couverture réellement publiée) n'était pas
   sérialisée** : le client ne pouvait pas voir la dilution.
4. **Découvert en implémentant : `_build_source_response` ne sérialisait ni
   `secondary_themes`, ni `granular_topics`, ni `source_tier`** (jamais, depuis
   la création du helper). Le catalogue mobile ne voyait donc que `theme` :
   match par sujet, badges « Spécialisé en X » et pépites (tier `deep`) étaient
   **débranchés**. En base : 61/124 curées actives ont des `granular_topics`,
   29 sont `deep`, 17 ont des `secondary_themes`, 74 ont des `coverage_themes`.

Les points 3 et 4 vont ensemble : sans thèmes secondaires ni sujets granulaires,
une pénalité anti-hors-intérêt aurait dégradé la reco au lieu de l'améliorer.

## Ce que fait la PR

**Backend (additif, aucune migration).** `SourceResponse.coverage_themes` +
sérialisation de `coverage_themes` / `secondary_themes` / `granular_topics` /
`source_tier` dans `_build_source_response`. Les colonnes sont déjà chargées sur
l'objet `Source` ⇒ **aucune requête supplémentaire, aucun N+1**.

Deux convertisseurs `Source → SourceResponse` coexistent : celui du service
(`GET /sources`) et `_source_to_response` dans `routers/sources.py` (liste curée,
suggestions par thème, fiche source). `coverage_themes` est sérialisée **dans les
deux**, sinon la même source aurait une forme différente selon l'endpoint et le
client conclurait « couverture inconnue » là où la donnée existe — exactement la
classe de bug corrigée ici. Un test verrouille la parité.

**Mobile — scoring.** Nouveau signal partagé `_InterestFit` :
`declared` > `covered` (la source publie sur un thème choisi) > `unknown` >
`offInterest`.
- **Règle A (anti-pad)** : bonus fiabilité/volume réservés aux sources
  pertinentes ⇒ une source hors-intérêt retombe à 0, sous toute source matchée ;
  `-1` de plus si sa couverture connue est disjointe.
- **Règle B (anti-dilution)** : `-1` par thème publié hors des intérêts, plafonné
  à `-2` ⇒ Ouest-France passe **sous** une source focalisée sans être écartée.
- **Garde-fous** : rien ne s'arme si l'utilisateur a « Passé » les thèmes ; une
  source **likée au swipe** n'est jamais pénalisée (le révélé prime) ; une
  couverture **inconnue** n'est jamais pénalisante.

**Mobile — deck du swipe.** `buildSpanningSet` trie par adéquation avant
`followerCount`, exclut les sources hors-intérêt des pôles et ne les garde qu'en
**filler de dernier recours** (fin de deck). Le fallback « thèmes pauvres » reste
garanti (deck jamais vide).

**Polish copy/UI.** Doubles majuscules corrigées (« Lire notre manifeste »,
« Notre manifeste », « Le projet », « Notre mission », « Notre approche ») ;
lien manifeste en emphase légère (couleur d'accent + demi-gras, dépliage inline
inchangé) ; « diversifier tes médias » → « diversifier tes **sources** » sur
l'écran concentration ; nouveau `SourceSearchLoader` (« Recherche de tes
médias » / « Basé sur tes intérêts ») à la place des 4 spinners nus.
Le loader prend `title`/`subtitle` : l'overlay de calibration de fin de swipe
l'utilise avec sa propre copy, ce qui supprime ~25 lignes de layout dupliqué et
le dernier `CircularProgressIndicator` nu de ce parcours.

## Tests

- **Backend** : `pytest -q` complet ⇒ **3018 passed**, 18 skipped, 2 xfailed.
  Nouveau test de sérialisation des signaux de reco (`None` conservé).
- **Mobile** : `test/features/onboarding` + `test/features/sources` ⇒ **262
  passed**. Suite complète : 2043 passed / 26 échecs **pré-existants**, tous hors
  des zones touchées (custom_topics, digest, feed, settings, widget_test).
- `flutter analyze` : aucune erreur ni warning.
- Alembic : **1 seul head**, inchangé (aucune migration).
- Tous les tests historiques du recommander sont conservés **sans modification
  d'attente**, dont le fallback « thèmes vides → fiabilité ».

## Points d'attention pour la review

- **Deux sources de vérité pour « est-ce un match déclaratif »** : `_interestFit`
  re-dérive le prédicat déjà calculé dans les boucles de `_scoreSource`. Unifier
  changerait le scoring, donc laissé en l'état — mais une évolution des règles de
  match devra être répercutée des deux côtés sous peine de désynchroniser la
  pénalité du score qu'elle corrige.
- **La règle anti-généraliste est la première règle éditoriale à vivre
  uniquement côté client** : pas d'équivalent `SCORING_OVERRIDES` / harnais de
  sensibilité, donc pas de tuning, d'A/B ni de rollback sans release.

- **Effet de bord voulu du point 4** : les badges « Spécialisé en X » et la
  section « Pépites » (tier `deep`) vont enfin s'activer dans l'onboarding.
  À valider visuellement (`/validate-feature`, handoff dans
  `.context/qa-handoff.md`).
- Le payload de `GET /sources` grossit de 3 petits tableaux par source curée.
- Story : `docs/stories/core/onboarding.reco-interest-aware.md`.
