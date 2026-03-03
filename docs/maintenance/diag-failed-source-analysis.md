# Analyse des failed RSS adds — Mission 2

**Date**: 2026-02-27
**Auteur**: Agent @dev (workspace Conductor)
**Source**: Table `failed_source_attempts` (production Supabase)

---

## 1. Constat

**La table `failed_source_attempts` est vide (0 records).**

### Pourquoi

| Fait | Detail |
|------|--------|
| Migration appliquee | `k1l2m3n4o5p6` — table creee le 2026-02-21 |
| Code de logging deploye | Premier deploy avec Add Source 2.0 : **2026-02-27 ~21h UTC** (aujourd'hui) |
| Derniere source custom ajoutee | 2026-02-24 (Elucid) — avant le deploiement du logging |
| Resultat | **Aucun echec n'a ete logue car le code est live depuis < 1h** |

Le logging des echecs est operationnel dans le code deploye. Les donnees s'accumuleront au fur et a mesure que les beta-testeurs essaieront d'ajouter des sources.

---

## 2. Donnees existantes (sources actuelles)

En attendant les donnees de fail, voici l'etat actuel des sources en production:

| Metrique | Valeur |
|----------|--------|
| Sources custom (non-curees) | 177 |
| Liens user-source custom | 48 |
| Sources type `article` | 206 |
| Sources type `podcast` | 8 |
| Sources type `youtube` | 7 (importees via script, pas via detection) |
| Sources type `reddit` | **0** |

**Observation**: Les 7 sources YouTube ont ete importees via `import_sources.py` avec des feed URLs hardcodees (`CURATED_FEED_FALLBACKS`), pas via le flux de detection utilisateur. Zero source Reddit en base.

---

## 3. Script d'analyse pret a l'emploi

Le script `packages/api/scripts/query_failed_sources.py` est pret et teste. Il se connecte a la DB prod via Railway et produit:

- Vue d'ensemble (volume, dates, users uniques)
- Breakdown par type d'input (url/keyword) et endpoint (detect/custom)
- Categorisation automatique par plateforme (YouTube, Reddit, Substack, Twitter/X, etc.)
- Top 20 URLs echouees
- Patterns d'erreur

### Execution

```bash
cd packages/api
railway run -- python scripts/query_failed_sources.py
```

### Quand relancer

Recommandation: relancer apres **1-2 semaines** d'accumulation de donnees (mars 2026) pour avoir un echantillon significatif.

---

## 4. Predictions basees sur le diagnostic Mission 1

En l'absence de donnees reelles, on peut predire les echecs attendus:

| Plateforme | Prediction | Raison |
|------------|-----------|--------|
| **YouTube** | Beaucoup d'echecs attendus | Bloc explicite dans le code (`source_service.py:411`) — tout ajout YouTube retourne une erreur |
| **Reddit** | Echecs attendus | Zero handling Reddit — toute URL subreddit echoue a la detection |
| **Sites sans RSS** | Echecs frequents | Le parser essaie 4 methodes mais echoue si pas de `<link rel="alternate">` ni de suffixe standard |
| **Substack** | Probablement OK | Substack expose `/feed` — le suffix fallback devrait fonctionner |
| **Twitter/X, Instagram, TikTok** | Echecs certains | Aucun RSS natif, pas de handling specifique |

### Estimation qualitative de la repartition attendue

```
YouTube (channel/handle)  ████████████████  ~35-40%
Reddit (subreddit)        ████████          ~15-20%
Website sans RSS          ████████          ~15-20%
Twitter/X                 ████              ~5-10%
Substack (si echec)       ███               ~5%
Autres (Instagram, etc.)  ████              ~5-10%
Keyword/Malformed         ███               ~5%
```

---

## 5. Tableau de faisabilite (previsionnel)

| Plateforme | Faisabilite | Fix | Effort |
|------------|-------------|-----|--------|
| YouTube (channel) | Facile | YouTube Data API v3 pour resolution channel_id | ~8-12h |
| Reddit (subreddit) | Facile | Transformation URL → `.rss` suffix | ~2-4h |
| Substack | Facile | Deja supporte via `/feed` suffix (verifier) | ~1h |
| Medium | Moyen | RSS parfois dispo via `/@user/feed` | ~2h |
| GitHub | Facile | RSS natif (`/releases.atom`, `/commits.atom`) | ~2h |
| Apple Podcasts | Facile | Feed URL dans le HTML de la page | ~3h |
| Mastodon | Facile | RSS natif (`.rss` suffix) | ~1h |
| Twitch | Moyen | RSS dispo via services tiers | ~4h |
| Twitter/X | Difficile | API payante ou scraping (RSSHub/Nitter) | ~1-2 jours |
| Instagram | Difficile | Pas de RSS, scraping fragile | ~2-3 jours |
| TikTok | Difficile | Pas de RSS, anti-bot agressif | Non recommande |
| LinkedIn | Difficile | Pas de RSS public | Non recommande |

---

## 6. Prochaines etapes

1. **Court terme (cette semaine)**: Implementer les fix YouTube et Reddit (Mission 1)
2. **Moyen terme (1-2 semaines)**: Relancer le script d'analyse pour obtenir des donnees reelles
3. **Moyen terme (mars)**: Utiliser les donnees reelles pour prioriser les plateformes Tier 2-3 (Mission 3)

---

*Genere par Agent @dev — Mission 2 du brief "Diagnostic RSS Sources"*
