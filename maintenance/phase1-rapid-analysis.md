# Phase 1 — Analyse RAPIDE des ajouts de sources échoués (prod, 09/07/2026)

> Source : `failed_source_attempts` (8) + `source_search_logs` (270, dont 47 `result_count=0`
> OU `abandoned`). Requêtes lecture seule via Supabase MCP. Complété par la carte du pipeline
> (`rss_parser.detect()` 9 étapes, `SmartSourceSearchService` 5 layers, `SyncService`).

## Parc (contexte)
- 313 sources actives : **247 non-curées** (custom) + 66 curées.
- 105 users avec sources ; 236 liens `user_sources.is_custom`.
- `failed_source_attempts` : **8** lignes (19/06 → 03/07), toutes `keyword` / `smart-search`, `error_message` NULL → ce sont des **abandons** (l'utilisateur a cherché puis n'a pas ajouté), pas des erreurs de résolution.
- `source_search_logs` : 270 recherches (26/04 → 09/07) ; **39** à 0 résultat, **8** abandonnées → **47** signaux problématiques (≈ 40 requêtes distinctes).

## Le vrai breakdown des ~47 signaux (≠ « sites sans RSS »)

| Catégorie | Volume | Nature réelle | Volet |
|---|---|---|---|
| **YouTube — rafale 30/06 + isolés** | ~17-18 req. (esa, micode, mediapart, urbania, stardust, hugo lisoir, clement viktorovitch, les numeriques, c ce soir, christophe andré, tech sama, esprit critique…) | `content_type="youtube"`, **layer `catalog` seul appelé**, 0 résultat. Les chaînes YouTube **ONT** un RSS par chaîne. | **`fixed_since`** — bug corrigé par PR #939 (le filtre youtube force désormais le layer). À re-vérifier par le rescue. |
| **Reddit** | 5 req. (r/ai, r/worldnews, artificial_intelligence, ai, une URL reddit) | `content_type="reddit"`, 0 résultat. Reddit expose `/r/x/.rss` (déjà géré par `detect()` étape 1). | Gap de **résolution** (probable garde `content_type`/short-circuit), pas no-feed. |
| **« Trouvé mais abandonné »** | 8 req. | **4 = match parfait** (Libération, L'Équipe, Le Grand Continent, BDM → feed valide **déjà renvoyé**, user abandonne) → **UX/confiance de l'add**. **4 = mauvaise entité** (Snowball→GmbH allemand, insight→BDM, hypertext→MDN, esprit critique→ambigu) → **relevance**. | **Ni l'un ni l'autre = no-feed.** UX add + relevance. |
| **Vrai « URL collée → 0 résultat »** | **4 sites** | usine-digitale.fr (×5 lignes, Infopro Digital / **DataDome** probable) ; monpetithoublon.com (blog tricot, sans doute WP) ; autobrasseur.fr (blog brassage, sans doute WP) ; betterclinicianproject.com (**URL polluée `utm_*`+`fbclid`** → échec parse, pas no-feed). | **Seuls candidats volet B** — et 1 seul (usine-digitale) est vraiment « dur ». |
| **Typos / non-sources** | goofle, vakitamefia, « vu », « ai », « esa » | requêtes invalides / trop courtes. | `invalid`. |

### Probes /feed/ (indicatif, UA non fiable ≠ curl-cffi backend)
- monpetithoublon.com/feed/ → HTTP 500 · autobrasseur.fr/feed/ → 404 · usine-digitale.fr/rss → 403.
  Non concluant (WebFetch n'imite pas le fingerprint Chrome de `_fetch_with_impersonation`) ; à confirmer par le rescue avec budget curl-cffi.

## Intégrité de l'échantillon (audit de biais, demandé par le PO)

Question PO : « quasi aucun média classique en échec — est-ce un biais de la pipeline de log ? »
Vérifié côté **succès** + côté **code**. Conclusion : **pas de masse cachée d'échecs médias classiques**, mais **un vrai angle mort temporel**.

- **Le média classique DOMINE les ajouts et réussit** : 173 ajouts `article` (70 % du total), **100 % synchronisés (0 `never_synced`)** ; recherches `article` **~90 % succès** (209 → 186 succès). Public Sénat, StreetPress, L'Humanité, Le Nouvel Obs, Numerama, Cerveau & Psycho… ajoutés sans souci. Son absence des *échecs* = il **résout**, pas un log manquant. Il apparaît d'ailleurs dans les échecs in-window (Libération/L'Équipe/Le Grand Continent = « trouvé mais abandonné » ; usine-digitale = zéro-résultat).
- **La capture est complète depuis le 26/04** : l'app route **clés ET URLs collées via `smart-search`** (d'où les URLs pleines dans `source_search_logs` avec `layers_called`), et `smart-search` **logge TOUJOURS** (succès + zéro-résultat, via `_finalize()`, best-effort). ⇒ les échecs d'URL média classique **sont capturés** (usine-digitale/monpetithoublon/autobrasseur/betterclinician y sont).
- **Le tableau `failed_source_attempts` = miroir d'abandon uniquement** : ses 8 lignes = exactement les 8 recherches `abandoned`. D'où « tout en `endpoint=smart-search` » (rien de `custom`/`detect`) — bénin.
- **Angle mort #1 (temporel, majeur)** : `source_search_logs` créé le **26/04/2026** (commit `4558ada5`), `failed_source_attempts` le **21/02** (`f0758b12`, abandon seulement). Or les ajouts remontent au **26/01** → **~118 ajouts custom (91 `article`) de janv→avr sans aucune visibilité échec**. ⇒ formuler « ~4 sites no_feed » comme **« ~4 sur la fenêtre observable 26/04→09/07 (~11 sem.) »**, pas all-time.
- **Angle mort #2 (abandon client-dépendant)** : `abandoned=true` ne se pose que si le client Flutter appelle `/search-abandoned` en `dispose()` → crash/background sous-comptent. Vrai abandon ≥ 8 (ne change pas les catégories, juste la magnitude du problème UX).
- **Mineur** : rate-limit 429 et `/detect` keyword-0-result non loggés (mais ce ne sont pas des signaux no-feed).

## Headline (ce qui change la décision volet B)

1. **La population réelle « site sans RSS découvrable » sur TOUT l'historique (avril→juillet) = ~4 sites, dont 1 seul vraiment dur (usine-digitale).** Dimensionner une infra de scraping/RSSHub/SaaS pour « 250-500 sources sans RSS » est **hors de proportion** avec la donnée observée aujourd'hui.
2. **Les échecs sont dominés par des causes NON-ingestion** : (a) bug youtube déjà corrigé, (b) gap de résolution reddit, (c) **UX de l'add** (4 matchs parfaits abandonnés), (d) **relevance** (4 mauvaises entités), (e) hygiène d'URL (strip `utm_*`/`fbclid`).
3. **`detect()` est DÉJÀ riche** (9 étapes : overrides, transforms Substack/Medium/Mastodon, reddit `.rss`, résolution chaîne YouTube, autodiscovery `<link>`+`<a>`, 16 suffixes en parallèle, suivi de page d'index, **anti-bot curl-cffi**). Les **vrais trous** = **WordPress REST API** et **sitemaps** (absents), + strip tracking-params, + le fait que **`SyncService` (refresh) n'a PAS d'anti-bot** (httpx simple) → un feed anti-bot trouvé à l'add peut casser au sync.
4. Contrainte d'archi : `sources.feed_url` est **UNIQUE NOT NULL** → tout chemin non-RSS doit soit produire une **feed_url synthétique** (backend génère le flux), soit introduire un discriminateur **`fetch_method`** + parseur alterne dans `SyncService`. Aucun `fetch_method` n'existe aujourd'hui.
5. Produit : **aucun article « tampon » n'est créé à l'add** aujourd'hui (1er sync = background task). L'effet « wow » est une **capacité nouvelle** quel que soit le mode d'ingestion.

## Implication pour trancher (à valider avec l'Architecte BMAD)
Le problème n'est pas « choisir un convertisseur site→RSS ». C'est une **cascade de résolution à paliers, du moins cher au plus cher**, où le scraping+LLM n'est que le **dernier palier** pour la vraie longue traîne (classe usine-digitale). Détail + comparatif des options dans le doc de décision (Phase 2).
