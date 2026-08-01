# Maintenance — le clustering « Actus du jour » voit le corpus complet

**Date** : 2026-08-01
**Branche** : `claude/clustering-actus-verification-yz5jbl`
**Type** : Maintenance (correctif de périmètre, sans DDL ni migration)
**Amont** : [`bug-clustering-actus-du-jour-fragmentation.md`](../bugs/bug-clustering-actus-du-jour-fragmentation.md)
(diagnostic) · [`bug-clustering-actus-du-jour-verification.md`](../bugs/bug-clustering-actus-du-jour-verification.md)
(contre-mesures)

> **Si tu reprends ce chantier, lis d'abord le §6.** Il liste ce qui reste faux,
> ce que je n'ai pas mesuré, et les arbitrages produits que j'ai tranchés seul et
> qui méritent d'être rediscutés.

---

## 1. Le problème en une phrase

La section promet « les sujets les + couverts en France », mais le regroupement qui
produit ce classement ne voyait que **les 200 articles les plus récents** — soit
**10,5 % du corpus 24 h**, sur une fenêtre de **1,7 à 2,9 h en journée**, issus de
**64 médias sur 192**. Un sujet couvert par 18 médias dans la journée n'en montrait
que 2 ou 3, et les deux plus gros sujets du jour n'atteignaient jamais la section.

Le plafond n'achetait pas de la latence — **le clustering coûte 0,45 s pour 2 200
articles**. Il achetait de la cécité.

## 2. Pourquoi le correctif précédent (#1044) n'a pas suffi

#1044 a livré deux lots. Ils ont eu un sort opposé, ce que le document d'origine ne
disait pas :

| Lot | Contenu | État réel |
|---|---|---|
| **A** | `TopicSelector._clusters_from_global()` — projeter les candidats du user sur les clusters globaux | **Code mort.** `_get_user_digest_format()` renvoie `"editorial"` sans condition ⇒ la branche `output_format == "topics"` est inatteignable. Vérifié en base : **1 765 digests sur 7 jours, 100 % `editorial_v3`, 0 `topics_v1`.** |
| **B** | `briefing/topic_clustering.py` — cosinus IDF + agglomératif par centroïde | **Actif.** `editorial/pipeline.py:180` appelle `ImportanceDetector()` sans argument, donc le défaut passé de Jaccard 0,4 à cosinus 0,30 s'applique. |

Le Lot A visait le bon levier (« le regroupement global fait autorité ») mais l'a
branché sur la branche morte de l'arbre d'appel. **Ce correctif-ci applique le même
principe au chemin vivant.**

## 3. Ce qui change

Tout tient dans un module de politique, [`app/services/editorial/candidate_pool.py`](../../packages/api/app/services/editorial/candidate_pool.py),
et ses deux appelants.

### 3.1 Le pool devient le corpus de la fenêtre

| | Avant | Après |
|---|---|---|
| Sélection | 200 plus récents (+ 200 sources suivies) | **tout le corpus de la fenêtre** |
| Fenêtre de regroupement | 48 h nominale, **1,7–2,9 h réelle** | **échelle 24 → 48 → 168 h** |
| Borne | `LIMIT 200` (plafond) | `LIMIT 6000` (sécurité mémoire, jamais atteinte) |
| Pool maigre | — | on descend l'échelle jusqu'à **200** articles utiles |

Le **200 historique devient un plancher** : il ne coupe plus le corpus, il détecte
un pool anormalement maigre et fait descendre d'un barreau plutôt que de servir un
digest famélique.

**Pourquoi une échelle et pas une fenêtre unique.** Les deux modes n'ont pas du tout
la même densité, et c'est ce qui a failli passer inaperçu :

| Mode | 24 h | 48 h | 168 h |
|---|---|---|---|
| `pour_vous` | ~2 000 | — | — |
| `serein` (hard-filtré `is_good_news`) | **13** | **33** | **145** |

Une fenêtre nominale de 24 h avec un repli unique à 48 h aurait amputé
« Bonnes Nouvelles » de **77 % de sa matière** (145 → 33) sur le chemin on-demand,
qui lisait jusqu'ici 168 h. L'échelle fait descendre `serein` jusqu'au dernier
barreau et restitue exactement son comportement historique, sans élargir
`pour_vous` d'une heure.

**Pourquoi 24 h en nominal.** « Actus du jour » est un produit quotidien : un sujet
se définit dans la journée. À 48 h, les articles de la veille se raccrochent à ceux
du jour — observé sur les bulletins radio, qui formaient un cluster à cheval sur
3 jours. Mesuré avant de trancher : passer de 48 h à 24 h coûte **44 articles issus
de 27 sources** qui n'ont rien publié dans les dernières 24 h. Ces 27 sources
restent couvertes par la tranche « sources suivies » (ci-dessous).

**La tranche « sources suivies » (P1) ne couvre plus que le créneau que la fenêtre
n'atteint pas** — `[now-48 h, now-24 h]` au lieu de `[now-48 h, now]`. Depuis que le
pool nominal est exhaustif sur sa fenêtre, la requêter à nouveau sur `[0, 24 h]` ne
rendait que des articles déjà présents : ils consommaient le `LIMIT 200` avant qu'un
seul article de niche plus ancien n'y entre — l'exact inverse du but de la tranche.
La garantie P1 était donc **cassée par la première version de ce correctif**, sans
qu'aucun test ne le voie.

### 3.2 Deux exclusions d'entrée

- **Articles post-datés** (`published_at <= now()`). 19 articles portaient une date
  RSS future ; le pool étant trié par récence décroissante, ils occupaient en
  permanence 19 des 200 places.
- **Bulletins et chroniques régulières** (`drop_unclusterable`). « JOURNAL DE 8H du
  jeudi… », « Le journal RTL de 6h… » partagent un **gabarit**, pas un sujet.
  Élargir le pool les fait se regrouper entre eux : avant ce filtre, un cluster de
  **20 bulletins / 3 médias** comptait comme un sujet du jour et remontait dans le
  top curé par le LLM.

  `pipeline._is_non_actu_cluster` existait déjà, mais exige que **tous** les contenus
  du cluster soient des bulletins — un seul intrus (« Ce soir à la télé : notre
  sélection ») sauvait le cluster entier. On traite ici la cause : un bulletin
  n'entre pas dans le calcul. Il reste consultable ailleurs dans l'app ; c'est un
  filtre d'entrée du regroupement, pas une suppression de contenu.

  **Taux de faux positifs mesuré** sur les 4 399 titres de production du corpus figé :
  **39 titres écartés (0,9 %)**, dont **38 bulletins authentiques**. Le seul cas
  discutable est une enquête en série (« … (2/3) »), qui n'est pas de l'actu chaude
  non plus. Le risque théorique existe (`^le journal\b` attraperait « Le journal
  Libération racheté par un fonds ») mais ne s'est pas matérialisé sur 24 h de
  production ; il est à re-mesurer si `NEWS_BULLETIN_PATTERNS` s'élargit.

### 3.3 Les deux chemins voient enfin le même corpus

Le chemin batch (`digest_generation_job._get_global_candidates`) et le chemin
on-demand (`digest_selector._fetch_editorial_global_pool`) construisaient chacun
leur pool. Ils avaient **divergé** : le chemin on-demand n'appliquait pas
`apply_ad_filter`, donc les articles `is_ad=True` entraient dans son clustering.
Les deux passent désormais par `build_editorial_pool_stmt`. Sans cela, un même
sujet n'affiche pas le même nombre de médias selon que le digest vient du batch ou
d'un recalcul à la demande.

## 4. Résultats mesurés

Sur corpus de production réel (2026-07-30 05:00 → 2026-08-01 00:00 UTC, 4 380
articles non post-datés), en important le code de production — **aucun proxy SQL,
aucune réimplémentation**.

### 4.1 Le pool

| | Avant | Après |
|---|---|---|
| Articles | 246 | **2 332** |
| Médias | 64 | **192** |
| Part du corpus 24 h | 10,5 % | **99,2 %** |
| Fenêtre réelle | 7,5 h (2,0 h en journée) | **24,0 h** |

### 4.2 Le KPI produit — sujets couverts par ≥ 3 médias

Algorithme identique des deux côtés : **seul le pool change**.

| Heure de génération | KPI avant | KPI après | |
|---|---|---|---|
| 05:00 UTC (cron 07:00 Paris) | 4 | **82** | ×20 |
| 08:00 | 6 | 71 | ×12 |
| 11:00 | 4 | 65 | ×16 |
| 14:00 | 4 | 64 | ×16 |
| 17:00 | 3 | 51 | ×17 |
| 20:00 | 8 | 54 | ×7 |

### 4.3 Les sujets de référence du diagnostic

| Sujet | Avant | Après | Cible §6 du diagnostic |
|---|---|---|---|
| Ceuta | 2 médias | **9 médias** (19 art.) | ≥ 6 ✅ |
| Gironde | 3 médias | 4 médias (7 art.) | ≥ 6 ❌ |

### 4.4 Ce que la curation LLM voit réellement

C'est **la vue produit** : `curation.select_topics` trie par nombre de médias et
tronque à `cluster_input_limit = 15`, puis le digest en retient 5. Le KPI global
n'est qu'un indicateur ; c'est ce top 15 que l'utilisateur finit par lire.

| Rang | Avant | Après |
|---|---|---|
| 1 | 7 méd. — Trêve à Gaza / désarmement Hamas | 12 méd. — FIFA : l'UEFA menace de boycotter la Coupe du monde |
| 2 | 4 méd. — Anthropic AI hacked three companies | 12 méd. — Xenia Fedorova visée par un arrêté d'expulsion |
| 3 | 3 méd. — Incendie en Gironde | 9 méd. — Croissance française à 0,2 % au 2ᵉ trimestre |
| 4 | 3 méd. — Avalanche au Pakistan | 9 méd. — Attal débouté face à Le Pen sur « renaissance » |
| 5 | **2 méd. — « Le journal RTL de 6h du 31 juillet »** | 8 méd. — Ceuta : l'Italie veut suspendre l'Espagne de Schengen |
| … | rangs 12-15 à **1 média**, dont **« Mattress Firm Coupons: Save up to $700 »** | rang 15 encore à **5 médias** |

Avant, la curation choisissait 5 sujets dans une liste dont la moitié basse était
du bruit à 1 média. Après, **les 15 candidats sont tous des sujets réellement
couverts**, de 5 à 12 médias.

### 4.5 Coût

| | Valeur |
|---|---|
| Clustering | 0,45 s pour 2 200 articles (1,4 s pour 4 400) |
| Fréquence | 2× par batch (`pour_vous` + `serein`), puis servi depuis le cache |
| Appels LLM | **inchangés** — `cluster_input_limit = 15` borne l'entrée de la curation quelle que soit la taille du pool |
| Suite de tests | 2 804 passed, 30 skipped (2 790 avant, +14 nouveaux) |

## 5. Où regarder en prod

```
digest_generation_global_pool_built       mode, window_hours, pool_size, source_count,
                                          dropped_unclusterable   (chemin batch)
digest_selector_global_pool_built         idem, chemin on-demand
editorial_pool_ladder_exhausted           aucun barreau n'atteint le plancher — normal
                                          pour `serein`, anormal pour `pour_vous`
editorial_pool_truncated                  ⚠ plafond 6 000 atteint = anomalie d'ingestion
digest_generation_followed_slice_skipped  fenêtre ≥ hours_lookback : tranche P1 sans objet
global_trending_context_built             topics_3_plus_media = le KPI
editorial_pipeline.clusters_built         nombre de clusters soumis à la curation
```

Les événements `editorial_pool_*` sont émis par `candidate_pool`, donc **communs aux
deux chemins** — le `mode` les distingue, pas le nom.

Signal de bonne santé attendu : `pool_size` ≈ 2 000-2 500 et `source_count` ≈ 190 en
`pour_vous` ; `pool_size` ≈ 150 en `serein` avec `editorial_pool_ladder_exhausted`
à chaque run (attendu — le mode n'a jamais 200 bonnes nouvelles). Un `pool_size`
`pour_vous` retombé à ~200 signifie que l'ingestion a un problème.

`topics_3_plus_media` doit se situer entre 50 et 85 en régime normal.

## 6. Pour le prochain agent — ce qui reste ouvert

### 6.1 Arbitrages que j'ai tranchés seul

1. **Échelle `[24, 48, 168]`.** Le premier barreau est choisi pour la cohérence
   produit (§3.1) ; les suivants existent pour `serein`. Si la promesse devient
   « les sujets de la semaine », ce choix est à refaire — et il faudra alors un
   decay temporel, sinon les clusters se mettront à cheval sur plusieurs jours.
   Le plancher (200) arbitre entre les barreaux : le monter ferait descendre
   `pour_vous` à 48 h les jours creux.
2. **Bulletins exclus à l'entrée** plutôt que filtrés au niveau cluster. Plus radical,
   mais traite la cause. Un faux positif de `NEWS_BULLETIN_PATTERNS` fait maintenant
   disparaître un article du regroupement — les patterns sont partagés avec
   `essentiel_service` et l'`actu_matcher`, donc y toucher a une portée large.
3. **Plancher à 200.** Valeur reprise de l'ancien plafond, pas mesurée. Si le
   ré-élargissement se déclenche souvent en prod (cf. log), c'est ce nombre qu'il
   faut revoir en premier.

### 6.2 Ce qui reste faux ou non résolu

1. **Gironde n'est toujours pas résolu** : 4 médias au mieux, cible ≥ 6, toujours
   éclaté sur ~91 clusters. Les facettes (« les mécanos au front », « des obus ont
   explosé », « la radio Ici Gironde mobilisée ») ne partagent aucun vocabulaire.
   **Aucun réglage lexical ne franchira ce plafond** (R ≈ 0,44 mesuré au banc B³).
   Seule voie : une représentation sémantique — protocole au §7.6 du diagnostic
   (embeddings Mistral, critère B³ R > 0,70 à P ≥ 0,95). `huggingface.co` est bloqué
   par la politique d'egress ; le test n'a jamais pu tourner. **Ne pas engager
   `pgvector` avant d'avoir cette mesure.**
2. **La précision du clustering est de 0,94, pas 1,00.** Audit des 81 clusters ≥ 3
   médias : 5 défectueux (fusion « data centers » de 3 sujets distincts, promo/test
   Galaxy Watch, 3 titres-citations sans sujet commun, 2 affaires Le Pen + une
   interview, et le cluster de bulletins — ce dernier corrigé ici). Le `P = 1,00`
   annoncé était mesuré sur 63 articles annotés, où ces familles n'existent pas.
3. **Le seuil 0,30 est plus près du précipice que la doc ne le dit.** Mesuré sur
   2 351 articles : la falaise de chaînage est **entre 0,28 et 0,25** (plus gros
   cluster : 23 → 93 articles). Le commentaire de `TOPIC_CLUSTER_COSINE_THRESHOLD`
   dit « en dessous de 0,25 » — c'est optimiste de deux crans. **Ne pas baisser ce
   seuil sans rejouer `verify_clustering_side_effects.py`.**
4. **`bench_clustering_bcubed.py` ne contient pas l'algorithme livré** : il utilise
   une liaison *moyenne* et un IDF non lissé. Il ne peut pas reproduire la ligne
   « centroïde » du §8 du diagnostic. Tant qu'il n'a pas de variante centroïde, le
   Lot C (observabilité) démarre en dette.

### 6.3 Pistes non explorées, par rendement estimé

1. **`trending_context` est calculé puis jeté.** `digest_selector.py:317-339` lance
   un `build_topic_clusters()` sur tout le corpus 24 h **avant** l'aiguillage de
   format ; la branche éditoriale `return` sans jamais le lire. C'est aujourd'hui du
   travail pur perte à chaque batch. Deux issues : le rendre paresseux
   (`if output_format != "editorial"`), ou — mieux — **fusionner les deux calculs**,
   puisque ce correctif fait maintenant clusteriser le même corpus deux fois.
   C'est le prochain gain évident, et il est purement mécanique.
2. **Dédoublonnage intra-source.** Jamais implémenté (§4.1 du diagnostic). BFMTV
   publie ~45 titres-citations quasi dupliqués sur un même sujet. Garder le meilleur
   article par source et par sujet assainirait `source_domains`, dont dépend
   directement la pastille « N sources ».
3. **`Content.entities` comme signal de *blocage*.** L'inverse de la piste écartée :
   au lieu de fusionner sur entité partagée (régression « Texas »), **interdire** la
   fusion quand deux clusters portent des entités nommées disjointes. Viserait
   exactement les défauts de précision du §6.2.2 sans coûter de rappel. Les entités
   sont peuplées à 72 % et ne servent aujourd'hui qu'à *nommer* un carrousel.
4. **Clustering incrémental et persistance.** Tout est recalculé à chaque cycle ;
   `contents.cluster_id` n'est écrit que pour les rares sujets retenus (11 lignes sur
   2 205). Sans persistance, impossible de suivre un sujet dans le temps ou de
   mesurer une régression. ⚠ **DB partagée** : `contents.cluster_id` est lu par
   `title_annotation_service` et écrit par la pipeline éditoriale ; y toucher depuis
   `main` change le comportement du backend `production` pendant une semaine.
   Expand-contract obligatoire, PR dédiée.
5. **Effets de bord aval non recalibrés.** Le nombre d'articles marqués
   `is_trending` passe de 91 à 453 (3,9 % → 19,3 % du corpus). Conséquences non
   traitées ici : `/feed/trending` (`routers/feed.py:811`) passe de ~22 à ~81 sujets,
   et `essentiel_service._W_TRENDING = 50` perd son pouvoir discriminant quand un
   cinquième du corpus est trending. **À revoir avant de toucher au seuil.**

### 6.4 Effets induits traités ici (et pourquoi)

Élargir le pool a des conséquences en dehors du digest, parce que
`EditorialGlobalContext.cluster_data` sérialise **tous** les clusters et passe de
~200 à ~2 350 contenus. Un consommateur en dépendait :

- **`grille_selector._build_cluster_index`** n'indexe plus que les clusters
  **multi-articles**. Le bonus `+2` qu'il alimente récompense l'appartenance à un
  *sujet* ; avec les singletons indexés, la quasi-totalité des candidats y avait
  droit — le bonus devenait une constante, donc sans effet sur le classement. La
  distinction était implicite tant que `cluster_data` ne couvrait que 200 articles.

### 6.5 Findings de revue écartés, avec la raison

- **`defer(Content.html_content)` sur la requête de pool.** Suggéré pour alléger le
  transfert. Mesuré : `html_content` pèse **699 kB sur 24 h** (1 kB/article), pas les
  mégaoctets supposés. Le gain est réel mais faible, alors qu'un `defer` sur des
  objets réhydratés puis re-sérialisés fait crasher tout accès tardif en contexte
  async (`MissingGreenlet`). Mauvais rapport risque/gain — non appliqué.
- **Ré-élargissement en « delta » plutôt qu'en requête complète.** L'échelle
  re-requête toute la fenêtre à chaque barreau au lieu de ne chercher que
  l'incrément. C'est deux à trois requêtes au lieu d'une, uniquement sur les modes
  clairsemés. La version « delta + fusion » complique la boucle pour un gain qui ne
  se paie que là — non appliqué, mais c'est le premier endroit à regarder si le
  chemin on-demand `serein` devient chaud.
- **Coût CPU superlinéaire de `cluster_documents` au plafond.** Un banc synthétique
  à forte densité de tokens donne ~O(n²) (11 s à n=2 400, 77 s à n=6 000). Sur des
  titres réels, la mesure est de **0,45 s pour 2 214 articles** — trois ordres de
  grandeur d'écart, le corpus réel est creux. `EDITORIAL_CLUSTERING_MAX_ARTICLES`
  borne donc la mémoire, pas le CPU : si l'ingestion double durablement, re-mesurer
  avant de relever ce plafond.

### 6.6 Ce que j'ai délibérément laissé de côté

- Étendre le filtre bulletins aux **autres** consommateurs du clustering
  (`routers/feed.py`, `article_clustering_service`, `recommendation_service`). Ce
  serait cohérent, mais ces surfaces sont vivantes et je n'ai pas mesuré l'impact.
- Supprimer le Lot A mort. Il ne coûte rien à l'exécution ; le supprimer ou le
  brancher est une décision produit, pas une urgence technique.

## 7. Reproduction

```bash
# Mesure avant/après sur les deux chemins + audit de chaînage
python3.12 docs/qa/scripts/verify_clustering_prod_paths.py   <corpus.json> [followed_ids]
# Vue curation LLM, robustesse horaire, sensibilité au seuil, effets de bord
python3.12 docs/qa/scripts/verify_clustering_side_effects.py <corpus.json> [followed_ids]
```

Les deux scripts importent `app/services/briefing/topic_clustering.py` tel quel et
rejouent l'algorithme antérieur extrait de `beac381e`. `editorial_pool_v2()` réplique
la politique de `candidate_pool.py` — **si tu modifies l'une, mets l'autre à jour**,
sinon les mesures cessent de décrire la production.

Le corpus est un export production `{p, d, s, a, t}` = published_at, domaine,
source_id, type de source, titre. Extraction via MCP Supabase (psql prod est bloqué) ;
les résultats > ~190 k caractères sont écrits sur disque au lieu d'être renvoyés,
donc paginer (`LIMIT 700`) et parser les fichiers.

### Pièges d'environnement

| Piège | Détail |
|---|---|
| `staging` ≠ `main` | `staging` est ~746 commits derrière `main` et c'est la branche par défaut du repo. Vérifier : `git rev-list --left-right --count HEAD...origin/main`. |
| Python 3.12 | Le `python3` du conteneur est 3.11. Utiliser `python3.12` / `uv venv --python 3.12`. |
| Postgres sur 54322 | Absent au démarrage ⇒ des dizaines de faux échecs. `initdb` refuse de tourner en root : passer par `su postgres` et un `PGDATA` hors du scratchpad (`/var/lib/postgresql/…`). |
| `PYTHONPATH=.` | Sans lui, `tests/conftest.py` échoue sur `ModuleNotFoundError: No module named 'app'`. |
| Hôtes bloqués | `huggingface.co` → 403 au CONNECT. Ne pas contourner. |
