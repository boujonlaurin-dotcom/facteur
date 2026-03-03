# Diagnostic YouTube & Reddit RSS — Mission 1

**Date**: 2026-02-27
**Auteur**: Agent @dev (workspace Conductor)
**Contexte**: Les beta-testeurs demandent YouTube et Reddit comme sources. Les deux echouent a l'ajout.

---

## Resume executif

| Source | Point de blocage | Cause racine | Fix estime |
|--------|-----------------|--------------|------------|
| **YouTube** | Bloc service-level (`source_service.py:411`) | 1) Bloc explicite dans le code 2) Meme sans le bloc, le parser echoue car YouTube JS-rend les pages handle/channel — plus de channelId dans le HTML serveur | ~8-12h |
| **Reddit** | Aucun handling Reddit dans le parser | 1) Pas de transformation URL → `.rss` 2) Reddit ne sert pas de `<link rel="alternate">` sur les pages HTML 3) Le suffixe `/.rss` n'est pas dans nos common suffixes | ~2-4h |

---

## 1. YouTube — Diagnostic detaille

### 1.1 Chemin d'echec actuel

```
User colle: youtube.com/@ScienceEtonnante
  → Router detect_source() [sources.py:122]
    → SourceService.detect_source(url) [source_service.py:408]
      → BLOC LIGNE 411-415:
        if "youtube.com" in url or "youtu.be" in url:
            raise ValueError("YouTube handles are currently disabled...")
      → FailedSourceAttempt logged
      → HTTP 400 retourne au client
```

**Le RSS parser (`rss_parser.py:107-274`) n'est JAMAIS appele.** Il contient 9 methodes de resolution channel_id, mais elles sont bypassees par le bloc service.

### 1.2 Resultats des tests manuels (bypass du bloc service)

Test avec `httpx` + meme User-Agent/cookies que le parser. Resultats du 2026-02-27:

| Test | URL | Fetch | channelId trouve | Feed fonctionne |
|------|-----|-------|-----------------|-----------------|
| Handle URL | `youtube.com/@ScienceEtonnante` | 200, 554KB HTML | **NON** | N/A |
| Channel URL | `youtube.com/channel/UCaNlbnghtwlsGF-KzAFThqA` | 200, 555KB HTML | **NON** | N/A |
| Direct Atom Feed | `youtube.com/feeds/videos.xml?channel_id=UCaNlbnghtwlsGF-KzAFThqA` | 200, 35KB XML | N/A | **OUI** (15 entries) |
| Handle Heu?reka | `youtube.com/@Haboryme` | 200, 554KB HTML | **NON** | N/A |
| /c/ handle | `youtube.com/c/Fouloscopie` | 200, 554KB HTML | **NON** | N/A |
| Video URL | `youtube.com/watch?v=dQw4w9WgXcQ` | 200, 1.5MB HTML | **OUI** (`UCuAXFkgsw1L7xaCfnd5JJOw`) | **OUI** (15 entries) |

### 1.3 Cause racine YouTube

**YouTube a change son rendering cote serveur.** Les pages handle/channel (`/@xxx`, `/channel/UCxxx`, `/c/xxx`) sont maintenant entierement rendues en JavaScript. Le HTML initial ne contient plus :
- Pas de `<meta itemprop="channelId">`
- Pas de `"channelId":"UCxxx"` dans le JSON inline
- Pas de `<link rel="alternate">` vers le feed Atom
- Pas de `<link rel="canonical">` avec le channel_id

**Exception** : les pages video (`/watch?v=xxx`) contiennent encore `"channelId":"UCxxx"` dans le JSON inline (necessaire pour le player). Cela explique pourquoi le test video est le seul a trouver un channel_id.

**Impact** : les 9 methodes de resolution du RSS parser (`rss_parser.py:107-274`) sont toutes cassees pour les URLs handle/channel, SAUF la methode regex sur les pages video.

### 1.4 Fix propose pour YouTube

**Option A — YouTube Data API v3 (recommande)**
- Endpoint gratuit: `GET /youtube/v3/channels?forHandle=@ScienceEtonnante&part=id`
- Retourne le `channelId` en 1 call API
- Quota gratuit: 10,000 unites/jour (1 unite par call channels.list)
- **Effort**: ~4h (integration API + gestion cle API + fallback)
- **Avantage**: Fiable, officiel, supporte tous les formats d'URL

**Option B — Scrape via page video (workaround)**
- Depuis une URL handle, trouver une video recente (via la page HTML, un lien video est parfois present)
- Extraire le channelId depuis la page video
- **Effort**: ~6h (fragile, depend du rendering HTML YouTube)
- **Desavantage**: Double requete, fragile si YouTube change encore

**Option C — yt-dlp (overkill)**
- Utiliser `yt-dlp --dump-json` pour extraire les metadonnees
- **Effort**: ~2h de code mais ajoute une dependance lourde (~50MB)
- **Desavantage**: Trop lourd pour juste resoudre un channel_id

**Recommandation**: Option A (YouTube Data API v3). Gratuit, fiable, officiel. Necessite une cle API stockee en env var.

### 1.5 Notes supplementaires YouTube

- Les 6 sources YouTube curees en DB ont ete importees via `import_sources.py` avec des `CURATED_FEED_FALLBACKS` hardcodes — elles n'utilisent PAS le flux de detection
- Le code `debug_youtube.html` (rss_parser.py:247-249) ecrit sur disque en production — a nettoyer
- Le feed Atom YouTube retourne toujours 15 entries, suffisant pour notre pipeline

---

## 2. Reddit — Diagnostic detaille

### 2.1 Chemin d'echec actuel

```
User colle: reddit.com/r/technology
  → Router detect_source() [sources.py:122]
    → is_url_like = True (regex match)
    → SourceService.detect_source(url) [source_service.py:408]
      → RSSParser.detect(url) [rss_parser.py:70]
        → Step 1: Direct parse → ECHEC (HTML, pas RSS)
        → Step 2: HTML auto-discovery → ECHEC (Reddit ne sert pas de <link rel="alternate">)
        → Step 3: YouTube check → SKIP (pas youtube.com)
        → Step 4: Common suffixes (/feed, /rss, /rss.xml, /feed.xml) → ECHEC (Reddit utilise /.rss)
        → ValueError("No RSS feed found on this page.")
      → FailedSourceAttempt logged
      → HTTP 400 retourne au client
```

### 2.2 Resultats des tests manuels

| Test | URL | Fetch | Feedparser | Entries |
|------|-----|-------|-----------|---------|
| Subreddit HTML | `reddit.com/r/technology` | 200, 521KB HTML | Bozo, 0 entries | 0 |
| Subreddit `.rss` | `reddit.com/r/technology/.rss` | 200, 47KB Atom | atom10, 25 entries | **25** |
| Top/week `.rss` | `reddit.com/r/technology/top/.rss?t=week` | 200, 46KB Atom | atom10, 25 entries | **25** |
| old.reddit `.rss` | `old.reddit.com/r/technology/.rss` | 200, 47KB Atom | atom10, 25 entries | **25** |
| Subreddit no www | `reddit.com/r/worldnews` | 200, 540KB HTML | Bozo, 0 entries | 0 |
| Small subreddit | `reddit.com/r/selfhosted` | 200, 558KB HTML | Bozo, 0 entries | 0 |
| Small subreddit `.rss` | `reddit.com/r/selfhosted/.rss` | 200, 83KB Atom | atom10, 25 entries | **25** |

### 2.3 Cause racine Reddit

1. **Reddit ne sert pas de `<link rel="alternate">`** dans les pages HTML subreddit → l'auto-discovery echoue
2. **Le suffixe `/.rss` n'est pas dans nos common suffixes** — on essaie `/feed`, `/rss`, `/rss.xml`, `/feed.xml` mais jamais `/.rss` (avec le point)
3. **Aucune detection d'URL Reddit** dans le code — pas de regex pour reconnaitre `reddit.com/r/{sub}` et transformer en `reddit.com/r/{sub}/.rss`

### 2.4 Observations positives Reddit

- **Aucun rate limiting** observe avec notre User-Agent Chrome
- **Format Atom standard** — feedparser parse sans probleme (bozo=False)
- **25 entries par feed** — suffisant pour notre pipeline
- **old.reddit.com** fonctionne aussi bien que www

### 2.5 Fix propose pour Reddit

**Fix simple — Transformation URL dans le parser** (~2-4h)

Ajouter dans `rss_parser.py` avant l'auto-discovery (ou dans `source_service.py`):

```python
# Reddit URL detection
import re
reddit_match = re.match(
    r'https?://(?:www\.|old\.)?reddit\.com/r/(\w+)/?.*',
    url
)
if reddit_match:
    subreddit = reddit_match.group(1)
    rss_url = f"https://www.reddit.com/r/{subreddit}/.rss"
    # Fetch and parse the RSS feed directly
    ...
```

**Edge cases a gerer:**
- `reddit.com/r/technology` → `reddit.com/r/technology/.rss` (cas standard)
- `reddit.com/r/technology/` → meme resultat (trailing slash)
- `reddit.com/r/technology/top` → utiliser le feed par defaut, pas le top
- `reddit.com/user/username` → `reddit.com/user/username/.rss` (optionnel, V2)
- Subreddits prives → le feed retournera une erreur, gerer proprement
- Subreddits NSFW → le feed fonctionne normalement

**Effort**: ~2-4h incluant tests et edge cases.

---

## 3. Recommandations consolidees

### Priorites

| # | Action | Impact | Effort | Priorite |
|---|--------|--------|--------|----------|
| 1 | Fix Reddit (transformation URL → `.rss`) | Tres demande par testeurs | ~2-4h | **P0** |
| 2 | Re-activer YouTube avec API v3 pour resolution channel_id | Tres demande par testeurs | ~8-12h | **P0** |
| 3 | Nettoyer `debug_youtube.html` write (rss_parser.py:247) | Securite/hygiene | ~15min | **P1** |
| 4 | Ameliorer le message d'erreur mobile (actuellement generique) | UX | ~1h | **P2** |

### Quick wins

1. **Reddit** est le fix le plus rapide et le plus impactant. Ajouter `/.rss` au suffixe commun (ou mieux, detecter les URLs Reddit explicitement) debloque tous les subreddits.
2. **YouTube** necessite une cle API mais est un fix propre et durable. L'alternative (scraper les pages video) est fragile.

---

## 4. Annexe — Script de test

Le script de diagnostic est disponible dans:
```
packages/api/scripts/test_youtube_reddit.py
```

Execution:
```bash
python packages/api/scripts/test_youtube_reddit.py
```

---

*Genere par Agent @dev — Mission 1 du brief "Diagnostic RSS Sources"*
