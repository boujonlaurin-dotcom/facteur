# Maintenance — Optimisation des recos, lot 2 : tuning, ordre des blocs, mesure

> **Date d'ouverture** : 2026-08-02
> **Branche** : `boujonlaurin-dotcom/tuning-seuils-et-ranking-tournee`
> **PRs ciblées** : `main`
> **Type** : lot séquencé (6 PRs)
> **Prolonge** : [`maintenance-reco-quality-step-up.md`](./maintenance-reco-quality-step-up.md)
> **Ne le refait pas** — les constats de PR0/PR1/PR2 y restent la référence.

## Cadre

Quatre axes demandés par le PO : (1) affiner les seuils/constantes contre un jeu
de données et de faux profils, (2) réordonner les blocs de la Tournée par la
somme de recommandabilité de leur top-3, (3) câbler de la mesure objective, (4)
faire apprendre l'algo sur des taux de clics.

Trois faits vérifiés cadrent le lot.

**L'A/B est hors de portée.** DAU moyen 16,1 (78 users distincts / 30 j).
Détecter +0,3 pp sur un CTR de base de 1,41 % demande ~27 000 slots/bras *avant*
clustering ; avec un ICC de 0,03-0,10 par user le facteur de design passe à
×17-×55, soit **1,5 à 5 ans par bras**. Les décisions de tuning se prennent
**offline**. La mesure online est une jauge de garde-fou, pas un arbitre.

**Il n'existait aucun tracking d'impression.** `trackDigestItemViewed` n'a aucun
call site en prod ; `last_impressed_at` n'est écrit qu'au pull-to-refresh. Le
dénominateur du CTR était reconstruit depuis `daily_digest.items`, ce qui ne
couvre que le digest — pas les sections de la Tournée. C'est le blocage dur de
l'axe 4, et l'objet de PR-1.

**La prémisse de l'axe 2 sur la comparabilité était inversée.**
`recommendation_service.py:2455-2470` restreint les sections thème de la Tournée
aux **sources suivies** (chemin two-phase, repli curated si 0 source suivie).
Blocs thème et blocs source encaissent donc le même `TRUSTED_SOURCE = 35` : un
tri global au score ne remonte pas mécaniquement les sources. Le tri global
demandé est sûr.

**Décisions PO au cadrage** : lot complet séquencé · tri **global** (familles
mélangées) · le tri s'applique **aussi aux comptes ayant personnalisé leur
ordre** (l'ordre manuel devient une base, pas une autorité) · méthodo
**sensibilité d'abord**, gold en garde-fou seulement.

**Zéro migration Alembic sur tout le lot** — conséquence de deux propriétés de
l'existant : `analytics_events.event_data` est en JSONB, et `ScoringWeights`
n'expose que des attributs de classe. Si une migration apparaît dans une PR de
ce lot, c'est un signal d'erreur de conception à réexaminer.

## Séquence

| PR | Objet | Axe | État |
|---|---|---|---|
| PR-1 | Instrumentation d'impression | 3 | **livrée** |
| PR-2 | `SCORING_OVERRIDES` + contexte de sweep | 1 (outillage) | **livrée** |
| PR-3 | Personas, corpus gelé, harnais de sensibilité | 1 | à faire |
| PR-4 | Ordre des blocs par score top-3 | 2 | **livrée** |
| PR-5 | Shrinkage affinité source + `DIGEST_SPORT_PENALTY` | 4 (amorce) | à faire, gated sur PR-3 |
| PR-6 | `evaluate_tournee_ctr.py` | 3 | à faire, ≈2 semaines après PR-1 |

PR-1 passe en premier parce que sa valeur est fonction du **temps calendaire
écoulé** : chaque jour non shippé est un jour de données perdu.

---

## PR-1 — Instrumentation d'impression

### Ce qui est posé

**Event `article_impression`** dans `analytics_events` (`event_type`), aucune
table, aucune migration : la colonne `event_data` est déjà en JSONB et les trois
colonnes utiles (`user_id`, `event_type`, `created_at`) sont déjà indexées.

Propriétés portées :

| Propriété | Source | Note |
|---|---|---|
| `content_id` | carte | |
| `section_key` | `sectionKey(section)` | |
| `section_family` | `sectionFamily(section)` | `theme \| source \| veille \| editorial` |
| `surface` | rendu | `tournee \| essentiel` |
| `section_index` | rang de la section | |
| `position_in_section` | rang de la carte | |
| `global_position` | compteur de page | porte l'effet de position |
| `score_total` | `recommendation_reason.score_total` | `null` sur les blocs éditoriaux |
| `block_score` | `FluxContinuState.blockScores[sectionKey]` | **renseigné depuis PR-4** : somme des 3 meilleurs `score_total` du bloc — c'est le champ qui relie « ordre des blocs » et « CTR mesuré ». Recalculé à chaque recomposition, donc c'est le score du bloc **au moment de l'impression** ; l'ordre, lui, est gelé à la journée, donc les deux peuvent diverger dans la journée (load-more, refetch). Analyse : joindre sur le couple `(day_key, section)`, pas sur la valeur seule |
| `theme`, `source_id` | carte | |
| `is_serene`, `underfilled` | état | découpes de lecture |
| `day_key` | `TourneeProgressService.dayKey` | frontière 4 h Paris |
| `session_id` | `AnalyticsService` | |
| `algo_version` | **serveur** | cf. ci-dessous |

### Décisions et leurs raisons

**Seuil de viewabilité : ≥ 50 % pendant ≥ 1 000 ms** (standard MRC display).
Au-dessus de 50 %, une carte à moitié coupée par le bas de l'écran ne serait
jamais comptée alors qu'elle est lisible ; sans seuil de durée, traverser la
Tournée d'un coup de pouce gonflerait le dénominateur de cartes que personne
n'a lues.

**Nouveau widget, pas une extension d'`AutoGrowCandidate`.** Celui-ci a un
seuil de 0,9, exclut les articles lus (`_visible && !_read` — or un article lu
*a été* impressionné, c'est même le numérateur du CTR) et porte un contrat
`dispose`/microtask qui sert un tout autre besoin. Les deux `VisibilityDetector`
s'imbriquent sans conflit, chacun ayant sa clé.

**Périmètre : Tournée + Essentiel.** Pas Flâner — le flux chronologique est
voulu, un CTR par rang n'y voudrait rien dire. Pas les **éditions passées**
(`/edition`) : c'est de la consultation d'archive, pas une Tournée servie par
l'algo ; les y compter fausserait le taux. Techniquement, `SectionBlock` ne
compte que si `impressionDayKey` est non-null, et les chemins archive le
laissent nul.

**Dédup 1×/(`content_id`, `section_key`, `day_key`)**, sur le pattern exact de
`trackSuggestionImpression` : liste SharedPreferences purgée au changement de
jour + garde-fou mémoire dans le process (une carte recyclée par le viewport
paresseux re-déclenche son tracker au scroll). Le **même** article vu dans deux
sections compte deux impressions : la position dans une section est justement ce
qu'on mesure.

**Batching obligatoire.** `_logEvent` fait un POST HTTP par event ; ~30
impressions par session, c'est 30 POST fire-and-forget sur réseau mobile.
Nouveau `POST /api/analytics/events/batch` (**additif** — `POST /events` reste
intact pour les binaires en circulation), buffer client flushé à 25 events / 10 s
d'inactivité / `endSession` (donc `AppLifecycleState.paused`, cf. `app.dart`).
Un lot qui échoue est **abandonné**, jamais ré-empilé : de l'analytics
best-effort qui se remettrait en file grossirait sans borne hors ligne.

Le batch **n'exécute aucun effet de bord** de `/events` (streak sur
`session_start`, mise à jour d'`app_version`) : `session_start` reste sur le
chemin unitaire. C'est écrit dans la docstring de l'endpoint.

**`algo_version` estampillé côté serveur.** Le mobile ne connaît pas la
configuration de scoring, et la faire redescendre dans `/api/feed` +
`/api/essentiel` puis remonter dans l'event serait trois surfaces de plumbing
pour la même valeur. Limite assumée et documentée : un redeploy entre le scoring
d'un flux et l'impression de ses cartes estampille la nouvelle version sur des
cartes scorées par l'ancienne — quelques minutes de données par déploiement.
`scoring_algo_version()` vit dans `scoring_config.py`, exactement là où PR-2
ajoutera le hash des overrides actifs.

**Backend-only, pas de miroir PostHog.** Le dénominateur doit se joindre à
`user_content_status` × `contents` × `daily_digest`, et cette jointure n'existe
qu'en Postgres. La divergence est déjà mesurable : `article_read` = 200 events /
12 users sur 30 j contre **1 312 `consumed` / 50 users** — le pipeline PostHog
couvre ~15 % des clics réels. Un miroir donnerait deux chiffres divergents pour
la même métrique.

**Sonde `tournee_customized` sur `session_start`.** C'est du SharedPreferences
local, invisible en DB : c'est la seule façon de savoir combien de comptes PR-4
concerne réellement.

**`EssentielArticle.sourceId`** : `/api/essentiel` servait déjà `source.id`, le
parse mobile le jetait. Ajouté (additif, round-trip par le cache) — il porte la
découpe « CTR par source » sur la surface héros.

### Volume et coût

~30 impressions uniques/user/jour × 16,1 DAU ≈ **480/jour, 14 500/mois**.
`analytics_events` fait 385/j aujourd'hui → on triple, non-problème Postgres.

Index partiel `CREATE INDEX CONCURRENTLY … WHERE event_type='article_impression'`
→ **différé** jusqu'à >100k lignes (≈ 7 mois au volume estimé).

### Fichiers

| Fichier | Nature |
|---|---|
| `packages/api/app/routers/analytics.py` | `POST /events/batch`, `_stamp_algo_version` |
| `packages/api/app/services/analytics_service.py` | `log_events` (bulk, 1 commit) |
| `packages/api/app/services/recommendation/scoring_config.py` | `scoring_algo_version()` |
| `packages/api/tests/routers/test_analytics_events_batch.py` | nouveau |
| `apps/mobile/lib/features/flux_continu/widgets/article_impression_tracker.dart` | nouveau |
| `apps/mobile/lib/core/services/analytics_service.dart` | `trackArticleImpression`, buffer, sonde |
| `apps/mobile/lib/features/flux_continu/widgets/section_block.dart` | câblage Tournée |
| `apps/mobile/lib/features/flux_continu/widgets/essentiel_hi_fi_card.dart` | câblage Essentiel |
| `apps/mobile/lib/features/flux_continu/models/flux_continu_models.dart` | `sectionFamily`, `renderedCardCount`, `sourceId` |
| `apps/mobile/lib/features/flux_continu/screens/flux_continu_screen.dart` | rang absolu + `dayKey` |
| `apps/mobile/test/core/services/analytics_service_impressions_test.dart` | nouveau |
| `apps/mobile/test/features/flux_continu/widgets/article_impression_tracker_test.dart` | nouveau |

### Vérification post-merge (à faire, J+2 après déploiement)

```sql
SELECT count(*), count(DISTINCT user_id)
FROM analytics_events
WHERE event_type = 'article_impression'
  AND created_at > now() - interval '2 days';
```

Attendu ≈ 960 lignes / ~16 users/jour. **< 200 ou > 5 000 ⇒ seuil ou dédup
faux** — ne pas commencer PR-6 sans avoir tranché.

**Gate de couverture** : ≥ 80 % des `consumed` du jour ont une impression
appariée sous 24 h. C'est exactement le test qui aurait attrapé le trou
d'`article_read`.

```sql
WITH consumed AS (
  SELECT user_id, content_id, updated_at
  FROM user_content_status
  WHERE status = 'consumed'
    AND updated_at > now() - interval '2 days'
),
impressed AS (
  SELECT user_id,
         event_data->>'content_id' AS content_id,
         created_at
  FROM analytics_events
  WHERE event_type = 'article_impression'
    AND created_at > now() - interval '3 days'
)
SELECT round(100.0 * count(i.content_id) / nullif(count(*), 0), 1) AS pct_apparie
FROM consumed c
LEFT JOIN impressed i
  ON i.user_id = c.user_id
 AND i.content_id = c.content_id::text
 AND i.created_at BETWEEN c.updated_at - interval '24 hours' AND c.updated_at;
```

Un taux durablement bas signale une **surface non instrumentée**, pas un bug de
seuil : le premier réflexe est de chercher d'où viennent les `consumed` non
appariés (Flâner et le reader sont hors périmètre par construction — les en
exclure avant de conclure).

---

## PR-2 — `SCORING_OVERRIDES` + contexte de sweep

Pas pour l'A/B (impossible), **pour la latence de rollback** : aujourd'hui,
changer une constante de scoring = commit + redeploy Railway sur une DB partagée
main-staging / production. Cette PR pose deux surfaces de surcharge de
`ScoringWeights`, une déployée et une offline.

### Surcharge d'environnement `SCORING_OVERRIDES` (déployée)

Une seule variable d'env portant du JSON `{"CONSTANTE": valeur, …}`, parsée
**une fois** au premier import, appliquée par `setattr` sur `ScoringWeights`.
Rollback = vider la variable Railway + restart (~30 s). Précédent : les env vars
ad hoc déjà en place (`EDITORIAL_SOLO_SUBJECT_MIN_SCORE`,
`EDITORIAL_COVERAGE_FOLD_ENABLED`…).

- **Placement critique** : appliquée **en bas de `scoring_config.py`**, donc au
  premier import de `ScoringWeights`, AVANT que tout autre module ne fige une
  valeur en argument par défaut (`scheduler.decayed_subtopic_weight`) ou en copie
  de niveau module (`essentiel_service._W_TRENDING`). Ces call sites lisent donc
  la valeur **surchargée** — l'env override est effectif partout.
- **Robustesse** : JSON invalide → erreur loggée, **rien appliqué** (fail-closed
  sur la config) ; clé inconnue → WARN + ignorée ; chaque override → INFO.
  `PILLAR_WEIGHTS` n'est accepté que si la somme fait 1.0.
- **`algo_version`** : `scoring_algo_version()` suffixe désormais un hash court,
  déterministe et stable des overrides actifs (`pillars_v1+ovr.<hash>`). Sans
  override actif, la version reste nue (`pillars_v1`) — inchangé pour les
  binaires sans la variable. C'est ce qui rend deux semaines de CTR mesurées sous
  deux jeux de constantes comparables : l'event `article_impression` porte de
  quelle config il relève (cf. PR-1).

### Contexte de sweep offline `weights_override` (tuning)

`scripts/_scoring_overrides.py::weights_override(**kwargs)` — généralisation
directe du `_threshold_override` de `evaluate_veille_curation.py` (qui ne patchait
que `VEILLE_RELEVANCE_THRESHOLD`, et **délègue désormais** à cette mécanique
partagée). Patche N attributs le temps d'un `with`, restaure en `finally`.
Consommé par les harnais de sensibilité/sweep de PR-3.

### Deux pièges traités

1. **Constantes liées au chargement du module (non patchables à chaud).**
   `scheduler.decayed_subtopic_weight(decay=ScoringWeights.SUBTOPIC_DECAY)` fige
   la valeur à l'import : un `setattr` runtime serait un **no-op silencieux**.
   `weights_override` **lève** si on cible un nom de `NON_PATCHABLE_AT_RUNTIME`
   (= `{SUBTOPIC_DECAY}`). Garde anti-drift :
   `test_scoring_overrides.py::test_no_new_module_bound_defaults` parse l'AST de
   tout `app/`, recense les défauts `def … = ScoringWeights.X` et échoue si la
   liste s'allonge sans que la garde soit mise à jour. *(L'env override, lui,
   atteint ces call sites car il court avant leur import — seul le sweep runtime
   est concerné.)*
2. **`PILLAR_WEIGHTS` est un dict mutable de classe** : deep-copié avant patch,
   restauré après, et l'invariant `sum == 1.0` réasserté une fois tous les patchs
   posés (les deux surfaces).

### Règle de discipline (non négociable)

L'override env est un outil de **tuning et de rollback, pas une surface de
configuration**. Tout override qui survit plus d'un cycle est **promu dans
`scoring_config.py` et la variable vidée** — sinon la source de vérité dérive,
ce qui est le problème même qu'on cherche à résoudre.

### Fichiers

| Fichier | Nature |
|---|---|
| `packages/api/app/services/recommendation/scoring_config.py` | `_apply_env_scoring_overrides`, `_ACTIVE_OVERRIDES`, hash dans `scoring_algo_version()` |
| `packages/api/scripts/_scoring_overrides.py` | nouveau — `weights_override`, `NON_PATCHABLE_AT_RUNTIME` |
| `packages/api/scripts/evaluate_veille_curation.py` | `_threshold_override` délègue à `weights_override` |
| `packages/api/tests/scripts/test_scoring_overrides.py` | nouveau — sweep, env, garde AST |

Aucune migration Alembic (`ScoringWeights` n'expose que des attributs de classe).

---

## PR-4 — Ordre des blocs par score top-3 (mobile)

### Ce qui est posé

La **dépriorisation binaire** riches/maigres (partition stable gatée sur
`richCount >= kThinDemotionRichThreshold`) ne classait pas, elle reléguait. Elle
est remplacée par un tri sur la **somme des 3 meilleurs `score_total`** des
articles du bloc — score que le backend renvoie déjà dans
`recommendation_reason`. Les slots manquants comptant 0, un bloc à 1 article est
pénalisé *structurellement* (≈ 1 × s vs 3 × s), ce qu'une moyenne n'aurait pas
fait. Répond à la plainte PO « des blocs à 1 article remontent en tête ».

**PR-4 boucle aussi PR-1** : `block_score` était câblé de bout en bout
(`SectionBlock` → `ArticleImpressionTracker` → `analytics_service`) mais
personne ne le renseignait — il valait `null` en prod. `FluxContinuState.blockScores`
le remplit désormais depuis la même passe qui a fixé l'ordre.

### Décisions et leurs raisons

**Ordre gelé à la journée tournée** (frontière 07h30 Paris, clé
`tournee_score_order_v1` stockant `{"day", "keys"}`).
`_fanOutSectionsProgressive` émet après chaque tâche (~10-15 recompositions) :
trier à chaque emit ferait sauter les blocs sous les yeux. L'ordre est calculé
**une fois**, à la complétion du fan-out, puis rejoué tel quel par tous les
composes suivants du jour (cache in-day, pull-to-refresh, refetch partiels).
Clé unique day-stampée ⇒ auto-invalidante, rien à ajouter à `purgeOldPrefsKeys`.

**Réinjection à position absolue via `mergeVisibleReorder`**, pas `applyOrder` :
ce dernier pousse les clés inconnues en **fin**, ce qui ferait couler Actus /
Bonnes Nouvelles (jamais scorées) jusqu'à les faire tomber hors du cap 13.

**Portée plus large que la classification maigre/riche** : toute section résolue
portant au moins un article scoré entre au classement — veille et « Choisie pour
vous » comprises. Une veille pauvre coule donc désormais elle aussi (décision
PO). Une section dont *aucun* article ne porte de `recommendation_reason`
(éditorial, coquille de boot) n'entre pas dans la map et **garde sa place**
plutôt que de couler à 0.

**Le tri s'applique aussi aux comptes personnalisés** (décision PO) : l'ordre
manuel reste la base d'entrée et départage à score égal (le tri est stable),
mais il ne fait plus autorité au-delà. Risque assumé : un bloc glissé en tête
peut descendre le lendemain — l'ordre étant figé à la journée, jamais dans la
même session.

**Kill-switch** `kTourneeScoreSortEnabled` : à `false`, aucun calcul, aucune
persistance, et la dépriorisation binaire reprend à l'identique.
`kThinDemotionRichThreshold` et le paramètre `demote` deviennent obsolètes mais
**partent au cycle suivant** — la CI ne lance pas `flutter test`, on ne retire
pas les deux filets d'un coup. `thinKeys` reste utilisé par le backfill et la
modal favoris.

### Fichiers

| Fichier | Nature |
|---|---|
| `apps/mobile/lib/features/flux_continu/utils/section_score_order.dart` | nouveau — `blockScore`, `rankKeysByBlockScore`, `applyScoreOrder` (pur, testable sans binding) |
| `apps/mobile/lib/features/flux_continu/providers/flux_continu_provider.dart` | `blockScores` dans `_classifyFavoriteSections`, `scoreOrder` dans `_orderedTourneeKeys`, gel + persistance dans `_fanOutSectionsProgressive`, chargement dans `_buildStateFromPayload` |
| `apps/mobile/lib/features/flux_continu/models/flux_continu_models.dart` | `FluxContinuState.blockScores` |
| `apps/mobile/lib/features/flux_continu/providers/tournee_order_prefs_provider.dart` | `kTourneeScoreSortEnabled` |
| `apps/mobile/lib/features/flux_continu/services/tournee_progress_service.dart` | `loadScoreOrderForToday` / `setScoreOrderToday` |
| `apps/mobile/lib/features/flux_continu/screens/flux_continu_screen.dart` | 1 call site `SectionBlock(blockScore:)` (le seul portant `impressionDayKey`) |

Aucune migration Alembic (mobile-only).

---

## Journal des constantes modifiées

Une ligne par constante touchée par le lot : valeur avant/après, quel objectif a
bougé, de combien, sur quel fichier corpus. Vide tant que PR-3 n'a pas livré le
harnais — **aucune constante ne bouge sans mesure**.

| Date | Constante | Avant | Après | Objectif déplacé | Corpus |
|---|---|---|---|---|---|
| — | — | — | — | — | — |

---

## Différé — apprentissage par CTR (cœur de l'axe 4)

Impossible aujourd'hui : `user_content_status` ne compte que 1 395 lignes
`unseen` contre 4 188 `consumed` — les lignes sont créées à l'interaction, pas à
la livraison. Il n'existait aucun dénominateur honnête hors du digest ; PR-1 le
crée, il faut maintenant le laisser se remplir.

**Critères de ré-entrée, les cinq simultanément :**

| Signal | Seuil | Justification |
|---|---|---|
| Impressions collectées | ≥ 60 000 lignes `article_impression` | à 480/j = **125 jours** ; ≥ 1 200 impressions/user sur les 50 récurrents |
| Cellules (user, source) à n ≥ 30 impressions | ≥ 300 | en-dessous, un CTR rétréci est à 90 % le prior — on apprendrait le prior |
| Cellules (user, thème) à n ≥ 50 impressions | ≥ 150 | ~3 thèmes × 50 users |
| Stabilité du CTR d'impression | ±1 pp semaine-sur-semaine sur 4 semaines | si le taux de base dérive, tout poids appris court après une tendance |
| Couverture du numérateur | ≥ 80 % des `consumed` appariés sous 24 h | prouve que l'instrumentation ne rate pas une surface |

Date attendue au DAU actuel : **~2027-02**. Réévaluer plus tôt si le **DAU
dépasse 33** (→ > 30 000 impressions/mois, portes atteintes en ~2 mois).

**Ce qu'il ne faut PAS construire maintenant** : un job hebdo matérialisant
`user_source_ctr` / `user_theme_ctr` dès le jour 1. `analytics_events` conserve
tout, l'agrégat est calculable rétroactivement. Construire le tuyau avant la
porte, c'est le prototype de la chose qu'on ship et qu'on n'utilise jamais.

---

## Points à vérifier avant d'attaquer les PRs suivantes

1. `essentiel_service.py` passe-t-il par `PillarScoringEngine` ? (décide du coût
   réel de l'option « faire remonter un score » écartée en PR-4 — non ouvert).
2. Le repli two-phase de `personalized_theme_mode` quand le pool de sources
   suivies est maigre : tombe-t-il sur du curated non suivi ? Si oui la
   comparabilité inter-familles varie *par bloc et par jour*
   (`recommendation_service.py:2455-2470`).
3. **`content_interaction` = 0 event sur 30 jours** alors que
   `digest_provider.dart:729-790` est censé l'émettre. Chemin mort ou call site
   plus atteint — possible régression silencieuse **indépendante de ce lot**, à
   investiguer à part.
4. `_capSectionsToFit` (`flux_continu_provider.dart` L1180-1259) applique un
   plancher dur « jamais 1 seul article dès que 2 sont disponibles » — vérifier
   qu'il ne rend pas le tri de PR-4 partiellement inopérant sur les blocs qu'il
   vise.
