# Maintenance — Runbook de la jauge CTR ranking (`evaluate_feed_ranking.py`)

> **Date** : 2026-07-29
> **Branche** : `boujonlaurin-dotcom/reco-quality-entity-affinity-audit`
> **PR ciblée** : `main`
> **Type** : outillage de mesure (aucun réglage)
> **Script** : `packages/api/scripts/evaluate_feed_ranking.py`
> **Tests** : `packages/api/tests/scripts/test_evaluate_feed_ranking.py`
> **Doc sœur** : [`maintenance-reco-quality-step-up.md`](./maintenance-reco-quality-step-up.md)

## À quoi sert cette jauge

Croiser ce que le ranking a **livré** (`daily_digest.items`) avec ce que
l'utilisateur a **consommé** (`user_content_status.status = 'consumed'`), et en
sortir un CTR découpé par rang de sujet, slot, sujet, topic, entité et bande de
score.

C'est l'instrument de mesure des PRs de reco. Sans lui, tout réglage de scoring
est une conviction non testée.

## Pourquoi elle ne tournait pas (et ce qui a été réparé)

Trois défauts, tous silencieux — le script s'exécutait sans erreur et
retournait un rapport vide, ce qui se lit comme « pas de signal » et pas comme
« instrument cassé ».

1. **Le format de prod n'était pas lu.** La requête ne connaissait que
   `flat_v1` (`items` = tableau) et `topics_v1` (`items.topics[]`). Or 100 % des
   digests non-sereins des 30 derniers jours sont en `editorial_v3`
   (`items.subjects[]`) : 3 493 digests non-sereins + 1 069 sereins ; les seuls
   `topics_v1` restants (266) sont tous sereins, donc écartés par défaut.
   ⇒ **0 ligne**. Une CTE `editorial_items` a été ajoutée.
2. **Le dénominateur reposait sur `last_impressed_at`**, colonne écrite
   seulement au pull-to-refresh et au « déjà vu » manuel : ni impression ni
   position. Remplacée par `--denominator` (cf. section suivante).
3. **Un NULL non typé cassait la requête.** `(:mode IS NULL OR dd.mode = :mode)`
   avec `--mode` non fourni ⇒ `psycopg.errors.AmbiguousParameter: could not
   determine data type of parameter $3`. Corrigé par des `CAST` explicites.

Ajouté au passage : histogramme `format_version` en en-tête, pour qu'un futur
changement de format soit **bruyant** au lieu d'être silencieux.

## Les 3 dénominateurs

Le rapport publie **toujours les trois côte à côte**. Ne jamais en citer un seul
hors contexte.

| dénominateur | définition | mesuré en prod (30 j, non-sereins) |
|---|---|---|
| `all` | tout slot livré | **566 / 45 735 = 1,24 %** |
| `engaged` | slots des digests avec ≥ 1 consommé | **566 / 3 081 = 18,37 %** |
| `engaged-loo` (**défaut**) | slots des digests avec ≥ 1 consommé **autre que l'article mesuré** | **459 / 2 974 = 15,43 %** |

- **`all` mesure la distribution, pas la pertinence.** ~93 % des digests générés
  n'ont jamais eu un seul article consommé : le 1,24 % dit surtout que l'app
  n'est pas ouverte, et il écrase toute différence de ranking.
- **`engaged` est circulaire** : l'article consommé conditionne son propre
  dénominateur, ce qui gonfle mécaniquement le CTR.
- **`engaged-loo` dé-circularise** : l'article *i* n'est compté que si son
  digest a un consommé **autre que lui**. Conséquence à connaître : un digest
  avec exactement un article consommé ne contribue **aucun** numérateur (cet
  article est son propre conditionneur, donc exclu). C'est voulu.

Invariants de construction (testés) : `CTR(all) ≤ CTR(engaged)` — `engaged` ne
retire que des non-consommés — et `CTR(engaged-loo) ≤ CTR(engaged)` — le LOO ne
retire ensuite que des consommés.

### Conditionneurs rejetés, et pourquoi

- **`digest_completions`** — rejeté. **0 ligne sur 60 j** (58 all-time, dernière
  le 2026-05-10) **et** circulaire par construction : la ligne est insérée à
  `consumed/total ≥ 0,8` (`digest_service.py`), donc le CTR conditionné serait
  ≈ 100 % par définition. C'est écrit ici pour que personne ne le re-propose.
- **`morning_ritual_opened`** — 206 events / 34 users / 60 j, couvrant 2,5 % des
  digests. Utilisable en **tranche de robustesse**, jamais en filtre principal :
  la puissance statistique s'effondre.

## Lancer la jauge

```bash
cd packages/api
PYTHONPATH=. python scripts/evaluate_feed_ranking.py --days 30
PYTHONPATH=. python scripts/evaluate_feed_ranking.py --days 30 --tag pr1-before
PYTHONPATH=. python scripts/evaluate_feed_ranking.py --compare \
  ../../.context/feed-ranking-pr1-before-2026-07-29.json \
  ../../.context/feed-ranking-pr1-after-2026-08-05.json
```

Sorties appariées dans `.context/`, comme les harnais frères
(`evaluate_event_clustering.py`, `evaluate_veille_curation.py`) :
`feed-ranking-<tag>-<date>.json` (machine, consommé par `--compare`) et
`.md` (humain).

Options utiles : `--denominator {all,engaged,engaged-loo}`, `--mode`,
`--include-serene`, `--min-shown`, `--top`, `--row-limit`, `--no-write`.

> Pas de `--sweep` : contrairement aux deux autres harnais, ce script n'a aucun
> dial à balayer. Il mesure, il ne règle rien.

### ⚠️ Prérequis d'accès : RLS

`DATABASE_URL_RO` (`claude_analytics_ro`) **retourne 0 ligne** sur
`daily_digest`, `contents` et `user_content_status` : les trois tables ont
`relrowsecurity = true` et le rôle a `rolbypassrls = false`. Le script tourne
sans erreur et rapporte un CTR vide — le même faux négatif que le bug qu'il
vient de corriger.

Deux voies :

1. **Recommandé, décision PO** : `ALTER ROLE claude_analytics_ro BYPASSRLS;` sur
   la DB de prod. C'est un changement de permission prod, à faire
   explicitement, pas en passant.
2. **Contournement** : rejouer la requête via le MCP Supabase (rôle `postgres`,
   `rolbypassrls = true`). C'est ce qui a servi à valider la requête et à
   produire les chiffres de ce runbook.

## Biais connus (à ne pas maquiller)

- **Persistance des scores forward-only.** `score` / `pillar_scores` sont
  persistés sur `subjects[].actu_article` depuis cette PR seulement. Toute
  fenêtre antérieure au merge affiche une bande `missing` massive : c'est
  attendu. Le CTR **par sujet / entité / rang de sujet / slot** est en revanche
  **rétroactif** sur tout l'historique `editorial_v3`.
- **Les `extra_actu_articles` ne sont jamais scorés** — `actu_matcher` les trie
  sur `(thumbnail, published_at)`. Leur `score` restera `null` **pour toujours** :
  ce n'est pas un trou de données à combler mais une propriété du pipeline.
- **Le fallback clusters-vides** (`digest_selector`) produit des sujets sans
  score : `null` légitime.
- **Effet de position vs effet de ranking** : le rang 1 est aussi « À la Une »
  et occupe le haut de l'écran. La jauge ne peut pas séparer les deux sans une
  randomisation de position. Toute lecture du rang 1 doit le dire.
- **Puissance** : ~2 974 slots LOO sur 30 j, ~220 par rang de sujet ⇒ **±5 pp à
  95 %**. Un écart de 2 pp entre deux rangs n'est pas un signal.

## Première lecture (30 j au 2026-07-29, `engaged-loo`)

CTR par rang de sujet, slots `actu` :

| rang | slots | consommés | CTR |
|---:|---:|---:|---:|
| 1 | 215 | 66 | **30,7 %** |
| 2 | 225 | 43 | 19,1 % |
| 3 | 223 | 44 | 19,7 % |
| 4 | 227 | 32 | 14,1 % |
| 5 | 223 | 44 | 19,7 % |
| 6 | 226 | 49 | 21,7 % |
| 7 | 223 | 44 | 19,7 % |
| 8 | 219 | 49 | 22,4 % |
| 9 | 225 | 43 | 19,1 % |
| 10 | 223 | 34 | 15,3 % |

Slots `extra`, tous rangs confondus : **11 / 745 = 1,5 %** en LOO
(11 / 11 085 = 0,1 % en `all`).

Deux constats, à confirmer sur une deuxième fenêtre avant d'en tirer une
roadmap :

1. **Le rang 1 se détache (30,7 % vs ~19 %), le reste est plat.** Les rangs 2 à
   10 tiennent tous dans ±5 pp autour de 19 % — c'est-à-dire dans la barre
   d'erreur. Le re-ranking per-user n'a **aucun pouvoir discriminant mesurable
   au-delà du rang 1**. On ne peut pas encore dire si l'avantage du rang 1 vient
   du ranking ou de la position.
2. **Les `extra_actu_articles` sont un angle mort.** 11 085 slots livrés sur
   30 j pour 11 consommations : ~24 % des slots du digest, jamais scorés,
   quasiment jamais lus.

## Ce que la jauge ne mesure pas

- **Les surfaces hors digest** : Tournée, Veille, Flux Continu ont leurs propres
  chemins de scoring et ne sont pas dans `daily_digest.items`. Un levier qui ne
  bouge pas ici peut bouger là — c'est explicitement le cas des abonnements
  entités (cf. doc sœur).
- **Le rappel** : elle ne dit rien des bons articles jamais candidats.
- **La satisfaction** : `consumed` est un proxy de clic, pas de valeur.
