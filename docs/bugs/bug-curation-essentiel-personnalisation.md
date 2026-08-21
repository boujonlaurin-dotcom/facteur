# Bug — « Ton Essentiel » n'est pas personnalisé (et paraît anecdotique)

- **Statut** : diagnostic figé, lot de PR en cours
- **Ouvert le** : 2026-08-01
- **Baseline** : [`bug-curation-essentiel-personnalisation-baseline.md`](bug-curation-essentiel-personnalisation-baseline.md)
  (+ requêtes rejouables : `docs/qa/scripts/baseline_curation.sql`)
- **Antécédent direct** : [`bug-actus-du-jour-ranking.md`](bug-actus-du-jour-ranking.md)
  — c'est le **même pendule**, vu depuis l'autre extrémité.

## Les deux griefs PO

1. « mon intérêt pour l'IA ne remonte pas dans les 1ers articles »
2. « le contenu semble anecdotique, voire random — pas des news importantes »

Ils ont **une seule cause mécanique**, et elle est en amont d'`essentiel_service`.

## Le verdict mesuré

Sur 30 j (132 users, `format_version = 'editorial_v3'`) :

| Métrique | Valeur |
|---|---|
| Slots du top-5 quasi-universels (`pour_vous`) | **80,8 %** |
| Slots du top-5 réellement personnels (< 10 % des users) | **4,2 %** |
| Slots du top-5 issus d'une source suivie | **16,3 %** |
| Slots du rang **6-10** issus d'une source suivie (tronqués, jamais vus) | **37,4 %** |
| CTR d'un slot **source suivie** | **3,58 %** |
| CTR d'un slot source non suivie | **0,99 %** |

> La carte s'appelle « Ton Essentiel », le mode s'appelle `pour_vous`. Dans les
> faits c'est le **même journal pour tout le monde** — et le tri relègue le
> personnel en 6-10, que la carte tronque, alors qu'il **convertit 3,6× mieux**.

## Le mécanisme, en code (commit `71e81f90`)

**a) Le pool éditorial est user-agnostique.**
`app/services/editorial/candidate_pool.py:build_editorial_pool_stmt` — aucune
jointure `user_*`. En batch, le pool *personnalisé* de `_get_candidates`
(`digest_selector.py:876-1022`) est **calculé pour chaque user puis jeté** :
`digest_selector.py:406-407`, `compute_candidates = global_pool_candidates or candidates`.

**b) `cluster_input_limit: 15`** (`config/editorial_config.yaml:6`) — seuls les
15 clusters les plus couverts atteignent le LLM. Un sujet IA couvert par 1-2
médias n'y entre jamais.

**c) La personnalisation est un tie-breaker de 3ᵉ rang.**
`digest_selector.py:1296-1305` :
```python
return (is_multi, subject_importance(s), subject_perso(s))
```
`subject_importance` est **continu** (couverture + récence + polarisation) → il
n'y a jamais d'égalité, donc `subject_perso` **ne départage jamais**. La
docstring l'assume : *« La personnalisation ne sert plus qu'à départager. »*

Confirmé par les `selection_reason` persistés : « Couvert par 2 sources » atteint
le top-5 dans **89,7 %** des cas, « Source suivie » dans **17,0 %**.

## Pourquoi « anecdotique » : `source_count` mesure la redondance

Cinq sources raflent **62,8 %** des slots héros : Ouest-France (19,6 %),
Home Fil actu (15,8 %), France Info (14,9 %), CNEWS (6,4 %), Europe 1 (6,1 %).
Elles réécrivent les mêmes dépêches, forment donc mécaniquement les plus gros
clusters, et gagnent le concours de taille. `source_count` est censé dire
« N rédactions indépendantes ont jugé ce sujet important » ; 5 reprises d'une
dépêche AFP, c'est 5 domaines mais **~1 jugement éditorial**.

Côté thèmes : `society` (faits divers, incidents locaux, météo) pèse **42,7 %**
des slots héros pour 10,5 % du corpus, quand `politics` tombe à **1,3 %**.

> ⚠️ **Correction au rapport d'origine** : sa colonne « CTR top-5 » donnait ces
> 5 sources à 0,00-0,02 %. C'est faux (et arithmétiquement impossible). Mesuré :
> **1,24 % contre 1,71 %** pour le reste, soit ×1,4. L'argument tient sur la
> **composition** — 62,8 % de la surface pour une couverture thématique qui
> survit à 68-88 % sans elles — **pas** sur un CTR nul. Le vrai gradient du
> dossier est ailleurs : **source suivie ×3,6**.

## Le cadrage : c'est un pendule, pas un bug

[`bug-actus-du-jour-ranking.md`](bug-actus-du-jour-ranking.md) documente une
décision PO validée de juin 2026, dont le grief était **l'exact inverse**
(« un sujet 11 sources se retrouve 10ème »). Le correctif a basculé à 100 %
couverture.

> Le système est passé de **100 % perso** à **0 % perso**. Les deux positions
> sont des **tris purs** ; une **somme pondérée** n'a jamais existé. C'est
> l'explication de « trois cycles sans amélioration ressentie ».

La cible n'est donc ni « revenir à la perso » ni « réserver des slots », mais :

```
score_sujet = w_importance · norm(importance) + w_perso · norm(perso)
              ↑ chantier A          ↑ chantier B         ↑ chantier C
                                    (corpus)             (apprentissage)
```

**Les deux termes sont aujourd'hui faux et le mélange n'existe pas.** A sans B
pondère de la redondance ; A sans C pondère du bruit.

## Séquence

| # | PR | Contenu | Statut |
|---|---|---|---|
| 0 | — | `BYPASSRLS` + figer la baseline | ✅ **fait le 01/08** |
| 1 | PR 1 | **B-1** métadonnées sources (script idempotent) | ✅ mergée (#1047) |
| 2 | PR 2 | **B-2** fold couverture + dry-run comparatif du top-15 | ✅ **cette PR** |
| 3 | PR 3 | **C-1** stopper la fabrication d'intérêts + unicité `(user_id, topic_slug)` | ✅ **cette PR** |
| 4 | PR 4 | **A** score mixte, `is_multi` retiré, poids en env, bump `editorial_v4` | ✅ **cette PR** |
| 5 | PR 5 | **A** pool personnalisé rebranché (`digest_selector.py:406-407`) | à venir |
| 6 | PR 6 | **C-2** taux appris lissés vers le prior population | à venir |

---

## PR 1 — B-1 : réparer les métadonnées du catalogue

Livrable : `packages/api/scripts/fix_source_metadata.py` (dry-run par défaut,
`--apply --allow-prod` gardé, idempotent, table de corrections explicite et
relue — pas d'heuristique).

### Ce que ça corrige

13 sources, toutes des médias français taggés `language = 'en'` par un titre de
flux en anglais. Dont :

| Source | Correction | Art./30 j |
|---|---|---|
| `Home Fil actu - actualités` → **`BFMTV`** | nom + `en`→`fr` | 4 803 |
| L'Équipe | `en`→`fr`, `culture`→**`sport`** | 3 065 |
| Libération - Politique | `en`→`fr`, `custom`→**`politics`** | 1 347 |
| CNEWS | `en`→`fr` | 1 318 |
| Society (society.fr) | `en`→`fr`, `tech`→**`society`** | 22 |

### ⚠️ Portée réelle — la prémisse du plan d'origine était fausse

Le plan justifiait B-1 par « le pool éditorial filtre sur la langue ».
**Vérifié : il ne filtre pas.** `build_editorial_pool_stmt`
(`editorial/candidate_pool.py:126-156`) n'a aucune clause `language`. Le filtre
langue vit en aval, dans le pool **personnalisé** (`digest_selector.py:1008-1009`)
et à la projection (`essentiel_service.py:443-452`).

Conséquences, à énoncer clairement :

- **Ces corrections ne bougent aucune des 5 métriques de baseline aujourd'hui.**
  C'est un **prérequis de la PR 5**, pas un levier sur le grief.
- Le fix `theme` est, lui, actif immédiatement : `Source.theme` pilote le mute
  de thème (`digest_selector.py:888,970`) et les presets sereins
  (`recommendation/filter_presets.py:202,294`). Un user qui mute `sport`
  recevait quand même les 3 065 articles/30 j de L'Équipe, rangés en `culture`.

### Ce que le script **ne** fait **pas**, volontairement

- **Il ne remplit pas les 206 `language IS NULL`** (64 % des sources actives).
  `is_foreign_source(None)` vaut `False` : un NULL est **déjà** traité comme FR.
  Renseigner la colonne rendrait *nouvellement invisibles* les sources
  réellement étrangères pour les **51 users** à `hide_non_fr_sources = true`.
  Changement de comportement produit ⇒ décision PO séparée.

### Trouvaille de l'audit — à arbitrer

**18 sources curées, actives, à 0 article sur 30 jours** : France Inter,
Les Échos, Libération, Le Point, Brut, Alternatives Économiques, Fouloscopie,
Heu?reka, Monsieur Phi, ScienceEtonnante… Ce sont exactement les sources de
qualité censées nourrir le digest.

Et il y a des **doublons** : `Le Point` et `Libération` existent chacun en deux
entrées — la version **curée est morte**, la version **non curée est vivante**
(et c'est celle qui était mal taggée). Le catalogue perd donc ses meilleures
sources pendant que le fil brut de BFMTV produit 4 803 articles/30 j.

> C'est un troisième angle sur « anecdotique », que ni l'un ni l'autre des
> rapports n'avait vu. Feeds morts à réparer + doublons à fusionner : à cadrer
> comme un chantier propre (candidat PR 2 bis), pas à bricoler dans ce script.

### Vérification

- `pytest tests/scripts/test_fix_source_metadata.py -v` — 22 tests, logique pure
  (diff, idempotence, garde-fou `expected_name`, intégrité de la table).
- Dry-run joué contre la prod en lecture seule : 13 sources à corriger, 0
  introuvable, 0 renommée.
- Aucune migration Alembic : DML pure sur des colonnes existantes.

---

## PR 2 — B-2 : ne compter que les rédactions qui portent un jugement

Point d'insertion unique : le « fold agrégateurs » de
`importance_detector.py`. `_is_aggregator` devient `_counts_toward_coverage`,
appliqué aux **deux** collections (`source_ids` **et** `source_domains`).

Critère : `SourceType.REDDIT` **OU** (`source.is_curated` falsy **ET**
`reliability_score ∈ {low, mixed}`). Réglable sans déploiement via
`EDITORIAL_COVERAGE_FOLD_RELIABILITY` (défaut `low,mixed`) et
`EDITORIAL_COVERAGE_FOLD_ENABLED` (kill switch, défaut `true`).

### Les 3 corrections mesurées au plan d'origine (§1)

1. **`unknown` retiré du critère.** `unknown` = jamais évaluée, pas « peu
   fiable ». L'inclure folderait 39,5 % du corpus `politics` (déjà à 1,3 % du
   top-5), via `Libération - Politique` notamment. Critère restreint à
   `low`/`mixed` ⇒ 19 sources / 9 509 art./30 j, `politics` foldé retombe à
   29,1 % (= `society`).
2. **Le critère n'attrape que 2 des 5 pourvoyeurs** (Home Fil actu, CNEWS) ;
   Ouest-France / France Info / Europe 1 sont curées ⇒ **M4 < 45 % n'est pas
   atteignable par B-2 seul**. Assainissement du terme `importance`, pas le
   levier des cibles (PR 4-5).
3. **Le fold s'applique à `source_ids` aussi**, pas seulement `source_domains` :
   `routers/feed.py` lit `source_ids` et hériterait sinon d'un comptage
   incohérent.

### Dry-run comparatif (prod, lecture seule, 24 h)

`scripts/dryrun_coverage_fold.py --hours 24 --tag b2-fold`. Résultat (1 565
contenus, 1 086 clusters) : **top-15 change de 13 %** (garde-fou : abort si
> 50 %), **18 clusters franchissent `2→1`**, 9 franchissent `3→2`,
**`politics` net = +0** (non net-sortant). Distribution `4+ domaines` :
22 → 13. Artefacts : `.context/dryrun_coverage_fold_b2-fold.{json,md}`.

Aucune migration.

---

## PR 3 — C-1 : arrêter de fabriquer des intérêts

Correctif **au moment de l'écriture**, pas au scoring.

- `_adjust_interest_weight` (lecture) → **UPDATE seul** : une lecture ne crée
  plus de `user_interests` sur le thème de la source.
- `_adjust_subtopic_weights` → paramètre `allow_create` (défaut `False`). Seuls
  les signaux **explicites** (like / save / note / feedback, actions digest
  SAVE|LIKE) peuvent créer une ligne ; lecture et signaux négatifs = update
  seul. **Le tail « interest par thème source » de cette fonction est gardé par
  le même `allow_create`** — il fabriquait lui aussi un `user_interests` sur
  lecture (double-comptage §3.1 confirmé, cf. handoff).
- Onboarding (`user_service.py`) : `db.add(UserSubtopic)` → upsert
  `on_conflict_do_nothing` (ne casse pas sur la nouvelle contrainte).

### Migration `cq01_subtopics_uniq_muted` (head : `sa02_alerts_v2`)

1. Dédup `user_subtopics` sur `(user_id, topic_slug)` (garde le plus grand
   weight) — la contrainte d'origine avait été droppée par accident
   (`4d497ce7bcc2`).
2. `UNIQUE uq_user_subtopics_user_topic` + `INDEX ix_user_subtopics_user_id`
   (la table n'avait aucun index).
3. `DELETE` idempotent des `user_interests` contredisant un `muted_themes`
   (53 lignes / 27 comptes au 02/08).

Idempotente, testée `alembic upgrade head` sur DB vide + downgrade/re-upgrade.
**Risque expand-contract assumé** (DB partagée) : pendant ≤ 1 semaine le backend
`production` (ancien code) peut recréer une course doublon (mesuré 5×/vie-de-table)
⇒ `IntegrityError` ponctuelle au lieu d'un doublon silencieux. Le `DELETE` muté
est **à rejouer une fois après la release hebdo**.

### Vérification C-1

Nouvelles métriques (M8-M11) dans `docs/qa/scripts/baseline_curation.sql`
(bloc « C-1 », à lancer via le rôle service — `claude_analytics_ro` n'a pas le
`SELECT` sur `user_interests`/`user_subtopics`) :

| # | Métrique | Avant (02/08) | Après |
|---|---|---|---|
| M8 | `user_interests` sur un thème muté | 53 (27 comptes) | 0 après migration |
| M9 | Lignes `user_interests` à `1,0 < w < 1,2` | 174 / 746 | ne plus croître |
| M10 | Users à amplitude `user_subtopics` < 0,2 | 85 / 101 | ne plus croître |
| M11 | Doublons `(user_id, topic_slug)` | 5 | 0, impossible |

---

## PR 4 — A : le score mixte existe enfin (`editorial_v4`)

Livré par cette PR (aucun DDL, aucun changement mobile) :

- **Clé de tri v4** : `digest_selector.mixed_subject_rank_score` (module-level,
  duck-typée) remplace le tuple `(is_multi, importance, perso)` par le scalaire
  `(1-w)·importance_100 + w·perso_100`, `w = SUBJECT_PERSO_WEIGHT = 0.40`.
  Les solos ne sont plus relégués par préfixe mais par `coverage(1)=0`
  (+ `SUBJECT_SOLO_MALUS` configurable, 0.0 par défaut). « À la Une » reste
  épinglé rang 1. Sujet sans actu → `float("-inf")` **avant** toute
  arithmétique (piège `0.0 × -inf = nan` au rollback w=0).
- **Rollback sans redeploy** :
  `SCORING_OVERRIDES='{"SUBJECT_PERSO_WEIGHT": 0.0, "SUBJECT_SOLO_MALUS": 1000.0}'`
  ≈ ordre v3. Retuning de `w` par la même variable.
- **`essentiel_service` devient un adaptateur** : même formule via les mêmes
  helpers (`helpers/editorial_ranking`), `perso = pillar_score` persisté
  (médiane du pool pour les articles sans score). Test de parité anti-divergence.
- **Dry-run** : `scripts/dryrun_subject_mix.py` (sanity v3 + sweep de `w` +
  M1-M4 + churn sur snapshots prod, read-only).

### Découvertes de l'exploration (consignées ici)

- **Le score du moteur était persisté puis jeté deux fois** : écrit dans le
  JSONB (`digest_service.py`, `actu_article.score`) mais ignoré au tri des
  sujets (3ᵉ position d'un tuple jamais atteinte) ET à la lecture
  (`_build_editorial_response` renvoyait `topic_score=0.0` en dur). Corrigé :
  il porte désormais le terme perso du mélange et remonte en
  `DigestTopicArticle.pillar_score`.
- **`badge == "actu"` est universel** : écrit inconditionnellement sur toute
  actu de sujet à la persistance → `_W_BADGE_ACTU` (+25) et le préfixe de tri
  `_is_actu_du_jour` étaient des no-ops en prod (et `is_actu_du_jour` est
  toujours vrai côté app). Supprimés du scoring ; le champ API reste pour le
  contrat mobile.
- **`_W_TRENDING` double-comptait la couverture** : `is_trending` est dérivé de
  `source_count >= 3` à la lecture — le même signal que le score de couverture.
  Supprimé.
- **Filtre figé dans `routers/contents.py`** : les deux loaders de
  `/perspectives` matchaient `format_version IN ('editorial_v1','editorial_v2')`
  → **v3 ne matchait déjà plus** (fallback live silencieux, logos CTA ≠ bottom
  sheet). Passés en préfixe `startswith("editorial_")`, aligné sur
  `digest_content_refs.py` / `push_dispatcher.py`.
