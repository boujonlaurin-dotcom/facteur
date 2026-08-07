# feat(tournée) : ordre des blocs par le score top-3 (lot reco, PR-4)

Base `main`. **Mobile uniquement, aucune migration Alembic.** Lot :
`docs/maintenance/maintenance-reco-optimisation-lot2.md` (§ PR-4).

## Quoi

Les blocs de la Tournée (thèmes, sources, veille, « Choisie pour vous ») ne sont
plus simplement **dépriorisés** quand ils sont maigres : ils sont **triés par la
somme des 3 meilleurs `score_total` de leurs articles** — score que le backend
renvoie déjà dans `recommendation_reason`.

Les slots manquants comptant 0, un bloc à 1 article coule **structurellement**
(≈ 1 × s contre 3 × s) sans avoir besoin d'être un cas spécial. C'est ce qui
répond à la plainte PO « des blocs à 1 article remontent en tête de Tournée » :
la règle historique (`thinKeys` + `demote`) ne *classait* pas, elle se contentait
de reléguer les blocs à ≤ 1 article sous les autres.

**La PR boucle aussi PR-1** : le champ `block_score` de l'event
`article_impression` était câblé de bout en bout (`SectionBlock` →
`ArticleImpressionTracker` → `analytics_service`) mais **personne ne le
renseignait** — il valait `null` en prod. C'est le champ qui relie « ordre des
blocs » et « CTR mesuré », donc celui dont PR-6 (`evaluate_tournee_ctr.py`) a
besoin.

## Pourquoi

Sans lui, PR-6 ne peut pas mesurer si le classement tape juste : on saurait
qu'un bloc a été vu et cliqué, sans savoir quel score l'avait mis là.

## Décisions structurantes

**L'ordre est gelé pour la journée tournée** (frontière 07h30 Paris, clé
`tournee_score_order_v1` stockant `{"day", "keys"}`). `_fanOutSectionsProgressive`
émet après chaque tâche (~10-15 recompositions) : trier à chaque emit ferait
**sauter les blocs sous les yeux**. L'ordre est calculé une seule fois, à la
complétion du fan-out, puis rejoué tel quel par tous les composes du jour (cache
in-day, pull-to-refresh, refetch partiels, load-more). Clé unique day-stampée ⇒
auto-invalidante, rien à ajouter à `purgeOldPrefsKeys`.

**Réinjection à position absolue via `mergeVisibleReorder`**, pas `applyOrder` :
ce dernier pousse les clés inconnues en **fin**, ce qui ferait couler Actus /
Bonnes Nouvelles (jamais scorées) jusqu'à les faire tomber hors du cap 13.

**Le tri s'applique aussi aux comptes personnalisés** (décision PO) : l'ordre
manuel reste la base d'entrée et **départage à score égal** (le tri est stable),
mais il ne fait plus autorité au-delà. Risque assumé : un bloc glissé en tête
peut descendre le lendemain — jamais dans la même session, l'ordre étant figé.

**Portée plus large que la classification maigre/riche** : toute section résolue
portant au moins un article scoré entre au classement, veille comprise. Une
section dont *aucun* article n'a de `recommendation_reason` (éditorial, coquille
de boot) n'entre pas dans la map et **garde sa place** plutôt que de couler à 0.

**Kill-switch `kTourneeScoreSortEnabled`** : à `false`, aucun ordre trié ni
persisté, et la dépriorisation binaire reprend à l'identique. Il désarme le
**tri**, pas la **mesure** — `block_score` reste renseigné, pour ne pas aveugler
l'instrument qui sert à juger le tri. `kThinDemotionRichThreshold` et `demote`
partiront au cycle suivant : la CI ne lance pas `flutter test`, on ne retire pas
les deux filets d'un coup.

## Comment ça a été vérifié

- [x] **`flutter test`** — **2057 passed**, 26 échecs **strictement identiques à
      la baseline `main`** (`origin/main` rejoué dans un worktree propre et
      comparé test par test : `IDENTICAL: True`, aucun échec neuf, aucun réparé).
      Aucun des 26 n'est dans le périmètre touché.
- [x] **Tests neufs** — 33 cas : `blockScore` (top-3 des *meilleurs* et non des
      premiers affichés, slots manquants à 0, clamp des scores négatifs),
      `rankKeysByBlockScore` (tri stable, ex æquo départagés par l'ordre
      d'affichage), `applyScoreOrder` (clés éditoriales de tête et de queue qui
      ne coulent pas, clé obsolète ignorée), et côté provider : gel à la journée,
      persistance sous `tournee_score_order_v1`, ordre daté d'hier ignoré et
      recalculé, ordre rejoué à l'identique dans la journée, `blockScores`
      exposés à la mesure.
- [x] **`flutter analyze`** — **526 issues, exactement la baseline**, zéro
      `error`, zéro `warning` neuf, rien dans les fichiers touchés.
- [x] **`/simplify`** — 4 relectures parallèles (reuse / simplification /
      efficiency / altitude), findings appliqués puis re-run complet de VERIFY.
      Détail dans la section ci-dessous.
- [ ] **Playwright / `/validate-feature`** — **non exécuté** : pas de build web ni
      d'API locale dans ce workspace, et les scénarios exigent un compte connecté
      avec ≥ 5 blocs favoris portant des articles **scorés** — donnée que je ne
      peux pas fabriquer localement. `.context/qa-handoff.md` est à jour et
      décrit les 6 scénarios ; **à lancer avant merge**.

### Passe SIMPLIFY — ce qui a été corrigé

1. **Le kill-switch aveuglait sa propre mesure.** `blockScores` n'était rempli
   que si `kTourneeScoreSortEnabled` — donc couper le tri en prod aurait fait
   retomber `block_score` à `null`, soit exactement le trou que PR-4 bouche. Le
   calcul est désormais **hors** du flag ; seule l'*application* de l'ordre est
   gatée.
2. **Une passe ordre+dédup complète était jouée deux fois.**
   `_freezeScoreOrderIfNeeded` rappelait `_classifyFavoriteSections` (donc
   `_orderedTourneeKeys` + `_filterSections` + `_dedupeSectionsInOrder` sur
   toutes les sections) juste avant un `emit()` dont le `_compose` refaisait la
   même passe sur un état identique. Le gel est maintenant consommé **dans**
   `_compose`, à partir des scores déjà en main, via un drapeau one-shot armé à
   la complétion du fan-out — une passe au lieu de deux, et l'ordre trié
   s'applique dans la recomposition même.
3. **`rankKeysByBlockScore`** prenait une liste de clés que son unique appelant
   dérivait de la map elle-même : paramètre dégénéré, supprimé.
4. **`applyScoreOrder`** portait trois gardes déjà assurées par
   `mergeVisibleReorder` — la fonction fait trois lignes.
5. **Doc corrigée** : `block_score` est recalculé à chaque recomposition alors
   que l'ordre est gelé ; le doc affirmait que c'était « celui-là même qui a fixé
   son rang ». Les deux peuvent diverger dans la journée (load-more, refetch) —
   l'analyse doit joindre sur `(day_key, section)`, pas sur la valeur seule.

Non appliqué, volontairement : la duplication du harnais de test avec
`flux_continu_sources_test.dart` (convention pré-existante à 6 fichiers du même
répertoire, hors périmètre) et le passage de la clé de prefs au couple
`setStringList` + `purgeDatedPrefsKeys` (le blob JSON day-stampé est
auto-invalidant, deux relecteurs sur quatre le préféraient tel quel).

## Zones à risque

- **Ordre de la Tournée = surface la plus visible de l'app.** Le filet est le
  gel journalier : même si le classement est mauvais, il ne *bouge* jamais en
  cours de session. Rollback = `kTourneeScoreSortEnabled = false`, qui restaure
  la dépriorisation binaire à l'identique sans toucher à la mesure.
- **Comptes personnalisés.** Un ordre manuel n'est plus souverain : il devient la
  base d'entrée et le départage des ex æquo. C'est une décision PO explicite, pas
  un effet de bord — mais c'est le changement le plus susceptible d'être
  remonté par un utilisateur qui a rangé sa Tournée à la main.
- **`SharedPreferences`.** Une seule clé neuve (`tournee_score_order_v1`), aucune
  clé existante renommée ni purgée différemment ⇒ aucune perte d'état à la MAJ.
- **Aucune migration Alembic**, aucun fichier backend touché.

## Ce que cette PR ne fait pas

- Ne touche **aucun poids de scoring backend** : elle consomme `score_total` tel
  quel, elle ne le recalcule pas.
- Ne retire pas encore `kThinDemotionRichThreshold` / `demote` (cycle suivant,
  une fois le tri observé en prod).
- Ne fige pas le `block_score` rapporté à la mesure sur celui qui a fixé le rang
  (documenté ; PR-6 joint sur `(day_key, section)`).
