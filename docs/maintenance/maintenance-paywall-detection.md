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

### Reste à faire

1. **Étiqueter à la main** `labels.json` (120 articles, `"paid"` / `"free"`).
   C'est le seul geste qui reste et il est délibérément humain : un label
   déduit de l'algo ferait valider l'algo par lui-même. Le harnais refuse de
   mesurer tant que le quota 3 payants / 3 gratuits par source n'est pas tenu.
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
