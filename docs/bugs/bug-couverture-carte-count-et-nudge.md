# Bug — couverture médiatique : compteur carte bloqué + nudge jamais affiché

> Type : Bug (mobile-only). Deux régressions héritées de la story 32.2
> (PR #1041 « pastille N sources » + nudge « comparaison », dont le Commit 3
> avait été livré sans test, validation PO différée). Aucune migration, aucun
> changement backend, aucun changement de ranking.

## Symptômes (signalés par le PO)

1. **Le chiffre « prévisualisé » sur les cartes est bloqué à ~2**, alors qu'en
   ouvrant l'article le reader affiche 5/7/8 sources, et ce **avant même la fin
   de la requête Google News** : la donnée existe déjà, stockée au digest.
2. **Le nudge flottant** (« Voir plus de points de vue ? » / « Prendre du
   recul ? » dans le reader) **ne s'affiche jamais.**

## Bug 1 — cause racine

Deux compteurs distincts, calculés par des chemins différents :

- **Carte** → `CoverageChip` affiche `sourceCount`, issu du backend
  `source_count = len(cluster.source_domains)` du clustering en RAM au moment
  du digest (`editorial/pipeline.py`), avec un gate multi-source `>= 2` dans
  `briefing/importance_detector.py` qui pose un **plancher à 2**. C'est un
  compteur de **ranking**, jamais réactualisé.
- **Reader** → `perspective_count` (cluster + Google News, filtré biais connu),
  calculé ET persisté par `_process_perspectives`, = ce que le reader montre
  immédiatement depuis le snapshot stocké.

`perspective_count` est déjà propagé jusqu'à la carte sur les 3 surfaces
(`DigestTopic`, `EssentielArticle` portent `sourceCount` **et**
`perspectiveCount`) : la puce lisait simplement le mauvais champ.

**Décision PO** : afficher `max(sourceCount, perspectiveCount)` partout, seuil
`>= 2`. `max` ne régresse jamais sous l'affichage actuel. Ranking `source_count`
non touché.

### Fix Bug 1

- Getter `coverageCount => max(sourceCount, perspectiveCount)` sur `DigestTopic`
  (`digest_models.dart`) et `EssentielArticle` (`flux_continu_models.dart`).
- Call sites basculés sur `coverageCount` : `section_block.dart`,
  `digest_section_screen.dart`, `essentiel_hi_fi_card.dart` (2 sites : lead
  `_SourceRow` + tuile inline). `CoverageChip` inchangé (le param s'appelle
  toujours `sourceCount` mais porte le nombre de couverture, choix minimaliste).

## Bug 2 — cause racine

Le nudge exige que **toutes** ces conditions tiennent au même instant : arm
1,5 s écoulé, non `spent`, pas WebView/CTA, cible résolue, cooldown 24 h ok,
cible montée avec `topY > 0.85 * viewport`. Causes, par gravité :

- **Fenêtre trop étroite (dominante)** : le gate `offset <= 32 px` (tout en
  haut) combiné à la chaîne async (arm 1,5 s + fetch perspectives + round-trip
  cooldown) rendait le créneau quasi inatteignable : l'utilisateur scrolle
  avant.
- **Blocage dur deep-reco** : `_resolveScrollNudgeTarget` priorisait le target
  `_deepRecoKey`, **non monté** dans la branche scroll-vers-le-site (montée
  seulement en lecture in-app). Tout article avec `deepRecommendation` résolvait
  donc une cible morte et **ne retombait jamais** sur les perspectives.
- **Gate de compte** `> minCount` (donc `>= 3`) alors que la carte affiche à
  `>= 2`.
- **Cooldown brûlé sur un show transitoire** : `markShown` (24 h/device) était
  appelé au flip `true` sans confirmation de visibilité : un flash masqué
  aussitôt éteignait le nudge pour la journée (symptôme « never shows »
  persistant en test).

### Fix Bug 2

Fichier unique `content_detail_screen.dart` :

1. Seuil de couverture inclusif : `perspectivesCount >= minCount` (aligne `>= 2`).
2. Fallback deep-reco : la cible deep-reco ne prime que si sa carte est montée
   (`_deepRecoKey.currentContext != null`) ; sinon on retombe sur les
   perspectives.
3. Suppression du gate `offset <= _kScrollNudgeTopTolerance` (et de la constante,
   devenue morte). La visibilité repose sur le seul check below-fold
   `topY > 0.85 * viewport`, qui masque naturellement la pastille quand la
   section approche. `spent` + auto-hide 6 s + cooldown 24 h garantissent 1
   apparition/article. **Décision PO : fiabilité > top-only.**
4. `markShown` déféré derrière un timer de confirmation
   (`_kScrollNudgeConfirmDelay = 400 ms`) : le cooldown n'est posé que si la
   pastille est **toujours** visible à l'échéance ; le timer est annulé partout
   où elle se masque (flip `!shouldShow`, auto-hide, reset, tap). Le tap pose le
   cooldown immédiatement (engagement franc).

### Refactor de testabilité

La logique pure est extraite en deux fonctions top-level testables sans pomper
l'écran : `resolveScrollNudgeTargetKind(...)` (sélection de cible) et
`computeScrollNudgeVisibility(ScrollNudgeInputs)` (décision de visibilité). La
méthode `_computeShouldShowScrollNudge` devient un adaptateur qui lit l'état et
délègue (effets de bord assumés : mémorisation de la cible + amorçage du
cooldown).

## Tests

- `test/features/detail/scroll_nudge_visibility_test.dart` : happy path +
  garde-fous (count exact 2, near-fold, spent/webview/cta, cooldown
  pending/false, deep-reco monté/non-monté → fallback perspectives).
- `test/features/flux_continu/widgets/essentiel_hi_fi_card_test.dart` :
  `perspectiveCount > sourceCount` fait afficher le plus grand ; couverture
  réelle `< 2` cache la puce. Helper `_article` : `perspectiveCount` devient
  paramètre (défaut 0) pour rendre les cas déterministes.
- `test/features/flux_continu/models/flux_continu_models_test.dart` : getter
  `coverageCount` sur `DigestTopic` et `EssentielArticle`.

> Note : le plan prévoyait aussi un widget test pumpant `ContentDetailScreen`.
> L'écran est fortement couplé (réseau, WebView, nombreux providers) ; le
> refactor en fonctions pures couvre déterministe­ment les deux régressions de
> fond (fenêtre + fallback deep-reco), sans la fragilité d'un pump complet. La
> validation de bout en bout passe par Playwright (voir plan).

## Garde-fous

- Bug 1 (getters + call sites) et Bug 2 (edits + refactor) sont indépendants et
  révocables.
- Pas d'em-dash dans la copy user-facing.
- Ranking (`source_count`, `is_multi`, `compute_coverage_score`) non touché.
