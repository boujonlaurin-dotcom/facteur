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
| 1 | PR 1 | **B-1** métadonnées sources (script idempotent) | 🟡 cette PR |
| 2 | PR 2 | **B-2** fold couverture + dry-run comparatif du top-15 | à venir |
| 3 | PR 3 | **C-1** stopper la fabrication d'intérêts + unicité `(user_id, topic_slug)` | à venir |
| 4 | PR 4 | **A** score mixte, `is_multi` retiré, poids en env, bump `editorial_v4` | à venir |
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
