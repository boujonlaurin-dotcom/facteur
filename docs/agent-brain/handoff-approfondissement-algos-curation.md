# Hand-off — Approfondir les algos de curation (Essentiel en priorité)

> **À lire en entier avant d'écrire une ligne de code.** Ce document remplace
> une phase d'exploration : il contient l'état vérifié du système au
> 1ᵉʳ août 2026, ce qui a déjà été corrigé, et pourquoi les pistes évidentes
> sont rangées dans cet ordre plutôt qu'un autre.
>
> Doc compagnon à tenir à jour : `docs/algorithme-scoring.html` (page
> autonome, non intégrée au site). Elle vient d'être actualisée ; toute
> modification d'algo faite ici doit s'y refléter.

---

## 0. Le contexte qui déclenche cette mission

Le PO (Laurin) constate, après trois cycles de corrections successives sur la
curation, qu'il **ne ressent aucune amélioration**. Ce n'est pas un problème de
perception : c'est le symptôme d'un diagnostic à faire.

**Les corrections récentes ont porté sur des surfaces qu'il ne regarde pas en
priorité.** La PR #1043 a réparé la curation *en entrée des sections
thématiques de la Tournée*. Elle est mergée, déployée en staging, et
mesurablement correcte. Mais la surface la plus consultée est **l'Essentiel**,
et l'Essentiel **ne passe par aucun des moteurs que nous avons touchés**.

C'est le point de départ de toute cette mission. Ne le perds pas de vue.

---

## 1. Ce qui est déjà fait — ne pas refaire

### PR #1043 — curation en entrée des sections thématiques (mergée)

Doc complète : `docs/bugs/bug-curation-entree-sections-thematiques.md`.

Symptôme : une section thème de la Tournée plafonnait à 6-7 articles alors que
Flâner en montrait 15+ depuis les mêmes sources sur la même fenêtre.

Cause racine : l'exclusion des articles du digest (Story 10.20) était un
**no-op silencieux**. `daily_digest.items` est passé au format `editorial_v3`
(un objet `{mode, metadata, subjects[]}`) alors que le parser inliné attendait
une liste plate de `{content_id}`. Itérer un dict renvoie ses clés →
`isinstance(item, dict)` faux partout → liste vide, sans exception, donc sans
le warning Sentry prévu. La section recevait donc ses 10 articles digest
inclus, que le client retirait ensuite (dédup inter-sections) **après** le
slice de pagination, sans remplacement.

Corrigé :
- extraction déléguée à `extract_content_ids` (helper partagé, 3 layouts) ;
- exclusion **restreinte à `personalized_theme_mode`** — Flâner n'a pas de
  dédup inter-blocs, l'y appliquer l'amputerait de ~14 articles/jour ;
- `digest_stmt` filtré sur `is_serene` (sans ça, `session.scalar` tirait un des
  deux digests du jour au hasard, sans lever) ;
- `extract_content_ids` récupère aussi `representative_content_id` — le pivot
  du sujet, différent d'`actu_article` sur la moitié des sujets, et donc
  supprimable par le storage cleanup, ce qui casse le bottom sheet Perspectives ;
- mobile : `_themeHasMore` aligné sur Flâner, top-up post-frame de la page
  dédiée, dédup des pages suivantes contre toute la Tournée ;
- `is_serial_episode_title` + `SERIAL_EPISODE_MALUS = -6.0` dans `PenaltyPass`,
  gaté sur `personalized_theme_mode`.

**Ce que ça ne fait pas** : ça n'ajoute pas de matière, ça arrête d'en jeter.
Et ça ne touche **ni l'Essentiel ni les Actus du jour**.

### Ce que main a apporté en parallèle (#1035, #1040, #1041, #1042)

- `coverage_source_count` renseigné par `topic_selector` → le bonus de pluralité
  s'applique enfin, **mais sur ce seul chemin** ;
- `INTEREST_WEIGHT_DECAY = 0.98` : `user_interests.weight` était le seul des
  trois signaux appris sans decay (724 lignes en prod, 32 au cap 3.0 — chez les
  vieux comptes, l'âge du compte battait la pertinence du jour) ;
- `ENTITY_MATCH_MULTIPLIER = 1.5` ;
- carrousels semi-éditorialisés partagés Essentiel ⇄ Flâner.

---

## 2. La découverte centrale : l'Essentiel a son propre moteur, non documenté

**Vérifie ceci toi-même en premier** (`app/services/essentiel_service.py`) —
c'est le socle de toute la mission.

Les 5 articles de l'Essentiel ne sont **pas** rangés par le
`PillarScoringEngine`. Ils passent par `_score_article`, un barème additif dont
les constantes sont **en dur dans le fichier**, hors de `scoring_config.py` :

| Signal | Poids | Commentaire |
|---|---|---|
| `_W_FOLLOWED_SOURCE` | **+100** × multiplicateur de priorité | domine tout |
| `_W_TOPIC_WEIGHT` | **+50 × poids appris** (borné à 3.0) | **jusqu'à +150** |
| `_W_TRENDING` | +50 | `topic.is_trending` |
| `_W_UNE` | +35 | `topic.is_une` |
| `_W_BADGE_ACTU` | +25 | badge posé par le digest |
| couverture multi-sources | +0 à +30 | `compute_coverage_score`, partagé |
| `_W_READ_PENALTY` | **-1000** | exclusion de fait |
| `_W_RANK_PENALTY` | -0.5 × rang | tie-break |

Trois conséquences, toutes structurantes :

1. **Le simulateur de `docs/algorithme-scoring.html` ne prédit rien de
   l'Essentiel.** Il est fidèle à pillars_v1, donc juste pour Flâner et la
   Tournée, et muet sur l'écran le plus vu. Toute discussion produit menée
   devant ce simulateur porte à faux dès qu'elle parle de l'Essentiel.
2. **Aucun réglage centralisé ne l'atteint.** Changer `PILLAR_WEIGHTS`,
   `MAX_*_RAW` ou `THEME_MATCH` ne déplace pas un seul article de l'Essentiel.
   C'est très probablement pourquoi le PO « ne sent rien ».
3. **Les échelles ne sont pas comparables.** Piliers : 0-100 pondérés.
   Essentiel : somme brute où un seul signal vaut 100 ou 150. Il n'y a pas de
   correspondance simple entre les deux, donc pas de réglage transférable.

### Second trou, dans le même écran

Dans un sujet des Actus du jour, les `extra_actu_articles` — ceux qu'on voit en
dépliant — sont triés par `(bool(thumbnail_url), published_at)` dans
`actu_matcher.py` (4 occurrences). **Aucun scoring.** Le fait d'avoir une
vignette prime sur tout le reste. C'est déjà noté comme biais connu dans
l'en-tête de `scripts/evaluate_feed_ranking.py`, mais jamais traité.

### Fenêtre de l'Essentiel

`ESSENTIEL_TOURNEE_WINDOW = 24h`, **fixe**, sans élargissement adaptatif (voir
`_filter_articles_by_freshness`). C'est la cible directe de la piste (c) du PO.

---

## 3. Priorisation demandée par le PO, et mon arbitrage

Le PO a proposé quatre pistes (a/b/c/d). Voici comment les ordonner, avec le
raisonnement — **tu peux contester, mais argumente sur les mesures**.

### (a) Outil de fine-tuning — **priorité 1, mais élargi**

Demande : un outil de réglage des seuils avec des pools d'articles d'exemple et
**3 profils fictifs**, pour voir l'effet d'un ajustement sur chacun.

C'est la bonne priorité, **mais l'outil doit couvrir l'Essentiel**, sinon il
reproduit exactement le problème actuel (un simulateur fidèle à un moteur qui
ne pilote pas l'écran regardé).

Cahier des charges :
- **Un harnais Python**, pas une page JS. La page HTML réimplémente la formule
  en JavaScript : elle dérive silencieusement dès que le code Python bouge.
  Le harnais doit importer le **vrai** `PillarScoringEngine` **et** le vrai
  `essentiel_service._score_article`. Précédent à suivre :
  `scripts/prove_thematic_scoring.py`.
- **Un corpus figé et versionné** (`tests/fixtures/scoring_corpus.json`), tiré
  de la prod puis anonymisé : ~150 articles couvrant les cas qui font mal —
  teaser sans texte, article riche sans image, feuilleton, sujet à 6 sources,
  scoop isolé, article de 30h, sport, article déjà lu.
- **3 profils fictifs** aux arbitrages opposés, pour que tout réglage montre
  immédiatement qui il avantage :
  - *Le généraliste* — 25 sources suivies, poids d'intérêt plats, peu
    d'historique ;
  - *Le spécialiste* — 6 sources, deux sous-thèmes au cap 3.0, forte affinité
    d'entités ; c'est lui que sur-servent les poids actuels ;
  - *Le nouveau* — 3 sources choisies à l'onboarding, aucun signal appris ;
    c'est le cold start, et c'est le profil que personne ne teste.
- **Sortie diffable** : pour chaque profil, le top 10 avant/après, avec le
  delta de rang par article. Un réglage se juge sur le *déplacement*, pas sur
  des scores absolus.
- **Un mode « balayage »** : faire varier une constante sur une plage et
  imprimer l'instabilité du top 5 (nombre de changements de rang). Ça révèle
  les constantes inertes — et il y en a (voir le malus hors-thème plus bas).

Livrable attendu : `scripts/tune_scoring.py` + le corpus + une section dans
`docs/algorithme-scoring.html` expliquant comment l'utiliser.

### (b) Préférences par bloc — **priorité 2, mais reformuler**

Demande : tenir compte des préférences utilisateur par bloc, pour mettre en
avant les blocs contenant de très bons articles.

Deux choses distinctes s'y cachent, ne les confonds pas :

- **b1 — ordonner les blocs par la qualité de leur contenu.** Aujourd'hui
  l'ordre des blocs de la Tournée est un ordre utilisateur figé, corrigé
  seulement par une rétrogradation des sections « maigres » (≤1 article, cf.
  `tourneeOrderPrefsProvider`, `kThinSectionMaxItems`). Rien ne fait remonter
  un bloc parce qu'il contient aujourd'hui un article exceptionnel. C'est la
  demande réelle, et elle est faisable : un score de bloc = max ou moyenne des
  k meilleurs scores de ses articles, appliqué comme réordonnancement **doux**
  (ne jamais déplacer un bloc de plus de N positions, sinon la Tournée devient
  méconnaissable d'un jour à l'autre — la stabilité est une promesse produit).
- **b2 — apprendre les préférences *par bloc*.** Beaucoup plus lourd (nouveau
  signal, nouvelle table, nouveau decay). **À ne pas engager dans cette
  mission** sans mesure préalable montrant que b1 ne suffit pas.

Attention au piège : la rétrogradation actuelle se calcule **après** la dédup
inter-sections. Un bloc peut donc être jugé « maigre » à cause d'un bloc placé
au-dessus. Tout scoring de bloc doit se calculer sur le contenu **post-dédup**,
sinon il classe un artefact.

### (c) Élargir les fenêtres temporelles — **priorité 3, cadrée**

Demande : passer à ~36h au lieu de 24h pour ne pas masquer un article
pertinent non lu, quitte à réduire le poids de la fraîcheur.

C'est légitime et peu risqué, **à condition de ne pas confondre les trois
fenêtres** — elles sont indépendantes et n'ont pas les mêmes effets :

| Fenêtre | Valeur | Effet d'un élargissement |
|---|---|---|
| `ESSENTIEL_TOURNEE_WINDOW` | 24h fixe | **le vrai levier** sur l'écran consulté |
| `THEMATIC_WINDOW_TIERS_HOURS` | 24/48/72 adaptatif | déjà adaptatif, mais… |
| `THEMATIC_MIN_POOL_SIZE` | **8** | …**inférieur à la taille de page (10)** |

Le défaut le plus net est le dernier : un thème qui sort 8 à 15 articles est
jugé « suffisant », ne déclenche aucun élargissement, et tient sur une seule
page. Monter ce seuil à ~25-30 est **une ligne** et le correctif le mieux
ciblé de toute cette liste. Il a été volontairement écarté de #1043 pour
limiter la surface de régression ; il est mûr maintenant.

Sur l'Essentiel : 24h → 36h est raisonnable, mais **mesure d'abord**. La
question à trancher par les données : combien d'articles pertinents non lus
sont écartés par la borne 24h ? Si la réponse est « 2 par jour », le gain ne
vaut pas la perte de fraîcheur. Le harnais (a) doit pouvoir répondre.

Ne touche `recency_base` ni la forme de la courbe qu'après. C'est une question
de positionnement produit (« un très bon article de 5 jours peut-il remonter en
tête ? »), pas un réglage — elle appartient au PO, pas à l'agent.

### (d) Embedding — **à ne pas engager maintenant**

L'intuition est juste : le matching actuel est lexical (topics d'une taxonomie
à 50 entrées, Jaccard sur les titres à 0.45, entités spaCy), et un embedding
capterait la proximité sémantique que tout ça rate.

Mais c'est le **mauvais moment**, pour trois raisons vérifiables :

1. **On ne sait pas mesurer.** Sans le harnais (a) et un jeu annoté, on ne
   pourra pas dire si l'embedding fait mieux. On remplacerait un système
   mal réglé par un système opaque et tout aussi mal réglé.
2. **Le tuyau actuel fuit encore.** `content.cluster_id` est NULL à ~99 % en
   base ; le clustering existe mais n'est pas persisté. Le bonus de pluralité —
   *le signal le plus aligné avec la promesse éditoriale de Facteur* — vaut
   donc 0 sur tout le feed. Réparer ça rapporte plus, pour bien moins cher,
   qu'une couche vectorielle.
3. **Coût d'exploitation réel.** pgvector + backfill + re-embedding continu +
   un modèle de plus à héberger, sur une app qui tourne sur un worker uvicorn
   unique et qui a déjà des soucis de latence au cold-open.

**Position à tenir** : rouvrir (d) quand (a) sera livré et que deux itérations
de réglage auront plafonné. Le harnais rendra alors la comparaison possible —
et c'est précisément ce qui rendra la décision défendable.

---

## 4. Pistes supplémentaires trouvées en lisant le code

Elles ne sont pas dans la liste du PO. Plusieurs sont plus rentables que (c).

### P1 — Le pilier Qualité est une prime à la vignette

Plafond `MAX_QUALITE_RAW = 32`, dont 12 pour la seule présence d'une image :
une miniature décroche 37/100. Les 15 % dévolus à la « qualité » récompensent
donc le confort visuel, pas la qualité éditoriale. Et le même biais existe en
plus brutal dans `actu_matcher` (tri par `bool(thumbnail_url)` d'abord).

Signaux disponibles et non utilisés : `content_quality` (déjà là, sous-pondéré),
longueur du texte, `reliability_score` de la source, `is_paid`, densité
d'entités. Piste : refondre le pilier et relever le plafond en conséquence.

### P2 — Le malus « hors thème suivi » est inerte

`THEME_MISMATCH_MALUS = -8`, mais `BasePillar._normalize` renvoie 0 dès que le
brut est négatif. Un article à -8 et un à 0 sortent identiques. Soit on le
déplace dans `PenaltyPass` (où il agirait vraiment), soit on le supprime. À
trancher avec le harnais : c'est exactement le genre de constante que le mode
« balayage » doit révéler comme sans effet.

### P3 — Doublons d'ingestion

171 groupes `(source_id, title)` en double sur 7 jours (197 lignes, ~1,3 % du
corpus) — ex. « Et si nous vivions dans une simulation 3/3 » présent 2×. Ça
consomme des slots dans tous les blocs. Dédup RSS sur `guid`/titre normalisé.
Peu spectaculaire, effet immédiat et transversal.

### P4 — Le clustering fragmente

Voir `docs/bugs/` (#1044, diagnostic déjà écrit et mergé). Seuil Jaccard 0.45
sur les titres : un même sujet couvert par 5 médias se scinde souvent en 3
clusters. Double effet — les Actus du jour montrent 3 fois le même sujet, et le
bonus de pluralité (qui compte les sources d'un cluster) est mécaniquement
sous-évalué. **À traiter avant** de rebrancher le bonus sur le feed, sinon on
branche un signal faux.

### P5 — La pénalité d'impression écrase tout

-100 à moins d'1h, -70 à moins de 24h, sur un score composite qui plafonne vers
100. Un excellent article vu une fois au pull-to-refresh est éliminé pour la
journée. Interaction directe avec la demande (c) du PO : élargir la fenêtre ne
sert à rien si la pénalité d'impression a déjà enterré les articles de la
tranche 24-36h. **Vérifie cette interaction avant de livrer (c).**

### P6 — Aucune boucle de mesure

`scripts/evaluate_feed_ranking.py` existe et est lucide sur ses propres biais
(lis son en-tête, il est excellent), mais rien ne tourne en continu. Aucun
réglage n'est aujourd'hui validé autrement qu'à l'œil du PO — d'où trois cycles
sans amélioration ressentie. Le harnais (a) est le premier pas ; un rapport
hebdomadaire sur le CTR par rang serait le second.

---

## 5. Ordre de marche recommandé

1. **Vérifier par toi-même** la section 2 (moteur propre à l'Essentiel, tri des
   `extra_actu_articles`). Tout le reste en découle. Si tu trouves que je me
   trompe, dis-le et renégocie le plan.
2. **Livrer le harnais (a)** avec les 3 profils et le corpus figé. Rien d'autre
   avant : c'est l'instrument de mesure de tout ce qui suit.
3. **Mesurer avant de régler.** Produire un état des lieux chiffré : qu'est-ce
   qui décide réellement des 5 slots de l'Essentiel aujourd'hui, pour chacun des
   3 profils ? On s'attend à ce que `_W_FOLLOWED_SOURCE` (+100) et
   `_W_TOPIC_WEIGHT` (jusqu'à +150) écrasent tout — **confirme-le ou
   infirme-le** avant de toucher quoi que ce soit.
4. **Deux réglages à faible risque, immédiatement** : `THEMATIC_MIN_POOL_SIZE`
   8 → ~25 (une ligne), et le tri des `extra_actu_articles` par score plutôt que
   par vignette.
5. **Puis** (b1), (c) sur l'Essentiel, P1, P2 — chacun validé au harnais, un
   changement à la fois, avec le diff des 3 profils dans la PR.
6. **Tenir la doc à jour** : `docs/algorithme-scoring.html` à chaque changement
   de constante ou de branchement. Cette page est le support des discussions
   produit ; une page fausse coûte plus cher que pas de page.

---

## 6. Contraintes non négociables

- **Perf.** Consigne explicite du PO sur la mission précédente, à reconduire :
  aucune requête alourdie, aucun temps de chargement dégradé. Le backend tourne
  sur **un worker uvicorn unique** et le cold-open tire déjà ~10 appels
  parallèles. Toute PR touchant une requête doit produire un `EXPLAIN`
  avant/après. Précédent : #1043 a documenté +0,6 % de coût, plan inchangé.
- **Un changement à la fois.** Trois cycles ont déjà été « corrigés » sans
  effet ressenti, en partie parce que les changements étaient groupés. Une PR =
  un levier = une mesure.
- **`--base main` obligatoire** (hook `pre-bash-no-staging.sh`). Jamais
  `production`.
- **Expand-contract** sur toute migration : `main` et `production` partagent la
  DB de prod (cf. CLAUDE.md).
- **Environnement d'exécution.** Aucun SDK Flutter n'est installé dans les
  sessions distantes : `flutter test` / `flutter analyze` ne peuvent pas y
  tourner, la CI doit valider le mobile. Postgres n'est pas non plus démarré
  par défaut — pour la suite backend, initialiser un cluster local sur le port
  54322 (`initdb` + `pg_ctl`, binaires dans `/usr/lib/postgresql/16/bin`),
  Docker n'étant pas disponible.
- **Données prod.** Le MCP Supabase donne un accès SQL en lecture. Compte de
  référence du PO : `fd6b9d0b-4c16-422b-9688-bae34d63f41c` (72 sources
  suivies). S'en servir pour chiffrer, jamais pour deviner.

---

## 7. Le piège à éviter

Ne recommence pas le cycle précédent : trouver un vrai bug, le corriger
proprement, le prouver par des tests — et livrer une amélioration que le PO ne
ressent pas, parce qu'elle porte sur une surface secondaire.

Avant de commencer quoi que ce soit, réponds à cette question par des chiffres :
**qu'est-ce qui décide, aujourd'hui, des 5 articles de l'Essentiel ?**

Si tu ne peux pas y répondre précisément, le premier livrable est l'instrument
qui le permettra — pas une correction.
