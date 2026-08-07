# Maintenance : refonte mesurée de la détection paywall

**Type** : Maintenance
**Statut** : 🟡 EN COURS — instrumentation posée, corpus bloqué par l'egress
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

### Bloqué — la collecte

La politique d'egress de l'environnement d'agent bloque tous les domaines de
presse (403 sur le CONNECT, `WebFetch` compris). Vérifiable à tout moment :

```bash
cd packages/api
PYTHONPATH=. python scripts/build_paywall_corpus.py --check
```

Sortie attendue une fois l'egress ouvert : `OK <slug> <feed_url>` pour les 14
sources. Tant qu'on lit `BLOQUÉ … ProxyError 403`, la collecte produirait un
corpus vide qu'on pourrait confondre avec « ces sources n'émettent aucun
signal ».

Deux entrées du manifeste demandent en plus un accès base, indisponible dans
cet environnement (`[secrets] aucune variable d'infra définie`, MCP Supabase
non connecté) :

- le `feed_url` réel de Cuisiner
  (`SELECT name, feed_url FROM sources WHERE name ILIKE '%cuisin%'` ;
  `source_id` connu par le catalogue repo : `92a33ad2-fdcc-43b2-83dc-03d6b95c1199`) ;
- les 4 `paywall_config` custom, à recopier dans le manifeste — sans eux le
  harnais rejoue la config par défaut et la baseline ne reflète pas la prod.

### Reste à faire

1. Collecter (`build_paywall_corpus.py`), puis **étiqueter à la main**
   `labels.json` — 3 payants et 3 gratuits minimum par source.
2. Geler la baseline (`paywall_benchmark.py --write-baseline`) et la reporter
   dans la description de PR. Elle répond à une question jamais tranchée :
   a-t-on déjà un problème de faux positifs aujourd'hui ?
3. Améliorer les niveaux 1 et 2 génériquement, chaque changement justifié par
   un chiffre sur le corpus complet.
4. Re-mesurer, documenter les pistes écartées et **pourquoi**.
5. Remplir la section « Où se trouve le signal, par source » ci-dessous.

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

À remplir après la collecte. Le RSS et le HTML sont deux surfaces distinctes :
un marqueur visible sur la page peut être absent du flux, et l'inverse arrive.

| Source | Signal RSS | Signal HTML | Niveau qui décide |
|---|---|---|---|
| _(à remplir après collecte)_ | | | |
