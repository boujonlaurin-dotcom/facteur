# Etude de faisabilite — Micro-service "Universal Source to RSS" — Mission 3

**Date**: 2026-02-27
**Auteur**: Agent @dev (workspace Conductor)
**Contexte**: Evaluer les options pour transformer n'importe quelle URL en flux RSS exploitable par le pipeline Facteur.

---

## 1. Resume executif

**Recommandation**: Architecture a 3 tiers, deployee progressivement:

| Tier | Solution | Cout | Sources couvertes | Effort |
|------|----------|------|-------------------|--------|
| **Tier 1** | Transformations natives dans le parser existant | **0 EUR/mois** | YouTube, Reddit, Substack, GitHub, Mastodon | ~2-3 jours |
| **Tier 2** | RSSHub self-hosted sur Railway | **~5-8 EUR/mois** | Twitter/X, Instagram (partiel), Telegram, 1000+ sites | ~1 jour deploy |
| **Tier 3** | Crawl4AI pour sites sans RSS | **~10-20 EUR/mois** | Sites web quelconques | ~3-5 jours |

**Ne PAS commencer par Firecrawl** (SaaS payant, 16-83 EUR/mois) ni par un micro-service custom. Commencer par le Tier 1 (effort minimal, impact maximal) puis ajouter RSSHub si besoin.

---

## 2. Evaluation des 4 technologies

### 2.1 RSSHub — Generateur RSS open-source (Node.js)

**Verdict: RECOMMANDE pour Tier 2**

| Critere | Detail |
|---------|--------|
| **Couverture** | 1000+ routes pre-construites (YouTube, Reddit, Twitter/X, Instagram, Telegram, GitHub, etc.) |
| **Hosting** | Self-hosted via Docker (`diygod/rsshub`) |
| **Stack** | Node.js (pas de headless browser pour la plupart des routes) |
| **RAM** | ~512MB-1GB (sans Puppeteer), ~2GB (avec Puppeteer pour sites JS-rendered) |
| **CPU** | Minimal (Node.js event loop) |
| **Disque** | ~500MB image Docker |
| **Maintenance** | Active (27k+ stars GitHub, mises a jour frequentes) |
| **Licence** | MIT |
| **Railway** | Template one-click disponible: `railway.com/deploy/rsshub` |

**Routes pertinentes pour Facteur:**

| Plateforme | Route RSSHub | Authentification requise |
|------------|-------------|------------------------|
| YouTube (channel) | `/youtube/channel/:id` | Non |
| Reddit (subreddit) | `/reddit/subreddit/:name` | Non |
| Twitter/X | `/twitter/user/:id` | Non (Web API interne) |
| Instagram | `/instagram/user/:id` | Oui (credentials) |
| Telegram | `/telegram/channel/:name` | Non |
| GitHub releases | `/github/repos/:user/:repo/releases` | Non |
| Medium | `/medium/user/:id` | Non |

**Avantages:**
- Couvre la majorite des plateformes demandees SANS scraping
- Template Railway pre-configure (deploy en 2 clics)
- Pas de headless browser pour YouTube/Reddit/Twitter
- API REST simple: `GET /youtube/channel/UCxxx` → RSS XML

**Inconvenients:**
- Certaines routes dependent d'APIs tierces non-officielles (fragiles)
- Twitter/Instagram peuvent casser si la plateforme change son API interne
- Pas de scraping generique (sites web sans RSS)

---

### 2.2 RSS-Bridge — Generateur RSS open-source (PHP)

**Verdict: ALTERNATIVE a RSSHub (moins recommande)**

| Critere | Detail |
|---------|--------|
| **Couverture** | 200+ "bridges" (YouTube, Reddit, Twitter, Telegram, etc.) |
| **Stack** | PHP 7.4+ (leger, pas de headless browser) |
| **RAM** | ~128-256MB (tres leger) |
| **Maintenance** | Active mais communaute plus petite que RSSHub |
| **Licence** | Unlicense |

**Avantages:**
- Tres leger en ressources
- Pas de database requise
- Simple a deployer

**Inconvenients:**
- Moins de routes que RSSHub (200 vs 1000+)
- Communaute plus petite, mises a jour moins frequentes
- PHP (pas dans notre stack — Python/Node)
- Interface web uniquement (pas d'API REST propre)

**Conclusion**: RSSHub est superieur en couverture et en API. RSS-Bridge n'apporte rien de plus.

---

### 2.3 Crawl4AI — Scraper open-source (Python)

**Verdict: RECOMMANDE pour Tier 3 (sites sans RSS)**

| Critere | Detail |
|---------|--------|
| **Usage** | Scraping de pages web quelconques → extraction structuree |
| **Stack** | Python + Playwright (headless Chromium) |
| **RAM** | ~1-2GB (Chromium headless) |
| **CPU** | ~0.5-1 vCPU par crawl concurrent |
| **Disque** | ~2-3GB (image Docker avec Chromium) |
| **shm-size** | 1-3GB recommande pour le headless browser |
| **Licence** | Apache 2.0 |

**Avantages:**
- Python natif (meme stack que notre backend)
- Extraction LLM-assistee integree (peut utiliser un LLM pour identifier les "articles" dans le HTML)
- Async natif
- Gere le JavaScript rendering (Playwright)

**Inconvenients:**
- Necessite un headless browser (lourd en RAM)
- Pas de routes pre-construites (il faut ecrire les extracteurs)
- Anti-bot detection a gerer manuellement
- Latence elevee (~3-10s par page)

**Cas d'usage ideal**: Sites web qui n'ont pas de RSS et qui ne sont pas couverts par RSSHub. Exemples: blogs custom, sites de niche, newsletters sans flux.

---

### 2.4 Firecrawl — API SaaS de scraping

**Verdict: NON RECOMMANDE pour le moment**

| Critere | Detail |
|---------|--------|
| **Type** | SaaS (API cloud) + version open-source |
| **Pricing cloud** | Hobby: 16 EUR/mois (500 credits), Standard: 83 EUR/mois (3000 credits) |
| **Self-hosted** | Open-source (Apache 2.0) mais "pas production-ready" selon la communaute |
| **RAM self-hosted** | ~2-4GB (headless browser + workers) |

**Pourquoi NON recommande:**
- Le pricing cloud est eleve pour notre volume (chaque scrape = 1 credit)
- La version self-hosted n'est pas mature pour la production
- Crawl4AI couvre le meme besoin en open-source pour 0 EUR de licence
- RSSHub couvre deja 90% des plateformes demandees sans scraping

**Quand reconsiderer**: Si Crawl4AI ne suffit pas pour des sites complexes (anti-bot agressif, CAPTCHAs) ET que le volume justifie 83 EUR/mois.

---

## 3. Estimation des couts Railway

### Tarifs unitaires Railway (fevrier 2026)

| Ressource | Prix |
|-----------|------|
| RAM | $0.01389/GB/heure (~$10/GB/mois) |
| vCPU | $0.02779/vCPU/heure (~$20/vCPU/mois) |
| Disque | $0.000216/GB/heure (~$0.16/GB/mois) |
| Egress | $0.05/GB |
| **Hobby plan** | $5/mois inclus |
| **Pro plan** | $20/mois/seat inclus |

### Scenario A: Tier 1 seul (transformations natives)

**Cout: 0 EUR supplementaire** — integre dans le backend existant, aucun service additionnel.

### Scenario B: Tier 1 + RSSHub sur Railway

| Composant | RAM | vCPU | Cout/mois |
|-----------|-----|------|-----------|
| RSSHub (sans Puppeteer) | 512MB | 0.25 vCPU | ~$5 RAM + ~$5 CPU = **~$10** |
| Disque (image + cache) | 1GB | - | ~$0.16 |
| **Total** | | | **~$10/mois** |

Avec le Hobby plan ($5 inclus): **~$5/mois de surplus**.
Avec le Pro plan ($20 inclus): **inclus dans le forfait**.

### Scenario C: Tier 1 + RSSHub + Crawl4AI

| Composant | RAM | vCPU | Cout/mois |
|-----------|-----|------|-----------|
| RSSHub | 512MB | 0.25 vCPU | ~$10 |
| Crawl4AI (cron, pas always-on) | 2GB pic | 0.5 vCPU pic | ~$5-15 (selon frequence) |
| **Total** | | | **~$15-25/mois** |

**Note**: Crawl4AI peut tourner en cron job (pas always-on). Si on scrape 100 sites 1x/jour pendant ~10min, le cout est tres reduit (~$2-5/mois).

### Projection par nombre de sources

| Sources custom | Tier 1 (natif) | Tier 2 (+ RSSHub) | Tier 3 (+ Crawl4AI) |
|----------------|---------------|--------------------|--------------------|
| 100 (beta) | $0 | ~$5-10 | ~$10-15 |
| 500 (lancement) | $0 | ~$5-10 | ~$15-25 |
| 2000 (croissance) | $0 | ~$10-15 | ~$25-40 |

Les couts scalent peu car RSSHub/Crawl4AI servent des flux caches, pas des requetes a la demande.

---

## 4. Architecture recommandee

```
┌─────────────────────────────────────────────────────┐
│               FACTEUR APP (Mobile)                   │
│  User colle une URL quelconque                      │
└──────────────┬──────────────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────────────┐
│         FACTEUR API (Backend existant)               │
│                                                      │
│  POST /api/sources/detect                           │
│    → SourceService.detect_source(url)               │
│                                                      │
│  ┌─ TIER 1: Transformations natives ──────────────┐ │
│  │  YouTube → API v3 → channel_id → Atom feed    │ │
│  │  Reddit  → regex → /.rss suffix               │ │
│  │  Substack → /feed suffix                       │ │
│  │  GitHub  → /releases.atom                      │ │
│  │  Mastodon → .rss suffix                        │ │
│  └────────────────────────────────────────────────┘ │
│                                                      │
│  Si Tier 1 echoue:                                  │
│  ┌─ TIER 2: RSSHub Proxy ─────────────────────────┐ │
│  │  Appel HTTP vers RSSHub self-hosted            │ │
│  │  rsshub.internal/twitter/user/xxx              │ │
│  │  rsshub.internal/instagram/user/xxx            │ │
│  │  → Retourne RSS XML                            │ │
│  └────────────────────────────────────────────────┘ │
│                                                      │
│  Si Tier 2 echoue:                                  │
│  ┌─ TIER 3: Crawl4AI Scraper (futur) ────────────┐ │
│  │  Scrape la page web                            │ │
│  │  Extraction structuree (titre, date, lien)     │ │
│  │  Generation d'un flux RSS synthetique          │ │
│  │  Cache et MAJ periodique                       │ │
│  └────────────────────────────────────────────────┘ │
│                                                      │
│  → Retourne feed_url au pipeline RSS existant       │
└──────────────┬──────────────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────────────┐
│         PIPELINE RSS EXISTANTE                       │
│  Sync → feedparser → Content DB → Digest            │
└─────────────────────────────────────────────────────┘
```

### Principe: sidecar, pas micro-service

Le Tier 1 est integre dans le backend existant (`rss_parser.py`). Le Tier 2 (RSSHub) est un service Railway a cote, appele en HTTP interne. Pas besoin de creer un micro-service custom.

---

## 5. Faisabilite par plateforme

| Plateforme | Tier | Solution | Effort | Notes |
|------------|------|----------|--------|-------|
| **YouTube** | 1 | API v3 (`channels?forHandle=@xxx`) | ~8-12h | Necessite API key Google (gratuit, 10k calls/jour) |
| **Reddit** | 1 | Regex URL → `.rss` suffix | ~2-4h | Feed Atom natif, 25 entries, aucun rate limiting |
| **Substack** | 1 | `/feed` suffix (existe deja dans common suffixes) | ~1h | Verifier que ca fonctionne |
| **GitHub** | 1 | `/releases.atom` ou `/commits.atom` | ~2h | Feed Atom natif |
| **Mastodon/Fediverse** | 1 | `.rss` suffix sur profil | ~1h | RSS natif |
| **Medium** | 1 | `/@user/feed` | ~2h | Feed RSS natif (parfois bloque) |
| **Twitter/X** | 2 | RSSHub `/twitter/user/:id` | ~0.5h (config) | Web API interne (fragile si X change) |
| **Telegram** | 2 | RSSHub `/telegram/channel/:name` | ~0.5h (config) | Channels publics uniquement |
| **Apple Podcasts** | 1 | Parser le feed URL depuis le HTML | ~3h | `<meta name="apple-itunes-app">` contient le feed |
| **Spotify Podcasts** | 2 | RSSHub `/spotify/show/:id` | ~0.5h (config) | Route RSSHub existante |
| **Instagram** | 2 | RSSHub (avec credentials) | ~2h (config) | Fragile, necessite cookies Instagram |
| **TikTok** | 2 | RSSHub `/tiktok/user/:id` | ~1h (config) | Anti-bot agressif, fiabilite variable |
| **LinkedIn** | 3 | Crawl4AI (si necessaire) | ~1-2 jours | Pas de RSS, scraping complexe |
| **Sites web generiques** | 3 | Crawl4AI + extraction LLM | ~3-5 jours | Fallback universel |

---

## 6. Roadmap phasee

### Phase 1 — Tier 1: Transformations natives (Semaine 1)

**Objectif**: Debloquer YouTube et Reddit immediatement.

| Tache | Effort | Impact |
|-------|--------|--------|
| Fix Reddit (URL → `.rss`) | ~2-4h | Deblocage immediat |
| Fix YouTube (API v3 pour channel_id) | ~8-12h | Deblocage immediat |
| Verifier Substack/Medium/GitHub | ~2h | Quick wins |
| **Total** | ~2-3 jours | ~60-70% des echecs resolus |

### Phase 2 — Tier 2: RSSHub (Semaine 2-3)

**Objectif**: Couvrir Twitter/X, Telegram, podcasts via RSSHub.

| Tache | Effort | Impact |
|-------|--------|--------|
| Deploy RSSHub sur Railway (template) | ~2h | Infrastructure |
| Integrer RSSHub comme fallback dans `rss_parser.py` | ~4h | Twitter/X, Telegram, Spotify |
| Configurer les routes prioritaires | ~2h | Selon donnees Mission 2 |
| **Total** | ~1-2 jours | ~80-90% des echecs resolus |

### Phase 3 — Tier 3: Crawl4AI (Mois 2+, si necessaire)

**Objectif**: Scraping generique pour sites web sans RSS.

| Tache | Effort | Impact |
|-------|--------|--------|
| Deploy Crawl4AI sur Railway | ~4h | Infrastructure |
| Ecrire le generateur RSS synthetique | ~2 jours | Sites generiques |
| Monitoring (detection de changement de structure) | ~1 jour | Fiabilite |
| **Total** | ~3-5 jours | ~95%+ des echecs resolus |

**Declencheur Phase 3**: Lancer uniquement si les donnees Mission 2 montrent une demande significative pour des sites non couverts par les Tiers 1-2.

---

## 7. Risques et mitigations

| Risque | Probabilite | Impact | Mitigation |
|--------|------------|--------|------------|
| YouTube API v3 quota depasse (10k/jour) | Faible | Moyen | Cache les channel_id resolus en DB |
| Routes RSSHub cassees (changement API Twitter/Instagram) | Moyenne | Moyen | Monitoring + fallback vers Tier 3 |
| Rate limiting Reddit | Faible | Faible | User-Agent Chrome, delai entre requetes |
| Crawl4AI bloque par anti-bot | Moyenne | Moyen | Rotation User-Agent, headers realistes |
| Cout Railway depasse le budget | Faible | Faible | RSSHub est leger (~$5-10/mois) |

---

## 8. Decision finale

| Question du brief | Reponse |
|-------------------|---------|
| **Firecrawl self-hosted vs cloud?** | Ni l'un ni l'autre. RSSHub + Crawl4AI couvrent le meme besoin pour moins cher |
| **Crawl4AI comme alternative?** | Oui, mais en Tier 3 seulement (sites generiques). RSSHub couvre le gros du besoin |
| **Frequence de scraping?** | Tier 1-2: aligne sur le sync RSS existant (30min). Tier 3: 1x/4h ou 1x/jour |
| **Format de sortie?** | RSS/Atom standard consomme par le pipeline existant (feedparser) |
| **Monitoring?** | Hash du contenu scrape. Si 3 scrapes consecutifs retournent des structures differentes → alerte |
| **Cout Railway pour 500 sources?** | ~$5-10/mois (Tier 1 gratuit + RSSHub) |

---

**Sources de recherche:**
- [Firecrawl Pricing](https://www.firecrawl.dev/pricing)
- [RSSHub Deployment Docs](https://docs.rsshub.app/deploy/)
- [RSSHub Railway Template](https://railway.com/deploy/rsshub)
- [Crawl4AI Docker Deployment](https://docs.crawl4ai.com/core/docker-deployment/)
- [RSS-Bridge GitHub](https://github.com/RSS-Bridge/rss-bridge)
- [Railway Pricing](https://railway.com/pricing)

---

*Genere par Agent @dev — Mission 3 du brief "Diagnostic RSS Sources"*
