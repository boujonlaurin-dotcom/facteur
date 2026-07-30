# Maintenance — Step-up qualité des recos : arbitrage et séquence

> **Date** : 2026-07-29
> **Branche** : `boujonlaurin-dotcom/reco-quality-entity-affinity-audit`
> **PR ciblée** : `main`
> **Type** : arbitrage écrit + 2 PRs (PR0 outillage, PR1 câblage)
> **Brief d'origine** : `.context/reco-quality-architect-brief.md`
> **Runbook de l'instrument** : [`maintenance-feed-ranking-gauge.md`](./maintenance-feed-ranking-gauge.md)

## Résumé

Le brief posait que le plafond de qualité des recos était **la granularité de la
taxonomie (51 slugs) et l'absence de vectorisation**, et proposait 4 leads :
A fiabiliser le tagging, B créer la granularité, C nourrir la jauge,
D vectoriser.

La vérification (code + DB de prod, 2026-07-29) **infirme ce cadrage sur trois
points matériels**. Le plafond n'est pas la finesse du tagging : ce sont des
signaux **débranchés ou numériquement inertes**, et un instrument de mesure
**qui ne parsait pas le format de digest de production**.

> Avant d'être loin de Google News, on est loin d'avoir branché ce qui est déjà
> écrit.

D'où la séquence retenue : **PR0 rend la jauge exécutable**, **PR1 rebranche les
signaux existants**. B (taxonomie) et D (vecteurs) sont **différés**, avec des
critères de ré-entrée chiffrés (§ Différé).

## Ce que l'évidence corrige dans le brief

Toutes les mesures ci-dessous ont été refaites sur la DB de prod le 2026-07-29
(via le MCP Supabase — cf. la note RLS du runbook).

| Le brief disait | L'évidence dit |
|---|---|
| PR2 « affinité entités » a mergé pendant le blackout classif ⇒ **calibration à refaire** | **Le levier est inerte, pas mal calibré.** Prod : `user_entity_affinity` = 871 lignes / 34 users, **affinité max = 1,588**, moyenne **1,030**, **2 lignes > 1,3**, `interaction_count` max = **14**. Avec `ENTITY_AFFINITY_BASE = 8` ⇒ ~**0,4 pt brut sur `MAX_PERTINENCE_RAW = 160`** (0,25 % d'un pilier). Ça ne peut pas changer un ordre. Recalibrer un signal à 0,25 % ne sert à rien. |
| Cause = blackout du tagging | **Cause = câblage.** `digest_service.py:1396-1449` (READ / SAVE / LIKE / UNLIKE de l'Essentiel, la surface phare) appelle `_adjust_subtopic_weights` **4 fois et `_adjust_entity_affinity` 0 fois**. Idem `routers/contents.py:440`. `content_service.py` est symétrique partout (`:187/192`, `:476/477`, `:514/517`, `:562/565`, `:646/649`) — le chemin digest ne l'est pas. |
| « Aucun pont entité → sujet suivable » | **Inversé : le pont existe et il est livré.** `user_topic_profiles.entity_type` / `canonical_name`, canonicalisé par LLM (`ml/topic_enrichment_service.py`), `InterestState` à 4 états, épinglable (`FavoriteTabKind.subjectEntity`), alertable. 93 lignes / 30 users. |
| La résolution d'entités est un prérequis (B1) | **La résolution n'est pas le goulot** : 72/93 (77 %) des entités suivies exact-matchent une chaîne de `contents.entities` sous 30 j. Le vrai défaut : `pertinence._score_custom_topics` ne lit **jamais** `content.entities` ni `canonical_name` — il ne teste que `slug_parent` et `keywords`. Le pont entité n'existe que dans une couche de recall legacy (`layers/user_custom_topics.py`) qui **ne s'applique pas aux surfaces scorées par piliers**. |
| Lead C « lancer la jauge, coût ≈ nul » | **La jauge n'est pas non-lancée, elle est non-lançable.** 3 défauts silencieux, cf. le runbook : format `editorial_v3` non parsé (100 % des digests non-sereins), dénominateur assis sur `last_impressed_at` (ni impression ni position), et un NULL non typé qui faisait échouer la requête (`AmbiguousParameter`). **C'est une PR, pas une commande.** |
| — *(absent du brief)* | **`_adjust_interest_weight` est le seul signal appris sans decay.** +0,05 par lecture sur `source.theme`, cap 3,0 ; `scheduler.py` ne décaie que les subtopics et les entités. Prod : 724 lignes / 126 users, **32 au cap (≥ 2,99)**, 83 dans ]1,5 ; 3,0[, moyenne 1,260. Une ligne au cap vaut `50 × (3,0 − 1,0)` = **100 pts bruts = 62 % du pilier pertinence**. Chez les comptes les plus anciens, **l'âge du compte bat la pertinence du jour**. |
| — *(absent du brief)* | **`_score_custom_topics` n'a jamais tiré sur l'Essentiel / le Digest.** `digest_selector._score_candidates` construit le `ScoringContext` **sans `user_custom_topics`** ⇒ la garde `if not context.user_custom_topics: return 0.0, []` avale tout. Sujets custom **et** abonnements entités sont muets sur la surface phare. |

## Décisions PO (2026-07-29)

1. **« Flâner » chrono est voulu.** L'early-return de `recommendation_service.py`
   n'est pas un bug. La qualité reco se joue sur **Essentiel / sections Tournée /
   Digest / Veille**. *Ne pas y toucher.* Corollaire ironique : la surface phare
   est justement celle où le custom-topic est muet.
2. **Séquence = doc + PR0 + PR1**, avant tout chantier taxonomie ou vecteurs.
3. **Vocabulaire des entités noté, non traité ce cycle** : 24 089 chaînes
   distinctes sur 14 j dont **73 % vues une seule fois**, avec du non-entité
   dedans (« députés français », « ambassadeur français ») ; seules **2 324
   entités atteignent ≥ 5 mentions / 14 j** — c'est l'univers réellement
   suivable. Décision après mesure.

## PR0 — rendre la jauge exécutable

Détail complet dans le [runbook](./maintenance-feed-ranking-gauge.md). En bref :

- **Zéro migration** — `pillar_scores` n'est pas une colonne mais une clé JSON
  dans `daily_digest.items` (JSONB). Tout est additif.
- Dénominateur explicite `--denominator {all,engaged,engaged-loo}`, défaut
  `engaged-loo`, **les trois publiés côte à côte**.
- CTE `editorial_items` : `subjects[].actu_article` + `extra_actu_articles`, avec
  rang de sujet, libellé de sujet et **slot** (`actu` / `extra`).
- Persistance **forward-only** de `score` / `pillar_scores` sur le représentant
  scoré.
- Sorties `.json` + `.md` appariées et `--compare`, en miroir des harnais frères.

### Première lecture, et elle est parlante

30 j au 2026-07-29, dénominateur `engaged-loo`, slots `actu` :

| rang de sujet | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| CTR | **30,7 %** | 19,1 % | 19,7 % | 14,1 % | 19,7 % | 21,7 % | 19,7 % | 22,4 % | 19,1 % | 15,3 % |

(~220 slots par rang ⇒ **±5 pp à 95 %**.)

Deux constats, à confirmer sur une deuxième fenêtre :

1. **Le rang 1 se détache, le reste est plat.** Les rangs 2 à 10 tiennent tous
   dans la barre d'erreur autour de ~19 %. Le re-ranking per-user n'a **aucun
   pouvoir discriminant mesurable au-delà du rang 1** — et la jauge ne peut pas
   dire si l'avantage du rang 1 vient du ranking ou de la position à l'écran.
2. **Les `extra_actu_articles` sont un angle mort** : 11 085 slots livrés sur
   30 j (≈ 24 % du digest), **11 consommations**, jamais scorés.

Ces deux résultats pèsent lourd sur l'arbitrage : ils disent que le problème est
en amont du réglage fin, pas dans la finesse de la taxonomie.

## PR1 — rebrancher les signaux existants

**Zéro migration** : les 3 tables (`user_entity_affinity`, `user_interests`,
`user_topic_profiles`) ont déjà les colonnes. **4 commits indépendamment
révocables.**

### (a) Nourrir l'affinité entités depuis l'Essentiel

Ajouter `_adjust_entity_affinity` à côté de chaque `_adjust_subtopic_weights`
dans `digest_service.py` et `routers/contents.py`, **avec le même delta** —
c'est l'invariant tenu partout dans `content_service.py`. READ →
`READ_TOPIC_BOOST` (0,03), SAVE → `BOOKMARK_TOPIC_BOOST` (0,05), LIKE →
`LIKE_TOPIC_BOOST` (0,15), UNLIKE → `−LIKE_TOPIC_BOOST`.

`NOT_INTERESTED` est laissé seul (il route vers
`_trigger_personalization_mute`), mais **l'asymétrie est signalée au PO plutôt
que corrigée en silence** : `content_service.set_hide_status` applique bien
`DISMISS_TOPIC_PENALTY` aux entités.

### (b) Faire tirer les abonnements entités — le threading d'abord

1. **Bloquant** : ajouter `user_custom_topics` à `DigestContext` et le passer au
   `ScoringContext` de `digest_selector`. Sans ça, la garde de
   `_score_custom_topics` avale tout et le reste de (b) est un **no-op**.
2. Branche entité dans `_score_custom_topics`, en miroir de
   `layers/user_custom_topics.py` : comparer `tp.canonical_name` aux clés de
   `iter_entity_names` (`helpers/entities.py`, la primitive déjà partagée
   write/read). Multiplicateur `ENTITY_MATCH_MULTIPLIER = 1.5`.
3. **Réutilisation** : collapser le `_parse_content_entities` privé de
   `layers/user_custom_topics.py` sur l'helper partagé, dans le même commit.
4. **Point à surveiller** : `_score_entities` (affinité, cap
   `ENTITY_AFFINITY_MAX_BONUS = 30`) et cette branche (`25 × 1,5 × mult`) sont
   deux signaux distincts sur la même entité qui **s'empilent** dans un pilier
   capé à 160.
5. **Copy** : pour un profil entité, `topic_name` est un nom de personne ⇒ le
   label actuel rend « Votre sujet : Kylian Mbappé ». Le mobile dit déjà
   « Entité suivie ». **Décision PO avant merge** ; un label distinct exige un
   bras assorti dans `reason_builder.py`. Rappel : **pas d'em-dash** dans la copy
   user-facing.

> ⚠️ **Blast radius assumé** : threader `user_custom_topics` dans le digest
> active aussi la branche slug/keyword existante
> (`CUSTOM_TOPIC_BASE_BONUS = 25 × multiplier`), **effet plus large que la
> branche entités elle-même**, et rend `THEME_MISMATCH_MALUS = −8` atteignable
> pour les users custom-topics-only. ⇒ **commit séparé, run de jauge
> avant/après dédié.**

### (c) Decay de `user_interests.weight`

Cloner `decay_user_entity_affinity` en `decay_user_interest_weights()`, avec
`INTEREST_WEIGHT_DECAY = 0.98` posé **à côté** de `SUBTOPIC_DECAY` et
`ENTITY_AFFINITY_DECAY` dans `scoring_config.py` — une famille visible, pas une
constante orpheline.

Justification du 0,98 contre la distribution mesurée (724 lignes / 126 users ;
338 à 1,0 exactement ; 258 dans ]1,0 ; 1,5] ; 83 dans ]1,5 ; 3,0[ ; **32 au
cap** ; 15 sous 1,0 ; moyenne 1,260) : **demi-vie ≈ 34 j** sur l'excédent
au-dessus du neutre. Une ligne au cap redescend à 2,0 après ~34 j sans lecture,
alors qu'une lecture (+0,05) est rattrapée en ~2 j de lecture active. Ça vide les
32 lignes saturées — qui à elles seules pèsent 62 % du pilier — sans effacer le
profil d'un lecteur actif.

**Décision explicite** : 15 lignes sont **sous** 1,0 et produisent un malus. Un
decay symétrique les remonte vers le neutre et **efface ce signal négatif**.
Recommandation retenue : décayer dans les deux sens (cohérence avec les deux
sœurs) et l'écrire.

### (e) Deux défauts d'explicabilité

- **`SUBTOPIC_LABELS` désynchronisé de `VALID_TOPIC_SLUGS`** — mesuré :
  **50 labels pour 51 slugs valides, 32 clés fantômes, 33 slugs valides sans
  label** ⇒ `slug.capitalize()`. Ce sont des slugs très suivis qui tombent :
  sur le top 16 par nombre d'abonnés, **8 n'ont pas de label** — `energy` (83
  users) → « Energy », `politics` (75) → « Politics », `usa` (70) → « Usa »,
  `environment` (63) → « Environment », `inequality` (54) → « Inequality »,
  plus `justice`, `europe`, `tech`. Correctif : un edit de dict **et un test
  d'invariant** (`set(SUBTOPIC_LABELS) <= VALID_TOPIC_SLUGS` et tout slug valide
  a un label) pour que ça ne puisse plus dériver.
- **Branche morte de raison dans le digest** — `digest_selector.py:1682` teste
  `label.startswith("Sous-thème : ")` alors que le pilier émet
  `"Sujet suivi : "` / `"Sujet : "` ⇒ les raisons du digest retombent sur le
  thème large. Fix d'une ligne. **Change le texte de raison visible sur beaucoup
  d'articles** ⇒ commit séparé + screenshot + entrée `changelog.json`.

### (d) Ne PAS recalibrer ce cycle

Ni `ENTITY_AFFINITY_BASE` ni les deltas d'interaction — **un levier mesuré à la
fois** (cf. `maintenance-clustering-calibration.md`).

**Conséquence assumée** : la portée de (b) est plus mince que « 93 entités ×
30 users ». Mesuré sur 30 j, les abonnements entités matchent 1 945 articles
candidats (4,2 % d'un pool de 46 549) ⇒ ~6,8 candidats/j/user abonné pour ~10
slots, mais seulement **37 des 42 916 slots actu livrés** (0,086 %), 13 users.
⇒ **(b) n'est pas résoluble en une semaine sur le digest.** Le mesurer sur
**Tournée / Veille** (où `user_custom_topics` circule déjà) et traiter le digest
comme directionnel. Le 77 % mesurait le pool de candidats, pas le livré.

## Différé, avec critères de ré-entrée

Ni B ni D ne sont écartés sur le fond : ils sont **non-ordonnançables tant que
rien n'est mesurable**.

- **Lead A — fiabiliser le tagging.** Le socle a 3 couches de garde
  (`_on_task_done`, job santé 30 min à seuil 12 h, `/api/health/classification`).
  Deux trous connus subsistent : `MISTRAL_API_KEY` vide ⇒ la queue **draine** en
  écrivant `topics=[]` sans qu'aucune alerte ne parte (l'âge du pending reste
  bas), et la fuite `exhausted_retries` documentée comme cause du plafond de
  couverture ~68 %. **Pas de backfill des ~25k articles du blackout** (corpus
  périmé). → PR séparée, hors de ce cycle.
- **Lead B — granularité de la taxonomie.** Ré-entrée si la jauge montre que le
  **CTR par sujet est plat entre slugs larges et slugs spécifiques** — c'est-à-
  dire que la finesse manque vraiment. Deux prérequis structurels déjà
  identifiés : le classifieur ne voit que **titre + 200 caractères de
  description** ⇒ **plafond d'information avant plafond de taxonomie** ; et il
  n'y a **pas de colonne `classification_version`** ⇒ aucune migration de
  taxonomie pilotable (6 copies de la liste de slugs, dont `TOPIC_TO_THEME` non
  testée ⇒ `theme = NULL` silencieux).
- **Lead D — vecteurs.** La conviction « pas d'excellent sans vecteurs » n'est
  pas fausse, elle est **prématurée** : `pgvector` est *disponible* (0.8.0) mais
  `installed_version IS NULL` ⇒ c'est un `CREATE EXTENSION`, pas du gratuit ; et
  sans dénominateur fiable on ne peut pas prouver qu'un étage de recall
  vectoriel bat l'actuel. Ré-entrée quand PR0 donne une baseline CTR stable sur
  deux fenêtres. Cible naturelle : **recall user-vector + re-rank explicable**
  par-dessus les piliers, pas un remplacement.
- **Vocabulaire des entités** (73 % de singletons, non-entités, ~2 324 entités à
  ≥ 5 mentions) — décision après mesure, choix PO.

### Suivis adjacents identifiés, non traités

- `user_interest_states` est absent lui aussi du `ScoringContext` digest ⇒ le
  plancher FAVORITE (`_FAVORITE_WEIGHT_FLOOR`) ne s'applique pas au digest.
- Double-compte pré-existant subtopic ↔ custom-topic : l'onboarding miroite
  chaque `UserSubtopic` en `UserTopicProfile(keywords=[slug])`
  (`user_service.py`) ⇒ 45 + 18 + 25 points pour un seul signal.
- `_score_coverage` est inerte (`cluster_source_counts` jamais peuplé).
- `user_entity_preferences` est mort (0 ligne) ; le mute entité passe en réalité
  par `user_personalization.muted_topics`.
- **Les `extra_actu_articles`** : ~24 % des slots livrés, jamais scorés, CTR
  1,5 %. Soit on les score, soit on les réduit — mais les laisser tels quels,
  c'est laisser un quart du digest hors du système de reco.

## Vérification

```bash
# PR0
cd packages/api && PYTHONPATH=. pytest tests/scripts/test_evaluate_feed_ranking.py -q
cd packages/api && PYTHONPATH=. pytest tests/test_digest_per_user_projection.py \
  tests/test_digest_service.py tests/editorial -q
cd packages/api && PYTHONPATH=. python scripts/evaluate_feed_ranking.py --days 30
#   attendu : ~3 000 slots en engaged-loo, CTR global ~15 %, rang 1 nettement
#   au-dessus des rangs 2-10. Si 0 ligne : soit la branche editorial_v3 est
#   fausse, soit le rôle DB est bloqué par RLS (cf. runbook).

# PR1
cd packages/api && PYTHONPATH=. pytest tests/recommendation/test_pertinence_pillar.py \
  tests/test_digest_service.py tests/test_content_interactions.py \
  tests/workers/test_scheduler.py tests/test_digest_per_user_projection.py \
  tests/test_digest_selector.py -q

# suite complète (anticipe stop-verify-tests.sh)
cd packages/api && pytest -v
```

**Alembic** : aucune migration dans les deux PRs (vérifié : tout est JSON
additif ou colonnes existantes) ⇒ le risque expand-contract de la DB partagée
`main` / `production` ne s'applique pas ici. Confirmer `alembic heads` = 1 avant
PR par réflexe.

**UI** : PR0 est backend-only. PR1 (e) change du **texte de raison visible** ⇒
passage Playwright CLI sur la feuille « Pourquoi cet article ? » (skill
`facteur-qa-web`, viewport 390x844, sémantique activée) + screenshot, et une
entrée `changelog.json`. Pas de nouvelle UI.

## Risques

1. **(b) est un no-op sans le threading `DigestContext`** — l'item le plus sévère.
2. **Threader `user_custom_topics` active aussi la branche slug/keyword à 25 pts**
   dans le digest : effet plus large que l'objectif déclaré ⇒ commit isolé,
   jauge avant/après.
3. **`THEME_MISMATCH_MALUS = −8` devient atteignable** pour les users
   custom-topics-only.
4. **Puissance statistique** : ~3 000 slots LOO (~220/rang, ±5 pp à 95 %) ;
   **37 slots** entité-matchés ⇒ (b) directionnel sur le digest, mesurable sur
   Tournée / Veille.
5. **Persistance des scores forward-only** : bandes de score vides jusqu'à ~2
   semaines post-merge ; `extra_actu_articles` à `null` définitivement.
6. **`digest_completions` doit être rejeté par écrit** (0 ligne / 60 j **et**
   circulaire), sinon quelqu'un le re-proposera. C'est fait dans le runbook et
   dans l'en-tête du rapport généré.
