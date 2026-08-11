# Maintenance : refonte mesurée de la détection paywall

**Type** : Maintenance
**Statut** : 🟡 EN COURS — corpus collecté (12/14 sources), cause racine des faux
négatifs Novethic identifiée et corrigée ; reste l'étiquetage manuel avant de
pouvoir geler une baseline chiffrée
**Périmètre** : `packages/api/app/services/paywall_detector.py`, `sync_service.py`
**Hors périmètre** : le filtre d'affichage `Content.is_paid.is_not(True)`
(`digest_selector.py`, `recommendation_service.py`) — fail-open volontaire,
cf. [bug-paywall-null-filter.md](../bugs/bug-paywall-null-filter.md).

---

## Le problème

La détection date de février 2026 et n'a évolué que par ajout manuel de
`paywall_config` JSONB par source (4 médias : Le Monde, Le Figaro, Les Échos,
Le Point). Ce pattern ne scale pas. Des faux négatifs sont remontés sur au
moins 5 sources : Novethic, Les Jours, La Croix, Philosophie Magazine,
Cuisiner.

L'objectif est d'améliorer **génériquement** les niveaux 1 (signaux HTML
déclaratifs) et 2 (scoring de repli), sur mesure réelle — pas d'empiler du
custom par source.

## L'asymétrie qui gouverne toutes les décisions

| Erreur | Coût | Réversible ? |
|---|---|---|
| Faux négatif (article payant affiché) | l'utilisateur clique et tombe sur un paywall | oui, le sync suivant peut corriger |
| **Faux positif** (article gratuit masqué) | retire silencieusement de l'offre gratuite, contre la promesse produit | **non** |

L'irréversibilité vient de `_save_content` (`sync_service.py` l.620) :
`is_paid` n'est upgradé que de `False` vers `True`, jamais l'inverse. Un
article marqué payant à tort le reste définitivement en base.

**Conséquence opérationnelle** : toute modification qui augmente le taux de FP,
même d'un seul article sur une seule source, est rejetée — même si elle corrige
beaucoup de FN. Le harnais rend ce verdict mécanique
(`test_false_positive_rate_never_regresses`).

---

## État d'avancement

### Fait — l'instrumentation

| Livrable | Fichier |
|---|---|
| Manifeste du corpus (14 sources, quotas, groupes) | `packages/api/tests/fixtures/paywall_corpus/manifest.yaml` |
| Collecteur RSS + HTML head, rejouable | `packages/api/scripts/build_paywall_corpus.py` |
| Harnais de mesure (matrice de confusion) | `packages/api/scripts/paywall_benchmark.py` |
| Garde-fou anti-régression en CI | `packages/api/tests/test_paywall_corpus_benchmark.py` |

Le collecteur réplique la production à l'identique : User-Agent Chrome du
client `SyncService`, `follow_redirects=True`, bundle certifi,
`Range: bytes=0-50000`, timeout 5 s, codes 200 **et** 206, troncature à 50 000
caractères. Une divergence ici produirait une baseline non représentative.

Le harnais reconstruit les arguments de `detect_paywall()` comme `_parse_entry`
le fait pour un article : `description = html.unescape(entry.summary)`,
`html_content = content:encoded`.

Tant que le corpus n'est pas collecté et étiqueté, les trois tests se
**skippent avec une raison explicite** : un corpus absent ne doit jamais passer
pour un corpus sans erreur.

### Fait — la collecte (2026-08-08)

L'egress vers les domaines de presse est ouvert. 120 articles collectés sur
12 des 14 sources ; **les 5 sources du groupe « faux négatifs » passent toutes**,
c'est-à-dire tout le périmètre utile de la refonte.

Deux sources restent hors corpus, et ce n'est pas une question de
configuration : `lesechos` et `lepoint` répondent **403 sur tous les chemins
testés** (flux et pages), y compris avec le User-Agent de prod. C'est leur
anti-bot qui refuse l'IP datacenter, pas la politique d'egress — le proxy
n'enregistre aucun rejet CONNECT pour ces hôtes. Les rejouer exigerait de
sortir par une IP résidentielle ; en attendant, le garde-fou anti-régression
couvre 5 des 7 sources du groupe B.

**Le corpus lui-même n'est pas versionné.** `html/` et `rss/` sont du contenu de
presse sous droits et le repo est public : ils sont gitignorés et se
régénèrent en une commande. Les métadonnées, elles, sont versionnées —
`labels.json` porte l'étiquetage humain, qui ne doit pas se perdre au clone.

```bash
cd packages/api
PYTHONPATH=. python scripts/build_paywall_corpus.py           # collecte
PYTHONPATH=. python scripts/build_paywall_corpus.py --check   # accès seul
```

Conséquence à assumer : le garde-fou `test_paywall_corpus_benchmark.py` se
skippe en CI faute de corpus. Il ne mesure qu'en local, après collecte et
étiquetage.

Correctif de manifeste au passage : les 3 candidates de La Croix redirigeaient
(301) vers le chemin legacy `http://www.la-croix.com/RSS/UNIVERS_ALL`, qui
répond 403. Le flux réel est `https://www.la-croix.com/feeds/rss/site.xml`.

État du HTML par source — le niveau 1 ne peut rien dire sans lui :

| HTML récupéré | Sources |
|---|---|
| oui | novethic, philomag, la-croix, cuisiner-jdf, lefigaro, mediapart, telerama, contrepoints, bonpote |
| non — 403 anti-bot | lesjours, liberation |
| non — **402 Payment Required** | lemonde |

Le 402 du Monde est un signal de paywall exploitable, qu'aucun des 3 niveaux
ne lit aujourd'hui (`_fetch_html_head` traite tout ce qui n'est pas 200/206
comme une absence de HTML). Piste à évaluer, non retenue à ce stade.

### Fait — la cause racine des faux négatifs Novethic

Mesuré en rejouant `detect_paywall_from_html()` sur les 90 HTML du corpus :
Novethic sortait `None` (aucun signal) sur **10 fichiers sur 10**, alors que
6 d'entre eux contiennent bien `"isAccessibleForFree": false`.

Le marqueur est présent mais illisible : Yoast SEO (WordPress) n'émet jamais
l'article au niveau racine du JSON-LD, il l'emballe dans
`{"@context": …, "@graph": [ … ]}`. Le parseur n'inspectait que la racine et ne
descendait pas dans `@graph`. Le média déclarait l'article payant, on ne
l'entendait pas.

Le correctif descend dans `@graph`. Effet mesuré sur le corpus, à étiquetage
constant :

| Source | Avant | Après |
|---|---|---|
| novethic | 10 sans signal | **6 payants**, 4 sans signal |
| les 8 autres sources avec HTML | — | **inchangées** |

C'est bien un gain générique — Yoast équipe une grande partie de la presse
en ligne française — et non un `paywall_config` de plus.

Deux garde-fous accompagnent la descente, parce qu'elle élargit la surface lue :

- `isAccessibleForFree` n'est plus lu sur les nœuds `WebPageElement`. La spec
  Google le place aussi dans `hasPart` pour décrire le bloc payant : une page
  **gratuite** contenant un encart payant y porte `false`, et la lire créerait
  un faux positif. Aucune divergence page/`hasPart` dans le corpus actuel,
  mais la structure autorise le cas.
- Nœuds contradictoires → « gratuit » gagne, par l'asymétrie des coûts.

### Portée : pourquoi le correctif vaut au-delà des sources listées

Le niveau 1 ne peut pas être spécifique à une source, par construction :
`detect_paywall_from_html()` ne reçoit que le HTML — ni `source_id`, ni
`paywall_config`, ni domaine. Et son point d'appel
(`sync_service.py` l.188) ne conditionne le fetch HTML qu'au
`content_type == ARTICLE`, jamais à l'identité de la source. Toute source qui
déclare `isAccessibleForFree` dans `@graph` en bénéficie donc
automatiquement, qu'elle soit dans le corpus ou non.

Trois fragilités de *forme* ont été levées pour que cette portée soit réelle et
pas seulement théorique. Aucune n'apparaît dans le corpus — elles décrivent le
même comportement déclaratif sous une sérialisation différente, et sont donc
justifiées par la généricité, pas par un chiffre :

| Forme | Avant | Après |
|---|---|---|
| Article sous `WebPage.mainEntity` | raté | lu |
| Booléen en URI (`https://schema.org/False`) | lu comme « gratuit » | lu comme « payant » |
| `<meta content="locked" property="og:article:content_tier">` (ordre inversé) | raté | lu |

`itemListElement` est délibérément **non** traversé : une liste pointe vers
d'autres articles, et leur état d'accès ne dit rien de la page courante — la
traverser ferait basculer en payante une page de rubrique gratuite listant des
articles payants.

Vérification de non-régression : après ces trois généralisations, le corpus
rend **exactement** les mêmes verdicts qu'avant sur les 90 fichiers.

La preuve empirique sur des sources hors corpus n'a pas pu être faite : la
politique d'egress est allowlistée **par domaine** et couvre les 14 sources du
manifeste. Un test sur 16 médias du catalogue absents du corpus (L'Humanité,
Politis, Élucid, Next, StreetPress, Vert, Blast…) rend 16 rejets CONNECT.
Élargir l'allowlist à ces domaines permettrait de chiffrer le gain réel.

### Invalidé par les données — la piste des mots-clés

L'hypothèse « apostrophe typographique » était présentée ici comme la piste
prioritaire, au meilleur rapport risque/gain. **Les données l'écartent, et
montrent que l'appliquer aurait été dangereux.**

Sur la forme, elle est exacte : 30 fichiers HTML contiennent `s’abonner`
(U+2019), **zéro** contiennent `s'abonner` (U+0027). Le mot-clé
`"S'abonner"` de `DEFAULT_PAYWALL_CONFIG` ne matche donc jamais rien.

Mais deux mesures la vident de son intérêt :

1. **Mauvaise surface.** Les mots-clés sont matchés sur `title + description +
   html_content`, c'est-à-dire le **RSS** — jamais sur `html_head`. Or sur les
   301 entrées RSS collectées, **aucun** des mots-clés de la config par défaut
   n'apparaît, dans aucune variante d'apostrophe, sur aucune des 12 sources.
   Le niveau 2 par mots-clés est du code mort en pratique.
2. **Le « fix » aurait créé des faux positifs.** Dans le HTML, `s’abonner`
   apparaît sur **10 articles sur 10** chez Novethic comme chez Mediapart :
   c'est une chaîne de navigation/pied de page, présente sur les articles
   gratuits comme payants. Corriger l'apostrophe pour ensuite matcher cette
   surface transformerait un mot-clé inerte en générateur de faux positifs —
   exactement l'erreur irréversible que la refonte doit éviter.

Conclusion : ne pas toucher aux mots-clés tant qu'aucune mesure ne montre un
gain. Le levier est le niveau 1, pas le niveau 2.

### Fait — rendre le harnais compatible avec un étiquetage progressif

L'étiquetage se fait par lots, sur plusieurs sessions. Deux défauts du harnais
rendaient ce mode de travail impossible ; les deux ont été reproduits sur un
`labels.json` simulé à 30 labels avant correction.

**1. Le quota jugeait un étiquetage en cours.** `load_corpus()` ignore les
`label: null`, donc dès le premier label posé le corpus n'était plus vide et
`test_corpus_has_free_articles_per_source` passait de « skip » à **échec** sur
les 12 sources à la fois. Comme `labels.json` est versionné, la CI virait au
rouge aussi. Le quota ne juge désormais qu'une source dont l'étiquetage est
**terminé** — une source à moitié étiquetée n'est pas un corpus défaillant,
c'est un travail en cours.

**2. La mesure tournait sans les charges utiles — et rendait un faux vert.**
`html/` et `rss/` sont gitignorés, `labels.json` non : en CI, chaque cas partait
donc avec `html_head=None`, le niveau 1 était intégralement sauté. Mesuré avec
une baseline gelée et 30 labels : `test_false_positive_rate_never_regresses`
**passait au vert** (FP = 0, puisque sans HTML plus rien n'est détecté) pendant
que le test de FN échouait à tort. Le vert portait sur la métrique bloquante,
c'est-à-dire au pire endroit possible. La mesure se skippe maintenant tant
qu'aucun cas ne porte de HTML.

Deux effets de bord corrigés au passage, sur le même comptage :

| Cas | Avant | Après |
|---|---|---|
| `lesechos`, `lepoint` — au manifeste, 0 article collecté (403) | comptés « 0 payants / 0 gratuits, quota non tenu » à perpétuité | hors quota tant qu'ils sont hors corpus |
| `contrepoints`, `bonpote` — médias 100 % gratuits | quota de 3 payants **inatteignable par construction** | `expects_paid: false` au manifeste ; le quota de gratuits, lui, s'applique toujours |

La règle vit en un seul endroit (`quota_status()`, `build_paywall_corpus.py`) :
le collecteur en fait un avertissement, le test un verdict. Elle est couverte
par `tests/test_paywall_corpus_quota.py`, qui ne dépend d'aucune fixture — donc
tourne en CI, là où le reste du harnais ne peut pas.

### Fait — lot 1 d'étiquetage (2026-08-11) : 30 articles sur 120

Étiquetés à la main, répartis sur les 12 sources du corpus pour observer le
plus de sites possible avant d'approfondir une source.

| Source | Payants | Gratuits | Source | Payants | Gratuits |
|---|---|---|---|---|---|
| novethic | 3 | 0 | lemonde | 1 | 1 |
| philomag | 1 | 2 | lefigaro | 2 | 1 |
| la-croix | 2 | 1 | mediapart | 2 | 0 |
| lesjours | 3 | 0 | liberation | 1 | 1 |
| cuisiner-jdf | 0 | 3 | telerama | 2 | 0 |
| contrepoints | 0 | 2 | bonpote | 0 | 2 |

Aucune source n'est encore complète, donc rien n'est mesurable : le harnais
skippe, sans rougir — c'est exactement le comportement que le correctif
ci-dessus a installé.

Deux observations de ce lot, à confirmer sur le suivant : **Cuisiner** rend
3 gratuits sur 3 alors qu'il figure au groupe « faux négatifs » ; **Les Jours**
et **Novethic** rendent 3 payants sur 3, donc leur quota de gratuits exigera
d'aller chercher plus loin dans le flux.

### Découvert — le corpus décroît, et l'étiquetage se périme avec lui

`labels.json` est versionné pour survivre au clone ; `html/` et `rss/` non. Or
le collecteur reconstruit le corpus **à partir des flux vivants**, dont la
fenêtre tourne vite. Mesuré le 2026-08-11 sur les 30 URL étiquetées du lot 1,
collectées 3 jours plus tôt : **14 sur 30 sont encore au flux**, et les
quotidiens sont à **0 sur 15** (Le Monde, Le Figaro, Libération, La Croix,
Télérama, Mediapart ont intégralement tourné).

Conséquence : dans un conteneur neuf, un label posé il y a plus de quelques
jours n'a plus de charge utile à mesurer, et une simple recollecte ne la rend
pas — elle ramène les articles *du jour*, qui sont non étiquetés. L'étiquetage
humain, le seul travail non automatisable du chantier, se dévalue tout seul.

La bonne nouvelle est que les pages, elles, restent servies hors flux. D'où
`--refetch-from-labels` (`build_paywall_corpus.py`), qui part de `labels.json`
— le vrai registre du corpus — au lieu du flux du jour, et re-fetch le HTML par
URL. Résultat sur les 120 articles : **90 HTML récupérés**, soit les 9 sources
dont la page est atteignable.

| Re-fetch par URL | Sources |
|---|---|
| récupéré (10/10) | novethic, philomag, la-croix, cuisiner-jdf, lefigaro, telerama, contrepoints, bonpote, lemonde\* |
| 403 anti-bot | lesjours, liberation |
| TooManyRedirects | mediapart |

Limite assumée du mode : le RSS d'un article sorti du flux est perdu sans
recours, donc ces cas se rejouent avec titre et description vides. Sans effet
tant que le niveau 2 est inerte, mais rédhibitoire pour qui voudrait mesurer le
niveau 2.

Deux constats de terrain, qui corrigent des affirmations antérieures de ce
document :

- **Mediapart est devenu inatteignable** (boucle de redirection) alors que la
  collecte du 2026-08-08 en tirait 9 signaux sur 10. La posture anti-bot d'une
  source change sans prévenir : le corpus ne décroît pas seulement par rotation
  des flux, mais aussi par durcissement des sources.
- **\*Le Monde répond 200 — mais ce n'est pas l'article.** Les 10 fichiers sont
  identiques, 3 038 octets, `<title>Client Challenge</title>` : une page de
  défi anti-bot servie avec un code de succès. C'est **pire que le 402** de la
  collecte précédente, qui au moins s'annonçait comme un échec. Ici
  `_fetch_html_head` accepte le 200, passe la page au niveau 1, qui n'y trouve
  évidemment aucun marqueur et conclut « gratuit ». Un faux négatif silencieux,
  indiscernable d'un article réellement sans marqueur.

  Conséquence à instruire côté production : si l'IP Railway est challengée de
  la même façon, tous les articles du Monde passent le niveau 1 sans signal.
  Et la piste « lire le 402 comme marqueur de paywall », laissée ouverte plus
  haut, est à écarter — le code varie d'une IP et d'un jour à l'autre.

### Mesuré — première matrice de confusion réelle (2026-08-11, 30 articles)

Corpus reconstitué par `--refetch-from-labels`, rejoué par `paywall_benchmark.py`
sur les 30 articles étiquetés. **C'est la première mesure du chantier appuyée
sur une vérité terrain humaine**, et elle tranche la question restée ouverte
depuis février : *a-t-on déjà un problème de faux positifs ?*

| Source | Articles | TP | FP | TN | FN |
|---|---|---|---|---|---|
| novethic | 3 | 3 | 0 | 0 | 0 |
| philomag | 3 | 1 | 0 | 2 | 0 |
| la-croix | 3 | 2 | 0 | 1 | 0 |
| lefigaro | 3 | 2 | 0 | 1 | 0 |
| cuisiner-jdf | 3 | 0 | 0 | 3 | 0 |
| contrepoints | 2 | 0 | 0 | 2 | 0 |
| bonpote | 2 | 0 | 0 | 2 | 0 |
| lemonde | 2 | 0 | 0 | 1 | 1 |
| liberation | 2 | 0 | 0 | 1 | 1 |
| telerama | 2 | 0 | 0 | 0 | 2 |
| mediapart | 2 | 0 | 0 | 0 | 2 |
| lesjours | 3 | 0 | 0 | 0 | 3 |
| **Global** | **30** | **8** | **0** | **13** | **9** |

**Réponse : non, pas de faux positif.** 0 FP sur 13 articles gratuits, dont les
4 du groupe piège (Contrepoints, Bon Pote). Le taux de faux négatifs est de
53 % (9 sur 17 payants).

Le correctif `@graph` est validé sur vérité terrain : **Novethic est à 3/3**,
là où il ne produisait aucun signal avant.

Les 9 faux négatifs se répartissent en deux familles, et une seule est un vrai
défaut de détection :

| Cause | FN | Détail |
|---|---|---|
| HTML inatteignable — le niveau 1 ne peut pas jouer | 6 | lesjours (3), mediapart (2), liberation (1) |
| HTML présent, aucun marqueur exploitable | 3 | telerama (2), lemonde (1) |

Sur les 3 derniers : Le Monde est le faux 200 décrit plus haut (page de défi,
donc en réalité un HTML inatteignable déguisé). Télérama, lui, est un vrai
angle mort : `og:article:content_tier` n'apparaît plus que sur **2 des 10**
pages collectées, contre 10/10 le 2026-08-08, et les deux articles payants
étiquetés n'en portent pas. Leur seul indice est un `tlr.user.subscriber ===
false` en JavaScript — qui décrit l'**utilisateur**, pas l'article, et ne peut
donc pas servir de marqueur.

Relevé des marqueurs sur les 90 HTML, à jour du 2026-08-11 :

| Marqueur | Sources qui l'émettent |
|---|---|
| `isAccessibleForFree` | la-croix 10/10, novethic 6/10, cuisiner-jdf 2/10, philomag 1/10 |
| `isPremium` | lefigaro 10/10, **cuisiner-jdf 10/10** |
| `og:article:content_tier` | telerama 2/10 (contre 10/10 le 2026-08-08) |

**Baseline volontairement non gelée.** `--write-baseline` encoderait les
accidents de collecte du jour — Mediapart devenu inatteignable, Télérama qui a
changé de balisage, Le Monde qui sert un défi. Une baseline doit se figer sur
un corpus stable et complètement étiqueté, sinon elle transforme une avarie
réseau en contrat d'anti-régression.

### Reste à faire

1. **Étiqueter à la main** le reste de `labels.json` (90 articles sur 120).
   Geste délibérément humain : un label déduit de l'algo ferait valider l'algo
   par lui-même. Le harnais mesure dès qu'une source est complète ; le quota
   3 payants / 3 gratuits se juge source par source, une fois son étiquetage
   terminé.
2. Geler la baseline (`paywall_benchmark.py --write-baseline`) et la reporter
   dans la description de PR — elle tranchera la question jamais résolue :
   a-t-on **déjà** un problème de faux positifs aujourd'hui ?
3. Instruire les faux négatifs restants : philomag (9 HTML sur 10 sans aucun
   signal déclaratif) et lesjours/liberation (HTML inaccessible → seul le
   niveau 2 peut jouer, et il est inerte).
4. Récupérer les 4 `paywall_config` custom en base pour que le harnais rejoue
   la prod, et le `feed_url` réel de Cuisiner
   (`SELECT name, feed_url FROM sources WHERE name ILIKE '%cuisin%'` ;
   `source_id` : `92a33ad2-fdcc-43b2-83dc-03d6b95c1199`).

---

## Pistes à valider ou invalider par les données

Aucune n'est acquise : elles se jugent sur le corpus, pas sur l'intuition.

- **Élargir les signaux déclaratifs du niveau 1.** C'est le niveau le plus
  fiable car le média déclare lui-même. Chercher dans le corpus HTML les
  marqueurs structurés au-delà des 3 patterns actuels (`isAccessibleForFree`,
  `og:article:content_tier`, `isPremium`) : autres champs schema.org, meta de
  plugins de restriction WordPress, attributs data, classes de conteneur
  paywall. **Chaque signal candidat doit être vérifié absent des articles
  gratuits du corpus** avant d'être retenu.
- **Normalisation du texte avant matching.** Hypothèse identifiée mais **non
  vérifiée** (aucun HTML réel n'a pu être inspecté) : les mots-clés du code
  utilisent l'apostrophe droite `'` (U+0027) alors que les CMS français
  génèrent l'apostrophe typographique `’` (U+2019). Si c'est confirmé,
  `"S'abonner"` ne matche jamais aucune source WordPress française. Ce fix
  élargit la reconnaissance de mots-clés existants sans en ajouter, donc il ne
  peut pas créer de faux positifs — c'est la piste au meilleur rapport
  risque/gain, à tester en priorité.
- **Revoir la liste de mots-clés** à partir des formulations réellement
  observées. Privilégier les formulations longues et spécifiques (« réservé à
  nos abonnés », « débloquer l'article ») aux mots isolés (« abonnés »,
  « premium ») qui apparaissent aussi dans des articles gratuits traitant de la
  presse ou des abonnements. Le groupe `false_positive_trap` du manifeste
  (Contrepoints, Bon Pote) existe pour ça.
- **Barème et seuil.** Le seuil à 5 impose deux signaux sur trois. Toute
  modification exige une justification chiffrée sur le corpus complet, impact
  FP des sources fonctionnelles inclus.
- **Angle mort de `seed_recent_content`** (`sync_service.py` l.249) : appelle
  `detect_paywall` avec `html_head=None` explicite, donc niveau 1 entièrement
  sauté pour les ~10 premiers articles d'une source fraîchement ajoutée.
  Évaluer le coût d'un fetch HTML sur ces 10 items avant de proposer.

Le custom par source reste un dernier recours, à justifier explicitement.

---

## Où se trouve le signal, par source

Relevé sur le corpus du 2026-08-08 (10 articles par source). Le RSS et le HTML
sont deux surfaces distinctes — et le constat le plus net de ce tableau est que
**le RSS ne porte aucun signal, nulle part**. Tout se joue sur le HTML.

| Source | Signal RSS | Signal HTML | Niveau qui décide |
|---|---|---|---|
| novethic | aucun | `isAccessibleForFree` dans `@graph` (6/10) | 1 — depuis le correctif `@graph` |
| philomag | aucun | `isAccessibleForFree` (1/10 seulement) | 1 quand présent, sinon aucun |
| la-croix | aucun | `isAccessibleForFree` (10/10, 5 payants / 5 gratuits) | 1 |
| lesjours | aucun | HTML inaccessible (403 Cloudflare) | aucun |
| cuisiner-jdf | aucun | `isAccessibleForFree: true` (2/10) | 1 quand présent |
| lemonde | aucun | HTML inaccessible (**402**) | aucun |
| lefigaro | aucun | `isPremium` JS (10/10, 6 payants / 4 gratuits) | 1 |
| lesechos | _hors corpus (403 anti-bot)_ | | |
| lepoint | _hors corpus (403 anti-bot)_ | | |
| mediapart | aucun | `isAccessibleForFree: false` (9/10) | 1 |
| liberation | aucun | HTML inaccessible (403) | aucun |
| telerama | aucun | `og:article:content_tier` (10/10, 5 free / 5 locked) | 1 |
| contrepoints | aucun | aucun marqueur | aucun (média gratuit — attendu) |
| bonpote | aucun | aucun marqueur | aucun (média gratuit — attendu) |

Lecture : sur les 9 sources dont le HTML est récupérable, 7 émettent un signal
déclaratif exploitable. Les faux négatifs restants ne viennent donc pas d'un
manque de mots-clés mais de trois causes distinctes — un signal illisible
(Novethic, corrigé), un HTML inaccessible (lesjours, liberation, lemonde), ou
un média qui ne déclare rien (philomag sur 9 articles sur 10).
