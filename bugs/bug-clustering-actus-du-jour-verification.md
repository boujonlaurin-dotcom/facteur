# Vérification adversariale — clustering « Actus du jour »

**Date** : 2026-08-01
**Branche** : `claude/clustering-actus-verification-yz5jbl` (rebasée sur `main`)
**Objet** : contre-expertise du diagnostic et du correctif livrés dans
`bug-clustering-actus-du-jour-fragmentation.md` (PR #1044).
**Posture** : aucun chiffre de l'analyse précédente n'a été repris. Tout ce qui est
chiffré ici a été remesuré, sur données de production, en important le code livré.

> **Correction de périmètre, à lire en premier.** La PR #1044, dont le titre est
> `docs(bug): …`, a **squashé le code avec la documentation**. `topic_clustering.py`,
> le nouveau seuil et la projection `TopicSelector` sont **déjà sur `main`**. Il ne
> s'agit donc pas d'une revue avant merge mais d'un **constat post-déploiement**.

---

## 0. Verdict en une page

| Question | Réponse mesurée |
|---|---|
| Le gain est-il « drastique » ? | **Sur le chemin réellement emprunté : non.** 2 → 4 sujets à ≥ 3 médias. Sur le corpus complet (jamais atteint) : 22 → 81, soit ×3,7. |
| Le Lot A sert-il en prod ? | **Non — code mort, prouvé.** 1 765 digests sur 7 jours, 100 % `editorial_v3`, 0 `topics_v1`. |
| Le Lot B sert-il en prod ? | **Oui.** C'est l'affirmation n°1 du brief qui est trop pessimiste : le chemin éditorial passe bien par `build_topic_clusters`. |
| La pastille « N sources » a-t-elle bougé ? | **Oui**, contrairement à l'hypothèse du brief : 2/3/3/1/2 → 7/4/3/2/3. Mais elle sous-compte toujours (7 au lieu de 12 réels). |
| Le doublon Gaza de la capture est-il corrigé ? | **Oui**, reproduit et vérifié : deux clusters à 3 et 3 sources fusionnent en un seul à 7. |
| Ceuta ? | **Résolu** sur corpus complet (19 art. / 9 médias), **pas dans le pool de prod** (2 médias). |
| Gironde ? | **Non résolu.** 7 art. / 4 médias au mieux, cible ≥ 6. Toujours éclaté sur 91 clusters. |
| Précision à l'échelle ? | **0,94, pas 1,00.** 5 clusters défectueux sur 81, audités un par un. |
| Suite de tests | **2 790 passed, 30 skipped** — vérifié, le chiffre est exact. |

**Le correctif est réel et bien construit. Il est étranglé par un `LIMIT 200` qui n'a
pas été touché.** L'ordre de priorité du plan révisé (§7.7 du diagnostic) désignait le
bon levier dominant — mais le lot livré sous le nom « Lot A » corrige ce levier **sur
la branche morte** de l'arbre d'appel.

---

## 1. §3.1 — Le Lot A ne sert à rien en prod, et c'est pire que ça

### 1.1 Preuve que le chemin `topics` est mort

```python
# app/services/digest_service.py:3052-3059
async def _get_user_digest_format(self, user_id: UUID) -> str:
    """Legacy note: … All users now receive the same editorial format."""
    return "editorial"
```

Aucun paramètre, aucun flag, aucune table. `effective_format` (`digest_service.py:866`)
en dérive directement, et le batch code en dur `output_format="editorial"`
(`digest_generation_job.py:983`). La branche `if output_format == "topics"`
(`digest_selector.py:518`) est donc inatteignable.

Confirmation en base, sur les 7 derniers jours :

| `format_version` | digests |
|---|---|
| `editorial_v3` | **1 765** |
| `topics_v1` | **0** |

`TopicSelector.select_topics_for_user` n'a qu'un seul appelant
(`digest_selector.py:523`), dans cette branche morte. **`_clusters_from_global()` — le
cœur du Lot A — n'a aucun appelant vivant.**

### 1.2 Le corollaire coûteux, non signalé jusqu'ici

`digest_selector.py:317-339` calcule `trending_context` **avant** l'aiguillage de
format. Ce calcul est un `build_topic_clusters()` sur **tout le corpus 24 h**
(`_build_global_trending_context`, ligne 1890 : `select(Content).where(published_at >=
now-24h)` — 2 351 articles mesurés).

Puis la branche éditoriale (ligne 371) `return` sans jamais lire `trending_context` :
`_project_editorial_for_user` ne le reçoit pas. **Le clustering global est calculé à
chaque batch puis jeté.** Le Lot A a ajouté deux champs (`cluster_by_content`,
`cluster_source_domains`) à un objet que le seul chemin vivant n'ouvre pas.

### 1.3 Ce que le brief sous-estime : le Lot B, lui, est bien en production

`editorial/pipeline.py:179-180` :

```python
detector = ImportanceDetector()
clusters = detector.build_topic_clusters(contents)
```

Sans argument → le **défaut** de `__init__` s'applique, et le correctif l'a fait passer
de `0.4` (Jaccard) à `0.30` (cosinus IDF). Le nouveau cœur de clustering est donc
**intégralement actif sur le chemin éditorial**. C'est la nuance décisive :

> **Lot A = mort. Lot B = vivant. Les deux ont été livrés ensemble et présentés comme
> un tout ; leur sort en production est opposé.**

Détail associé, qui invalide une constante de la table du diagnostic : la ligne de base
du chemin vivant était **Jaccard 0,40**, pas 0,45. `TOPIC_CLUSTER_THRESHOLD = 0.45`
n'était passé explicitement que par `TopicSelector` — la branche morte. Tous les
« avant » du document d'origine mesurent donc un seuil que le chemin vivant n'a jamais
utilisé.

### 1.4 Le vrai facteur limitant, mesuré

`digest_generation_job._get_global_candidates` : `ORDER BY published_at DESC LIMIT 200`,
plus une tranche `FOLLOWED_SLICE_LIMIT = 200` sur les sources suivies.

Mesuré à l'heure exacte du cron (`DIGEST_CRON_HOUR_PARIS = 7` → 05:00 UTC) :

| | valeur |
|---|---|
| Pool éditorial effectif (union des deux tranches) | **246 articles** |
| Corpus 24 h à la même seconde | 2 351 articles |
| **Part du corpus vue par le clustering** | **10,5 %** |
| Médias présents dans le pool | 64 sur **192** |
| Fenêtre temporelle réelle du pool | **7,5 h** (sur 48 h autorisées) |

La fenêtre de 7,5 h à 05:00 est l'effet du creux nocturne. En journée, le débit
d'articles la comprime :

| Heure UTC | Pool | Médias | Fenêtre réelle |
|---|---|---|---|
| 08:00 | 221 | 48 | **2,0 h** |
| 11:00 | 264 | 59 | **1,8 h** |
| 14:00 | 238 | 67 | **2,0 h** |
| 17:00 | 242 | 72 | **1,7 h** |
| 20:00 | 253 | 52 | 2,9 h |

**L'estimation « ~2 h » du brief est confirmée** pour toute génération diurne (recalcul
à la demande, cache miss). Le batch de 05:00 bénéficie du creux nocturne et atteint
7,5 h — mais cela signifie qu'il **ne voit aucun article publié avant 21:32 la veille**,
c'est-à-dire toute la journée éditoriale précédente.

### 1.5 Gain réel, chemin par chemin

KPI = nombre de sujets couverts par ≥ 3 médias distincts (après fold agrégateurs),
mesuré en important `app/services/briefing/topic_clustering.py` et en rejouant
l'algorithme antérieur extrait de `beac381e`.

| | AVANT (Jaccard 0,40) | APRÈS (cosinus 0,30) | |
|---|---|---|---|
| **Chemin éditorial — pool réel 246 art.** | **2** | **4** | **+2** |
| Corpus complet 24 h — 2 351 art. | 22 | **81** | ×3,7 |

Sur les six heures de génération testées, le delta du chemin éditorial est **+2, +3, +2,
+2, +2, +5**. Le gain est réel et systématique, mais il se compte en unités, pas en
ordres de grandeur — parce que le pool plafonne à 10 % du corpus.

**Reproduction** : `python3.12 docs/qa/scripts/verify_clustering_prod_paths.py <corpus.json>`

---

## 2. La pastille « N sources » — l'hypothèse du brief est fausse, la conclusion tient

Le brief supposait que la pastille venait de `perspective_count` / `PerspectiveService`.
La chaîne réelle est :

```
curation.py:44        source_count = len(cluster.source_domains)   ← clustering éditorial
digest_service.py:2452  source_count=subject.get("source_count", 0)
flux_continu_models.dart:251  sourceCount: json['source_count']
coverage_chip.dart:64   Text(sourceCount > 1 ? '$sourceCount sources' : '1 source')
```

`perspective_count` existe et transite, mais **la pastille lit `source_count`**. Elle est
donc bel et bien alimentée par le clustering, et le Lot B l'améliore.

Mesuré sur le pool éditorial réel, pastilles des 5 premiers sujets :

| | pastilles |
|---|---|
| AVANT | `2 src` · **`3 src`** · **`3 src`** · `1 src` · `2 src` |
| APRÈS | **`7 src`** · `4 src` · `3 src` · `2 src` · `3 src` |

Les deux `3 src` de la ligne AVANT sont **les deux cartes Gaza de la capture
utilisateur** — le doublon (A) du diagnostic, reproduit à l'identique. Après correctif
elles fusionnent en un seul sujet à 7 sources. **Le symptôme visible est corrigé.**

Mais la valeur reste fausse en tant que mesure de couverture nationale. Sur le corpus
24 h complet, ces mêmes sujets valent :

| Sujet | Pastille affichée | Couverture réelle 24 h |
|---|---|---|
| FIFA / boycott UEFA | absent du pool | **12 médias** |
| Xenia Fedorova | absent du pool | **12 médias** |
| Ceuta | 2 médias | **9 médias** |
| Gaza / désarmement Hamas | 7 médias | 7 médias |

**Verdict** : la pastille n'est plus fausse par fragmentation, elle reste fausse par
troncature du pool. « Les sujets les + couverts en France » désigne toujours « les
sujets les plus couverts dans les 2 dernières heures, vus par 1/3 des médias ».

---

## 3. Le seuil 0,30 — calibration circulaire confirmée, et marge plus étroite qu'annoncée

### 3.1 Le banc d'essai livré ne contient pas l'algorithme livré

`docs/qa/scripts/bench_clustering_bcubed.py` :

- son `cos_idf` utilise un IDF **non lissé** (`log(N/df)`) à partir d'un fichier de DF
  figé, là où `topic_clustering.compute_idf` lisse (`log((1+N)/(1+df))+1`) et calcule
  l'IDF **sur le corpus local** ;
- il applique une **liaison moyenne** (`agglo(..., linkage="average")`), là où le module
  livré applique une **liaison par centroïde** — la note d'implémentation du §8 dit
  explicitement que la liaison moyenne a été *essayée puis écartée* ;
- il n'expose aucune variante centroïde.

Exécuté tel quel :

```
Cosinus IDF 0.3, liaison moyenne     B³ P=1.00 R=0.40 F1=0.58 | Ceuta  4 méd. | Gironde 1 méd.
```

Le tableau « Résultats mesurés » du §8 annonce `R = 0.47`, `Ceuta 9 médias` pour le
seuil 0,30. **Le harness commité ne peut pas produire cette ligne.** Le chiffre provient
d'un code non versionné. Il n'est pas nécessairement faux — mon propre relevé sur corpus
complet donne bien Ceuta à 9 médias — mais il n'est **pas reproductible en l'état**, ce
qui est le défaut que le Lot C (observabilité) était censé fermer.

### 3.2 Circularité

Le corpus annoté fait 63 articles dont 21 Ceuta, **tous porteurs du mot « ceuta » dans
le titre**. Ce corpus a servi à choisir le seuil *et* à valider le seuil. La commentaire
de `TOPIC_CLUSTER_COSINE_THRESHOLD` cite ce même corpus comme justification.

### 3.3 Sensibilité remesurée sur 2 351 articles réels

| Seuil | Sujets ≥ 3 méd. | Art. trending | Ceuta méd. | Gironde méd. | **Plus gros cluster** |
|---|---|---|---|---|---|
| 0,22 | 107 | 773 | 13 | 15 | **118 art.** ⚠ |
| 0,25 | 97 | 650 | 12 | 14 | **93 art.** ⚠ |
| 0,28 | 85 | 501 | 9 | 4 | 23 art. |
| **0,30 (livré)** | **81** | **453** | **9** | **4** | **22 art.** |
| 0,32 | 75 | 401 | 9 | 4 | 21 art. |
| 0,35 | 69 | 357 | 6 | 4 | 21 art. |
| 0,40 | 53 | 266 | 6 | 4 | 20 art. |

La falaise de chaînage est **entre 0,28 et 0,25** : le plus gros cluster passe de 23 à
93 articles. Le commentaire du code dit « en dessous de 0,25 la précision décroche » —
la mesure montre que **le décrochage est déjà consommé à 0,25**. La marge sous le seuil
livré est de **0,02**, pas de 0,05.

Les gains apparents de Ceuta (13) et Gironde (15) à 0,22 sont des artefacts : ils sont
absorbés par le cluster géant de 118 articles, pas correctement regroupés.

**Conclusion nuancée** : 0,30 est un choix défendable — il est sur le plateau stable
0,28–0,35 — mais il est plus près du précipice que la documentation ne le laisse croire,
et il n'a jamais été validé sur autre chose qu'un corpus d'un seul jour.

---

## 4. Le « 32 → 79 » — provenance invalide, chiffre conservateur

Confirmé : le « 32 » et le « 79 » du §7.2 sont des **composantes connexes d'un graphe de
paires**, c'est-à-dire une **liaison simple**, obtenue par proxy SQL. Ce n'est ni
l'algorithme d'avant (glouton, sac fusionné) ni celui d'après (centroïde). À ne pas
citer comme résultat du code livré.

Mesure réelle, code contre code, sur le corpus complet 24 h :

| Base de comparaison | Sujets ≥ 3 médias |
|---|---|
| Jaccard 0,45 glouton (le seuil du chemin mort) | **17** |
| Jaccard 0,40 glouton (**le vrai défaut de prod**) | **22** |
| Proxy composantes connexes 0,45 (chiffre cité) | 32 |
| **Cosinus IDF 0,30 centroïde (livré)** | **81** |

Le proxy **surestimait la ligne de base** (32 contre 22 réels) et **sous-estimait
légèrement l'arrivée** (79 contre 81). Le ratio honnête sur corpus complet est donc
**×3,7 et non ×2,5**. Le chiffre publié était mal fondé mais prudent — il faut le
remplacer, pas seulement le retirer.

Rappel : ce ×3,7 décrit une borne haute que la production n'atteint pas (cf. §1.5).

---

## 5. Précision à l'échelle — 0,94, pas 1,00

Les 81 clusters à ≥ 3 médias produits par le code livré sur les 2 351 articles ont été
**audités un par un**. Défauts trouvés :

| # | Type | Contenu |
|---|---|---|
| 1 | **Fusion de sujets sans rapport** | `Atomarine: Nuclear Data Centers at Sea` + `EU launches €30B push to build 7 massive AI data centers` + `LinkedIn Won't Be Expanding Its Data Centers` — 3 sujets, liés par « data centers » (5 médias) |
| 2 | **Fusion de sujets sans rapport** | `Galaxy Watch 9 is $40 off at Costco` + `J'ai testé la Galaxy Watch 9` + `-51 % sur le Samsung Galaxy S25` — promo, test et autre produit (3 médias) |
| 3 | **Cluster de bruit pur** | `"J'ai vu quelqu'un jeter quelque chose et ça s'est embrasé"` + `« J'ai quelque chose à te dire »` + `« Au niveau de la performance globale… »` — trois titres-citations sans sujet commun (3 médias) |
| 4 | **Fusion de sujets voisins** | 2 affaires Le Pen distinctes + une interview Cazeneuve (3 médias) |
| 5 | **Boilerplate** | 20 articles : `JOURNAL DE 12H30 du jeudi 30 juillet`, `Le journal RTL de 6h du 31 juillet`, … — un gabarit, pas un sujet, et **à cheval sur 3 jours** (3 médias) |
| — | Intrus isolé | `Le pape aime les Etats-Unis…` capté par le cluster « frappes américaines sur l'Iran » (7 médias, 1 intrus sur 7) |

**Précision au niveau cluster : 76/81 = 0,94.** Le KPI effectif est donc ~76 sujets
réels, pas 81.

Le `P = 1,00` du §8 n'était pas faux — il était mesuré sur 63 articles annotés, où ces
familles de défauts n'existent pas. **La classe de défaut n°5 (boilerplate) est
structurelle et nouvelle** : le regroupement plus permissif fait émerger des clusters de
gabarit (journaux radio horaires, grilles TV) qui n'existaient pas avant et qui
comptent dans le KPI comme des sujets.

La non-régression « Texas » **tient** : Gaza, Ukraine et Iran restent trois clusters
distincts malgré « Trump » partout. C'est le point le plus risqué du correctif, et il
passe.

---

## 6. Effets de bord aval — confirmés et chiffrés

`is_trending` est défini par `len(cluster.source_domains) >= 3`. Sur le corpus 24 h :

| | Sujets ≥ 3 méd. | **Articles marqués trending** | % du corpus |
|---|---|---|---|
| AVANT (Jaccard 0,40) | 22 | 91 | **3,9 %** |
| APRÈS (cosinus 0,30) | 81 | **453** | **19,3 %** |

**×5 sur le rayon d'action.** Consommateurs vivants, non revérifiés lors de la livraison :

1. **`routers/feed.py:811`** — endpoint `/feed/trending`, qui renvoie
   `[c for c in clusters if c.is_trending]`. Sa liste passe de ~22 à ~81 sujets, dont les
   5 défectueux du §5. Changement visible pour l'utilisateur, hors périmètre annoncé.
2. **`essentiel_service.py:366-367`** — `_W_TRENDING = 50` ajouté si `topic.is_trending`,
   lui-même dérivé de `source_count >= 3` (`digest_service.py:2450`). Quand une minorité
   de sujets était trending, ce +50 discriminait ; à 19 % du corpus il devient beaucoup
   plus proche d'une constante. **Le poids n'a pas été recalibré.**
3. **`recommendation_service.py:1243`**, **`article_clustering_service.py:98`**,
   **`digest_selector._two_pass_selection`** (`trending_target`) — mêmes clusters, ratios
   de sélection établis sous l'ancienne distribution.

Sur le digest éditorial lui-même, l'impact est aujourd'hui **inerte** : `trending_context`
n'y est pas lu (§1.2). Mais l'inertie vient d'un bug, pas d'un choix — le jour où le
chemin sera rebranché, ces ratios sortiront de leur calibration sans avertissement.

---

## 7. Gironde — non résolu, confirmé ; Ceuta — résolu hors production

Fragmentation résiduelle, corpus 24 h (nombre de clusters distincts portant le mot) :

| | `gironde` | `ceuta` | `incendie` |
|---|---|---|---|
| AVANT | 118 | 17 | 171 |
| APRÈS | **91** | **5** | 131 |

| Sujet | AVANT | APRÈS | Cible §6 |
|---|---|---|---|
| Ceuta — meilleur cluster | 3 art. / 3 méd. | **19 art. / 9 méd.** | ≥ 6 méd. ✅ |
| Gironde — meilleur cluster | 3 art. / 3 méd. | **7 art. / 4 méd.** | ≥ 6 méd. ❌ |

Ceuta est traité — mais uniquement sur le corpus complet. Dans le pool de production, il
plafonne à **2 médias** : le sujet reste invisible dans l'app. **Le Lot B résout Ceuta ;
le pool le ré-enterre.**

Gironde reste éclaté sur 91 clusters. Le meilleur (4 médias) regroupe le fil « le feu est
contenu dans son périmètre » ; les facettes (« les mécanos au front », « des obus ont
explosé », « la radio Ici Gironde mobilisée ») restent séparées, comme prévu. Le plafond
lexical R ≈ 0,44 est cohérent avec ce que j'observe.

**Le test embeddings n'a pas été retenté** : `huggingface.co` reste bloqué par la
politique d'egress. Je n'ai pas cherché à contourner. Le protocole du §7.6 (Mistral
`mistral-embed`, critère B³ R > 0,70 à P ≥ 0,95) reste la bonne porte d'entrée, et il
est bien conditionné à une mesure préalable — c'est la partie la plus saine du document
d'origine.

---

## 8. Pistes omises

### 8.1 Déjà écartées par la mesure — ne pas reproposer sans preuve nouvelle

- clusteriser sur `title + description` brute (§7.4 : 63,9 % → 27,4 % de paires
  cross-média) ;
- regroupement par entité seule (§3.2, régression « Texas ») ;
- simple baisse du seuil Jaccard (§3.1 du diagnostic, et confirmé ici §3.3).

### 8.2 Non explorées — par rendement décroissant estimé

1. **Le cap à 200 — le seul levier qui change l'ordre de grandeur.** C'est la conclusion
   n°1 de ce document. Options, de la moins à la plus invasive :
   *(a)* relever le `LIMIT` du seul `_get_global_candidates` (le clustering coûte
   **0,45 s pour 2 200 articles** — mesuré, ce n'est pas le goulot) ;
   *(b)* remplacer « 200 plus récents » par « tout le corpus des N dernières heures »,
   ce qui rend le pool indépendant du débit ;
   *(c)* brancher le chemin éditorial sur `_build_global_trending_context`, qui
   **clusterise déjà tout le corpus 24 h et jette le résultat**. C'est l'option la moins
   chère : le calcul existe, il suffit de le lire.
2. **Fenêtrage temporel.** Aucune contrainte de date n'entre dans la similarité : le
   cluster boilerplate du §5 mélange les 29, 30 et 31 juillet. Un decay temporel ou un
   simple blocage au-delà de N heures supprimerait cette classe de défaut et
   réduirait le chaînage — à moindre risque qu'une baisse de seuil.
3. **Dédoublonnage intra-source.** Signalé au §4.1 du diagnostic, jamais implémenté.
   Le cluster à 20 articles / 3 médias en est l'illustration : 13 des 20 viennent de
   `rtl.fr`. Garder le meilleur article par source et par sujet avant clustering
   assainirait le décompte de `source_domains`, dont dépend directement la pastille.
4. **`Content.entities` comme signal de *blocage*, pas de regroupement.** L'inverse de
   la piste écartée : au lieu de fusionner sur entité partagée (régression Texas),
   **interdire** la fusion quand deux clusters portent des entités nommées disjointes.
   Cela viserait exactement les défauts n°1, 2 et 4 du §5 sans toucher au rappel. Les
   entités sont peuplées à 72 % et ne servent aujourd'hui qu'à *nommer* un carrousel.
5. **Filtre boilerplate.** Classe de défaut nouvelle et facile : les titres à gabarit
   (`JOURNAL DE \d+H`, `Le journal RTL de …`, grilles TV) sont identifiables par regex
   et devraient être exclus du clustering, pas seulement du rendu.
6. **Clustering incrémental.** Aujourd'hui tout est recalculé à chaque cycle. Un
   clustering incrémental persisté rendrait un sujet suivable dans le temps et
   supprimerait la dépendance au débit horaire — c'est le préalable réel du Lot C.
7. **19 articles post-datés.** `published_at > now()` sur 19 lignes (dates RSS
   erronées) ; comme le pool est `ORDER BY published_at DESC`, ils **occupent 19 des 200
   places** en permanence, soit ~10 % du pool. Un `AND published_at <= now()` est un
   correctif d'une ligne.

---

## 9. Pièges d'environnement (coût réel constaté)

| Piège | Détail |
|---|---|
| **`staging` ≠ `main`** | `staging` est **746 commits derrière `main`** et c'est la branche par défaut du repo GitHub. Une branche créée sans `git fetch origin main` part de code périmé. Vérifier : `git rev-list --left-right --count HEAD...origin/main`. |
| **PR #1044 mal titrée** | Squash `docs(bug): …` contenant **tout le code**. Le titre d'une PR n'est pas un périmètre — lire `git show --stat`. |
| **Python 3.12 obligatoire** | Le `python3` du conteneur est **3.11.15**. Utiliser `python3.12` explicitement, et `uv venv --python 3.12`. |
| **Postgres local sur 54322** | Absent au démarrage → des dizaines de faux échecs. `initdb` **refuse de tourner en root** : passer par `su postgres` et un `PGDATA` hors du scratchpad (`/var/lib/postgresql/…`), sinon « Permission denied ». |
| **`PYTHONPATH=.`** | Sans lui, `tests/conftest.py` échoue sur `ModuleNotFoundError: No module named 'app'` avant le premier test. |
| **psql prod bloqué** | Le MCP Supabase est la seule voie. Ses résultats > ~190 k caractères sont **écrits sur disque** au lieu d'être renvoyés : paginer (`LIMIT 700`) et parser les fichiers hors contexte. |
| **Hôtes bloqués par politique** | `huggingface.co` → 403 au CONNECT. Ne pas contourner ; le test embeddings reste non exécuté et déclaré comme tel. |

---

## 10. Reproduction

```bash
python3.12 docs/qa/scripts/verify_clustering_prod_paths.py   <corpus.json> [followed_ids]
python3.12 docs/qa/scripts/verify_clustering_side_effects.py <corpus.json> [followed_ids]
```

Les deux scripts **importent `app/services/briefing/topic_clustering.py` tel quel** et
rejouent l'algorithme antérieur extrait de `beac381e` — aucune réimplémentation, aucun
proxy SQL. Le corpus est un export production
(`{p, d, s, a, t}` = published_at, domaine, source_id, type de source, titre), extrait
via MCP Supabase sur la fenêtre 2026-07-30 05:00 → 2026-08-01 00:00 UTC (4 380 articles
non post-datés).

Suite de tests vérifiée sur ce même environnement : **2 790 passed, 30 skipped** en 52 s.

---

## 11. Recommandation

1. **Retirer le Lot A du périmètre « livré »** dans `bug-clustering-actus-du-jour-fragmentation.md`.
   Il est mort tant que `_get_user_digest_format` renvoie `"editorial"`. Soit on le
   supprime, soit on branche le chemin éditorial dessus — mais il ne doit pas rester
   comptabilisé comme un gain.
2. **Traiter le cap à 200**, option (c) de préférence : le clustering complet 24 h est
   déjà calculé à chaque batch et jeté. C'est le seul changement qui fasse passer le KPI
   de 4 à un nombre à deux chiffres.
3. **Corriger le tableau des « Résultats mesurés » (§8)** : remplacer le `32 → 79` par
   `22 → 81`, et signaler que le banc commité ne reproduit pas la ligne « centroïde ».
4. **Ajouter la variante centroïde à `bench_clustering_bcubed.py`** pour que le harness
   corresponde au code — sinon le Lot C démarre déjà en dette.
5. **Filtrer le boilerplate et les articles post-datés** — deux correctifs courts qui
   récupèrent ~5 faux sujets sur 81 et ~10 % du pool.
6. **Ne pas relever le seuil sans revoir `_W_TRENDING`** : à 19,3 % d'articles trending,
   le bonus de 50 ne discrimine plus.
