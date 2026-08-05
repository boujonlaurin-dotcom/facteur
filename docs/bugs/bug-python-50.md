# Bug — N+1 sur les attributs source du flux RSS perspectives (PYTHON-50)

> **Élevé** — remonté par le triage Sentry nocturne du 2026-08-01.
> Issue Sentry : `PYTHON-50`, culprit annoncé `get_perspectives`.

## Symptôme

Rafale de `SELECT sources ... WHERE url ILIKE '%domaine%'` sur le chemin
perspectives, proportionnelle au nombre d'items du flux RSS Google News.

## Cause racine

**Le culprit nommé par Sentry est trompeur**, comme pour PYTHON-5Q. L'endpoint
`get_perspectives` programme un refresh en arrière-plan qui passe par
`PerspectiveService._parse_rss`.

Dans `_parse_rss`, chaque item RSS appelle `resolve_bias(domain)` puis
`resolve_reliability(domain)`. Les deux passent par `_resolve_source_column`, qui
fait un `SELECT` sur `Source` avec un predicate `url ILIKE %domaine%`. Résultat :
**jusqu'à 2 requêtes par item RSS**.

Ce chemin est **distinct** de celui déjà corrigé par la PR #806
(`search_internal_perspectives` / `build_cluster_perspectives`). Là-bas, le fix
était un `selectinload(Content.source)` : la source est atteignable par une
relation ORM. Ici, la résolution se fait **par domaine**, sur des items RSS
externes sans lien ORM — le `selectinload` ne s'applique pas.

## Correctif

Ajout de `PerspectiveService._prefetch_source_attributes(domains)`, appelé une
fois en tête de `_parse_rss` avec les domaines de tous les items. Il collapse les
lookups en **une seule requête** (`or_(*[Source.url.ilike(...)])`) puis pré-remplit
`_bias_cache` / `_reliability_cache`, que `resolve_bias` / `resolve_reliability`
consultent déjà en premier.

Le patch est **purement additif** : aucune ligne existante n'est modifiée.

### Préservation stricte de la sémantique

Le préchargement duplique la logique de `_resolve_source_column`, donc il en
reproduit les cas limites à l'identique :

- **1 seule source active matchée, valeur ≠ `unknown`** → on pré-remplit ;
- **>1 source matchée** → `scalar_one_or_none()` lèverait, l'exception est
  attrapée et `_resolve_source_column` retombe sur `"unknown"` **sans essayer le
  fallback par nom**. Le préchargement écrit donc `"unknown"`, et surtout ne
  pioche pas l'une des deux sources au hasard ;
- **0 match, ou match unique à `unknown`** → on ne pré-remplit rien, et l'appel
  per-item d'origine gère le fallback par nom, inchangé.

`resolve_bias` consulte `DOMAIN_BIAS_MAP` *avant* le cache : précharger un domaine
présent dans la map est donc sans effet. Le préchargement est best-effort — toute
erreur est loggée et laisse le chemin per-item intact.

## Vérification

`pytest tests/test_perspective_service_n1.py` — 2 tests ajoutés :

- `test_parse_rss_prefetches_source_attributes_in_one_query` : 5 items RSS, mesure
  les requêtes émises via le `_QueryCounter` existant. **Validé en négatif** : en
  désactivant l'appel au préchargement, le test échoue en mesurant exactement
  **10 requêtes** (5 items × 2 lookups) contre ≤ 2 après fix. Le gain est donc
  mesuré, pas supposé.
- `test_prefetch_preserves_resolve_semantics` : compare, domaine par domaine, le
  résultat de `resolve_bias`/`resolve_reliability` **avec** et **sans**
  préchargement, sur les trois cas qui divergent le plus (match unique, double
  match, domaine absent). C'est l'invariant qui rend le fix sûr.

Les domaines de test sont volontairement absents de `DOMAIN_BIAS_MAP` : la map en
dur court-circuite `resolve_bias` avant tout accès DB et masquerait le N+1.

Suite complète perspectives : **42 tests verts** contre un vrai Postgres.

## Suivi hors périmètre

`_parse_rss` est **partagé** avec le pipeline du job digest (`pipeline.py`). Le
correctif étant purement additif (un préchargement de cache, aucune modification
de la logique existante), il est sans risque pour le digest. Mais ce couplage est
à garder en tête pour toute évolution future de `_parse_rss`.
