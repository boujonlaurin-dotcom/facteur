# Décision technique — Ingérer les sites « sans RSS » à l'échelle

> Brief de décision pour l'Architecte BMAD. S'appuie sur : (1) l'analyse Phase 1 des échecs
> réels prod (`phase1-rapid-analysis.md`), (2) la carte du pipeline actuel (`detect()` 9 étapes,
> `SmartSourceSearchService`, `SyncService`), (3) recherche web 07/2026 (3 axes, sources citées en bas).
> **Périmètre : 1 seule PR** (rescue + comblements Tier-0/1 + ce doc). Le scraping lourd est différé, pas scindé en PR.

---

## 0. Le cadrage que la donnée impose

Le problème posé (« scaler les sources RSS non-disponibles à 250-500 ») **ne correspond pas à la donnée observée**. Sur la **fenêtre observable (26/04→09/07, ~11 sem.)**, la population « URL collée → 0 flux découvrable » = **~4 sites**, dont **1 seul vraiment dur** (usine-digitale.fr / Infopro, DataDome probable). Les autres échecs sont : bug YouTube **déjà corrigé (#939)**, gap de résolution Reddit, **UX de l'add** (4 matchs parfaits abandonnés), **relevance** (4 mauvaises entités), et **hygiène d'URL** (tracking params).

> **Intégrité de l'échantillon (audité) :** la capture des échecs est **complète depuis le 26/04** (l'app route clés + URLs collées via `smart-search`, qui logge tout, succès + zéro-résultat) ; le média classique **domine les ajouts (173, 70 %) et réussit à 100 %** — pas de masse cachée d'échecs. **Caveat honnête pour l'Architecte :** angle mort **avant le 26/04** (`source_search_logs` n'existait pas) → ~118 ajouts janv→avr sans visibilité échec ; donc « ~4 sites » = **sur la fenêtre observable**, pas all-time. Abandon possiblement sous-compté (dépend du client). Détail : `phase1-rapid-analysis.md`.

⇒ La bonne question n'est pas « quel convertisseur site→RSS acheter/héberger ? » mais **« quelle cascade de résolution, du moins cher au plus cher, avec le scraping en dernier recours ? »**. Sur-dimensionner une infra pour un besoin réel de ~1 site serait disproportionné.

De plus, `detect()` est **déjà** une cascade à 9 étapes (overrides, transforms Substack/Medium/Mastodon, Reddit `.rss`, résolution chaîne YouTube, autodiscovery `<link>`+`<a>`, 16 suffixes //, suivi de page d'index, **anti-bot curl-cffi**). Les **vrais trous** sont ciblés : **WordPress REST**, **sitemaps**, **strip tracking-params**, gap Reddit — et le fait que **`SyncService` (refresh) n'a pas d'anti-bot** (httpx simple).

---

## 1. Architecture recommandée — cascade à 3 paliers

### Palier 0 — Hygiène & régressions (coût ~0, plus gros ROI immédiat)
- **Normaliser l'URL collée** avant résolution : strip `utm_*`, `fbclid`, `gclid`, `igshid`, `mc_cid`, fragments. (répare la classe betterclinicianproject)
- **Vérifier via le rescue** que #939 a bien fermé le bug YouTube `content_type` (rejouer la rafale 30/06 → attendu `fixed_since`).
- **Fermer le gap Reddit** (`content_type="reddit"` → 0 résultat alors que `/r/x/.rss` est géré par `detect()` étape 1).
- (UX de l'add : 4 matchs parfaits abandonnés → workstream mobile séparé, hors de cette PR backend, mais à signaler au PO.)

### Palier 1 — Endpoints structurés natifs (coût ~0, aucune nouvelle infra, s'intègre à feedparser + SyncService)
Ajouter 2-3 rungs à la cascade `detect()` existante :
- **WordPress REST** : probe `/wp-json/wp/v2/posts?per_page=20&orderby=date&order=desc` → `content.rendered` (corps HTML complet) + `date` + `link` en JSON, sans auth, sur **~59 % de part CMS** (WordPress). Réalistement **70-85 % de la longue traîne FR** est WP. Actif par défaut ; désactivé seulement en minorité (plugins sécurité / règles serveur). Plafond `per_page=100`, page 1 suffit pour un digest. **Fallback plus robuste que `/feed/`** (marche même si `/feed/` est cassé/UA-bloqué) **et** fournit le payload pour les **articles tampons** à l'add.
- **Sitemap / News-sitemap** : robots.txt `Sitemap:` → `/sitemap.xml` → `/sitemap_index.xml` → `/news-sitemap.xml`. Donne URL + date (+ `news:title` pour le News-sitemap) = feed de nouveautés ; le corps nécessite encore un fetch page. News-sitemap = fenêtre ~2 j (vue roulante, pas archive).
- (JSON Feed : adoption trop faible en 2026 — bonus opportuniste dans la ladder, jamais une cible.)

**Intégration sans migration (recommandé) :** exposer une résolution non-RSS comme **feed_url synthétique interne** servie par notre backend (ex. endpoint qui rend WP-REST/sitemap en RSS). `sources.feed_url` reste **UNIQUE NOT NULL**, `SyncService` **inchangé** (fetch d'une URL → feedparser). Le « convertisseur » devient **notre propre petit endpoint**, pas un service tiers.

### Palier 2 — Scraping dernier recours (différé, gated sur la donnée)
Pour la vraie traîne non-WP / sans sitemap uniquement. **Ne rien construire/héberger maintenant** (demande réelle ≈ 1 site). Réévaluer **si** le job hebdo de rescue montre que la population `no_feed` grossit. Défaut privilégié le jour venu : **sélecteurs générés par LLM (Mistral déjà intégré) stockés en JSONB + `trafilatura`**, ou **Firecrawl on-demand** — parce qu'ils s'intègrent au pipeline sans faire tourner un service PHP/Node 24/7 pour une poignée de sites. Ce palier **exige** alors un discriminateur `fetch_method` sur `sources` + branche dans `SyncService.process_source()` (migration additive expand-contract sur la DB prod partagée).

**Cas anti-bot durs (classe usine-digitale / DataDome) : non-objectif assumé.** Aucune option ci-dessous ne bat DataDome de façon fiable. Voie de contournement existante = catalogue curé manuel, ou le chemin `premium_connection_config` (WebView login).

---

## 2. Comparatif des options « Palier 2 » (recherche 07/2026, citée)

| Option | Modèle | Coût @~500 | Anti-bot DataDome | API / auto-provision | Fit longue traîne FR | Intégration | Verdict |
|---|---|---|---|---|---|---|---|
| **Maison — WP REST + sitemap** (Palier 1) | endpoints natifs | **~0 €** | N/A (sites ouverts) | natif | **70-85 %** | rungs sur `detect()` + feed synthétique | **PRIMAIRE** |
| **Maison — scrape + sélecteurs LLM + trafilatura** | scrape maison | tokens Mistral (déjà là) + CPU | non (sauf proxy ajouté) | natif | la traîne résiduelle | `fetch_method` + parseur alterne | **défaut Palier 2** |
| **Firecrawl** (/scrape,/extract) | API scrape+extract | 83→399 $/mo selon stealth | **partiel** (échoue CF Turnstile dur) | API (pas un feed persistant) | tout site ouvert | appel depuis worker | alt Palier 2 (on-demand) |
| **Jina Reader** | API scrape | ~4,5 $/mo tokens | **NON (explicite)** | API | sites ouverts | appel depuis worker | extracteur de corps pas cher, **pas** pour anti-bot |
| **RSS-Bridge** self-host | sélecteurs CSS génériques | PHP ~64 Mo Railway | **non** | construire l'URL/source | config par site | service à opérer | **différé** (un service pour ~1 site) |
| **RSSHub** self-host | route par site (code) | Node+Chromium lourd | partiel (Chromium, peu fiable) | **pas de mode générique** | CN-centrique, ~0 FR | écrire des routes TS | **rejeté** |
| **RSS.app** | SaaS feeds | ~83 $/mo (500) | non documenté | API (Pro, 1k ops/mo) | tout site | fetch feed URL | seulement si on externalise tout |
| **FetchRSS** | SaaS feeds | **24 $/mo (500)** | faible/non doc | API (gating non doc) | tout site | fetch feed URL | SaaS pas cher si externalisation |
| **PolitePaul** | SaaS feeds | ~65 $/mo (Premium) | JS+proxy, pas de claim CF/DD | **pas d'API create** | tout site | fetch feed URL | **disqualifié** (pas d'auto-provision) |

**Lectures clés :**
- **RSSHub = mauvais outil** : pas de mode générique, catalogue CN/global, footprint Node+Chromium. On écrirait une route TS par site FR — irréaliste.
- **RSS-Bridge = seul self-host avec mode générique** (`CssSelectorBridge`/`XPathBridge`/`FeedExpander`), léger, mais **travail de sélecteurs par site + zéro anti-bot + un service à opérer** pour une demande de ~1 site. Reconsidérable seulement si la traîne grossit **et** qu'on veut du config-driven (non-LLM).
- **SaaS (FetchRSS/RSS.app/PolitePaul)** : dépendance externe, coût par flux, **DataDome non garanti**, et surtout on **perd la maîtrise de `detect()`**. FetchRSS est le moins cher (24 $) mais PolitePaul n'a pas d'API (rédhibitoire pour l'auto-provision).
- **Firecrawl/Jina** : bons extracteurs de corps propre pour LLM ; Firecrawl a un anti-bot *partiel*, Jina **aucun**. Utiles comme brique du « Maison scrape » au Palier 2, pas comme feed persistant.

---

## 3. Produit — « ajout transparent + articles tampons »
Aujourd'hui **aucun article tampon** n'est créé à l'add (1er sync = background task). C'est une **capacité nouvelle** quel que soit le mode. Le Palier 1 la sert nativement : **WP REST renvoie les 20 derniers posts immédiatement** → on peut insérer ces `content` dès l'add (effet wow), là où RSS classique dépend du délai du background sync. C'est un argument fort de plus pour prioriser WP REST.

---

## 4. Ce qu'on demande à l'Architecte BMAD de trancher
1. **Feed synthétique interne (pas de migration)** vs **`fetch_method` + parseur alterne (migration)** pour brancher WP-REST/sitemap. Reco : synthétique pour Palier 1, `fetch_method` réservé au Palier 2.
2. Ordre exact des nouveaux rungs dans `detect()` et gestion du cache `HostFeedResolution` (TTL négatif 7 j déjà là).
3. Anti-bot au **sync** (aujourd'hui httpx nu) : faut-il porter le curl-cffi de `detect()` dans `SyncService` pour les feeds anti-bot trouvés à l'add ? (sinon ils cassent au refresh)
4. Périmètre exact de la PR unique (rescue + Palier 0 + Palier 1 WP-REST au minimum ; sitemap et tampons en option selon appétit).
5. Confirmer le **non-objectif DataDome** et le **gating du Palier 2** sur le job hebdo de rescue.

---

## Sources (recherche 07/2026)
- Self-host : [RSSHub repo](https://github.com/DIYgod/RSSHub) · [RSS-Bridge repo](https://github.com/RSS-Bridge/rss-bridge) · [CssSelectorBridge](https://github.com/RSS-Bridge/rss-bridge/blob/master/bridges/CssSelectorBridge.php) · [FeedExpander](https://rss-bridge.github.io/rss-bridge/Bridge_API/FeedExpander.html)
- SaaS/scrape : [RSS.app pricing](https://rss.app/pricing) · [FetchRSS prices](https://fetchrss.com/prices) · [PolitePaul prices](https://politepaul.com/en/prices) · [Firecrawl pricing](https://www.firecrawl.dev/pricing) · [Jina Reader](https://jina.ai/reader/)
- Natif : [W3Techs WordPress](https://w3techs.com/technologies/details/cm-wordpress) · [WP REST pagination](https://developer.wordpress.org/rest-api/using-the-rest-api/pagination/) · [Google News sitemap](https://developers.google.com/search/docs/crawling-indexing/sitemaps/news-sitemap) · [RSS autodiscovery](https://www.rssboard.org/rss-autodiscovery) · [SmartNews — strip UTM](https://publishers.smartnews.com/hc/en-us/articles/7917502346137)
