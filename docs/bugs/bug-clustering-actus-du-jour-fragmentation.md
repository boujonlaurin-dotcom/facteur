# Bug — Fragmentation du clustering : les plus gros sujets du jour n'atteignent jamais « Actus du jour »

**Date** : 2026-07-31
**Branche** : `claude/article-clustering-analysis-06xko0`
**Sévérité** : **P0 — cœur de proposition de valeur**. La section « Les sujets les + couverts en France » n'affiche pas les sujets les plus couverts.
**Statut** : Diagnostic terminé — plan à valider (pas d'implémentation)
**Liés** : `bug-actus-du-jour-ranking.md`, `bug-clustering-consistency.md`, `bug-comparison-clustering-too-loose.md`, `bug-digest-pas-de-recul-same-event.md`

---

## 1. Symptôme

Capture utilisateur du 2026-07-31 (« Actus du jour ») :

| # | Titre | Sources |
|---|---|---|
| 1 | Bande de Gaza : Donald Trump annonce un accord sur le désarmement du Hamas | 3 sources |
| 2 | Trump annonce un accord sur le désarmement du Hamas, malgré le scepticisme d'Israël | 2 sources |
| 3 | Anthropic says its AI accidentally hacked three companies during safety tests | 2 sources |

Deux problèmes visibles d'un coup :

- **(A) Doublon** : les cartes 1 et 2 sont **le même sujet**, éclaté en deux clusters.
- **(B) Absences majeures** : aucun sujet sur l'immigration en Espagne (Ceuta) ni sur les incendies en Gironde, alors qu'ils sont en Une de la quasi-totalité des médias.

**Le pool de données n'est pas en cause.** Sur les 24 h analysées (2 193 articles, 122 sources), les tokens les plus partagés entre médias distincts sont :

| Token | Articles | Médias distincts |
|---|---|---|
| `gironde` | **120** | 18 |
| `incendies` | 86 | 23 |
| `ceuta` | **83** | **24** |
| `migrants` | 51 | 18 |
| `trump` | 48 | 18 |
| `espagne` | 37 | 15 |
| `hamas` | 26 | 14 |
| `anthropic` | 20 | 16 |

Les deux sujets absents de l'app sont **les deux plus gros sujets de la base**. Ceux qui s'affichent (Hamas 26 art., Anthropic 20 art.) sont 3 à 6 fois plus petits. **L'information est là, l'algorithme ne la voit pas.**

---

## 2. Root cause

Un seul et même code sert le digest, l'Essentiel et les carrousels :
`ImportanceDetector.build_topic_clusters()` — `packages/api/app/services/briefing/importance_detector.py:140-275`.

C'est un clustering glouton en une passe, sur **le seul titre**, avec similarité de **Jaccard ≥ 0.45** (`ScoringWeights.TOPIC_CLUSTER_THRESHOLD`).

### 2.1 Cause n°1 — Le seuil est mathématiquement hors d'atteinte

Un titre de presse contient en moyenne **8,4 tokens utiles** après filtrage des 216 stop words (mesuré sur le corpus réel).

Jaccard = |A ∩ B| / |A ∪ B|. Pour que deux titres de 8 tokens franchissent 0.45 :

```
s / (8 + 8 - s) ≥ 0.45   ⟹   s ≥ 5,2
```

**Il faut que 5 à 6 des ~8 mots significatifs soient identiques.** Deux rédactions qui couvrent le même événement ne rédigent jamais leur titre ainsi. Résultat sur le corpus réel :

- **15,6 %** des articles seulement ont ≥ 1 voisin au-dessus de 0.45 ;
- Jaccard médian du meilleur voisin de chaque article : **0.167** (seuil : 0.45) ;
- 706 paires retenues sur 81 443 partageant au moins un mot (**0,87 %**).

**84 % des articles sont condamnés au singleton avant même que l'algorithme ne commence.**

### 2.2 Cause n°2 — La dérive du sac de tokens (le cluster se ferme après 2 articles)

`importance_detector.py:186-203` : un article n'est **jamais comparé aux articles du cluster**, mais au **sac fusionné** de tous leurs tokens (`merged = cluster["tokens"] | tokens`, plafonné à 15).

Ce sac grossit à chaque ajout → l'**union** au dénominateur de Jaccard grossit → la similarité **chute mécaniquement** pour tout candidat suivant. Le cluster s'auto-verrouille.

Démonstration sur le sujet Gaza de la capture :

| Article candidat | Jaccard vs **article 1** | Jaccard vs **sac accumulé** | Verdict |
|---|---|---|---|
| Art. 2 (Courrier Int.) | 0.455 | 0.455 (8 tk) | ✅ rattaché |
| Art. 3 (France Info) | 0.364 | **0.286** (11 tk) | ❌ rejeté → nouveau cluster |
| Art. 4 (Libération) | 0.154 | **0.200** (11 tk) | ❌ rejeté → nouveau cluster |

**C'est exactement le doublon (A) de la capture.** Le 3ᵉ article, pourtant sur le même sujet, ouvre un cluster concurrent.

### 2.3 Cause n°3 — L'effet est *anti-corrélé* à l'importance du sujet

C'est le mécanisme le plus grave, et il est contre-intuitif :

> **Plus un sujet est couvert, plus il se fragmente, et moins il a de chances d'être affiché.**

Un sujet couvert par 20 médias est traité sous 20 angles éditoriaux différents (bilan humain, réaction politique, explication, terrain, économie…). Le vocabulaire diverge, donc il éclate en 15-19 micro-clusters de 1-2 sources. Un sujet couvert par 3 médias qui se recopient reste, lui, groupé.

Or la sélection (`topic_selector.py`) trie par taille de cluster et attribue `TOPIC_TRENDING_BONUS = 50` aux clusters de **≥ 3 domaines**. Un sujet fragmenté ne touche jamais ce bonus. **L'algorithme pénalise structurellement les sujets majeurs.**

#### Preuve sur données de production — corpus Ceuta

21 articles, **21 médias différents**, **le mot « Ceuta » dans les 21 titres**, un seul événement.

Résultat de `build_topic_clusters()` :

```
>>> 19 clusters produits.  Tailles : [2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
>>> Clusters « trending » (>=3 domaines) : 0
>>> Articles isolés en singleton : 17/21
>>> Jaccard paire-à-paire : moyen 0.118 | >= 0.45 : 3 paires sur 210
```

**Zéro cluster trending.** Le sujet ne peut mathématiquement pas apparaître dans « Actus du jour », quel que soit le scoring en aval.

### 2.4 Chiffrage global (24 h de production)

En mesurant les composantes connexes du graphe des paires ≥ 0.45 — ce qui est une **borne supérieure généreuse** de ce que fait réellement l'algorithme glouton :

| Métrique | Valeur |
|---|---|
| Articles publiés (24 h) | 2 193 |
| Articles rattachés à un autre article | **334 (15 %)** |
| Sujets multi-articles | 100 |
| Sujets à ≥ 3 médias (seuil « trending ») | **32 au maximum** |
| Plus gros cluster possible | 10 médias |

L'algorithme réel étant plus restrictif que cette borne, il en descend 3-4 dans l'app — cohérent avec l'observation utilisateur.

---

## 3. Ce que le problème n'est PAS

Il faut écarter les fausses pistes avant d'engager le correctif.

### 3.1 Ce n'est pas un problème de réglage de seuil

Test sur corpus mixte réel (21 Ceuta + 8 Gironde + 10 sans rapport) :

| Variante | Meilleur cluster Ceuta | Meilleur cluster Gironde |
|---|---|---|
| **Actuel — Jaccard 0.45, sac fusionné** | 2 art / 2 médias | 1 art / 1 média |
| Jaccard 0.30 | 3 / 3 | 1 / 1 |
| Jaccard 0.25 | 5 / 5 | 1 / 1 |
| Jaccard 0.45, liaison simple (vs membres) | 3 / 3 | 1 / 1 |
| Recouvrement 0.50, liaison simple | 7 / 7 | 1 / 1 |
| **Cosinus pondéré IDF, 0.25** | 7 / 7 | 1 / 1 |

Même en descendant le seuil jusqu'à l'absurde, on ne dépasse pas **7 articles sur 21**. Corriger la dérive du sac (§2.2) ne rapporte qu'**un seul article**. Le problème n'est pas le paramètre : **c'est la représentation**. Deux titres du même événement ne se ressemblent pas lexicalement.

### 3.2 Ce n'est pas non plus « il suffit de regrouper par entité »

C'est le piège documenté dans `bug-comparison-clustering-too-loose.md` (le cas « Texas », 2026-04-22) : regrouper sur une entité partagée fusionne des sujets sans rapport.

Vérification sur le cas le plus dangereux du jour — les **24 articles contenant « Trump »**, qui couvrent en réalité **4 sujets distincts** (accord Hamas, missiles Patriot en Ukraine, guerre en Iran, politique intérieure US) :

| Règle | Ceuta | Gironde | Gaza | Ukraine | Iran | Clusters mixtes |
|---|---|---|---|---|---|---|
| A. **Actuel** | 2/21 (2 méd.) | 1/8 | 6/9 | 1/5 | 1/3 | 0 |
| B. Ancre nom propre seule | **21/21 (21 méd.)** | **7/8** | 9/9 | 4/5 | 3/3 | **3 — fusionne 5 sujets** ❌ |
| C. Ancre + ≥ 2 ancres partagées | 5/21 | 1/8 | 9/9 | 5/5 | 3/3 | 1 |
| **D. Ancre + Jaccard ≥ 0.20** | **9/21 (9 méd.)** | 2/8 | **9/9** | **5/5** | 2/3 | 1 |
| D'. Ancre + Jaccard ≥ 0.25 | 5/21 | 1/8 | 9/9 | 3/5 | 2/3 | **0** |

- La règle B (ancre seule) a un rappel parfait mais **reproduit exactement le bug Texas** : elle colle Gaza + Ukraine + Iran + politique US dans un seul cluster « Trump ».
- La règle **D** est le bon compromis : Ceuta passe de 2 à **9 médias** (donc largement trending), Gaza et Ukraine sont **correctement séparés**, et il ne reste qu'un cluster mixte.

**Conclusion honnête** : une correction purement lexicale fait passer « Actus du jour » de ~3 sujets à ~5-6 sujets réellement représentatifs et débloque Ceuta. Elle **ne suffit pas pour la Gironde** (2/8), dont les articles sont des facettes thématiquement dispersées (cambrioleurs, obus, radio locale, mécanos, forêt) qui ne partagent presque aucun vocabulaire. Ce cas-là exige une représentation sémantique.

---

## 4. Problèmes secondaires identifiés

1. **Sur-représentation d'une source.** BFMTV publie à lui seul ~45 articles quasi dupliqués sur la Gironde (« Incendie en Gironde: "[citation]", déclare X »). Le fold agrégateur ne traite que Reddit ; il n'existe pas de dédoublonnage intra-source. Ces titres-citations sont aussi structurellement inclusterisables.
2. **`Content.entities` est sous-exploité.** 72 % des articles des dernières 24 h ont des entités NER (3,1 en moyenne). Elles ne servent aujourd'hui qu'à *nommer* un carrousel (`article_clustering_service.py:116-129`), jamais à regrouper.
3. **La colonne `contents.cluster_id` est morte** : 11 lignes renseignées sur 2 205. Le clustering est intégralement recalculé en mémoire à chaque génération, sans persistance ni observabilité — impossible de suivre un sujet dans le temps ou de mesurer une régression.
4. **Stop words contre-productifs.** `president`, `gouvernement`, `ministre`, `monde`, `guerre`(non), `europe` sont filtrés. Sur un titre de 8 mots, retirer « président » ou « Europe » supprime un discriminant réel et rapproche le titre du bruit.

---

## 5. Plan proposé

Trois lots, du moins risqué au plus structurant. **Chaque lot est indépendamment livrable.**

### Lot 1 — Débloquer l'existant (faible risque, gain immédiat)

1. Remplacer la comparaison au sac fusionné par une **liaison simple** (max de similarité sur les membres du cluster) — supprime la dérive §2.2 et le doublon Gaza de la capture.
2. Ajouter la règle **D** : deux articles se rejoignent s'ils partagent **≥ 1 ancre distinctive** (nom propre / entité NER dont la fréquence du jour ≤ 6 % du corpus) **ET** un Jaccard ≥ 0.20.
3. Réutiliser `Content.entities` (déjà peuplé à 72 %) comme source d'ancres, avec repli sur la détection de majuscules.
4. Dédoublonnage intra-source avant clustering (garder le meilleur article par source et par sujet).

*Gain attendu : Ceuta et les gros sujets équivalents deviennent visibles ; le doublon disparaît. Risque de régression « Texas » contenu par la double condition.*

### Lot 2 — Observabilité (indispensable avant d'aller plus loin)

1. Persister les clusters (`contents.cluster_id` + table de clusters) au lieu de tout recalculer en mémoire.
2. Harness de calibration rejouable sur un corpus figé, avec un jeu de sujets annotés (Ceuta, Gironde, Trump/4-sujets sont déjà constitués dans cette analyse).
3. Métriques quotidiennes : nb de sujets ≥ 3 médias, taux de singletons, taille du plus gros cluster, taux de clusters mixtes.

*Sans cela, tout réglage futur se fait à l'aveugle — c'est ce qui a produit l'oscillation « trop large » (avril) → « trop strict » (aujourd'hui).*

### Lot 3 — Représentation sémantique (résout le cas Gironde)

Le seul moyen de regrouper « les mécanos au front », « des obus ont explosé » et « la radio Ici Gironde mobilisée » sous un même sujet.

- Option A : **embeddings** de titre+chapô, clustering par seuil cosinus. `pgvector` n'est pas encore installé sur le projet Supabase (extensions actives : `unaccent`, `pg_trgm`) — à provisionner. Coût maîtrisé, latence faible, pas de dépendance LLM par article.
- Option B : **labellisation LLM** du sujet par lot d'articles. Une pipeline éditoriale LLM existe déjà (`services/editorial/`), donc le socle est là, mais le coût croît avec le volume (2 200 art./jour).

*Recommandation : Option A, avec l'Option B réservée au nommage éditorial des clusters retenus (déjà son rôle actuel).*

---

## 6. Critères de succès

Mesurés sur le corpus figé du 2026-07-31 :

| Critère | Aujourd'hui | Cible Lot 1 | Cible Lot 3 |
|---|---|---|---|
| Sujet Ceuta — meilleur cluster | 2 médias | **≥ 6 médias** | ≥ 12 médias |
| Sujet Gironde — meilleur cluster | 1 média | ≥ 2 médias | **≥ 6 médias** |
| Gaza / Ukraine / Iran séparés | oui | **oui (non-régression)** | oui |
| Sujets ≥ 3 médias dans « Actus du jour » | 3-4 | **≥ 6** | ≥ 8 |
| Clusters mixtes (2 sujets réels fusionnés) | 0 | **≤ 1** | 0 |
| Taux de singletons (24 h) | 85 % | ≤ 70 % | ≤ 50 % |

---

## 7. Reproduction

Scripts de l'analyse (corpus réel extrait de production, algorithme importé depuis `app/services/text_similarity.py`) :

- Requêtes SQL de diagnostic : §1, §2.1, §2.4 de ce document (exécutables telles quelles sur Supabase).
- Simulation de l'algorithme et comparaison des variantes : voir historique de la branche `claude/article-clustering-analysis-06xko0`.

**Aucune modification de code applicatif n'a été faite** — ce document est un diagnostic.
