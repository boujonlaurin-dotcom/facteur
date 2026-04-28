# QA Handoff — Recherche de sources (qualité + observabilité)

> Branche : `boujonlaurin-dotcom/source-search-fix` → cible `main`
> Bug doc : `docs/bugs/bug-source-search-quality.md`
> Diag : `.context/source-search-diag.md`

## Feature développée

Refonte du pipeline `POST /sources/smart-search` : drop strict des résultats sans feed RSS détecté, filtre listicle/denylist, fallback root host, catalog accent-insensible + fuzzy `pg_trgm`, court-circuit dès 1 hit curated, log universel dans nouvelle table `source_search_logs`.

## Pré-requis QA — migration manuelle Supabase

À exécuter dans Supabase Studio Editor SQL **avant déploiement Railway** :

```sql
CREATE EXTENSION IF NOT EXISTS unaccent;
-- Puis le DDL de ssq01_create_source_search_logs (cf. alembic/versions)
```

## Écrans impactés

| Écran | Route mobile | Statut |
|-------|--------------|--------|
| Ajouter une source | `add_source_screen.dart` | Modifié (logique backend uniquement) |

## Scénarios de test

### S1 — Source curated mainstream (happy path)
Taper `mediapart`. Attendu : Mediapart en tête, `layers_called == ["catalog"]`, latence < 500 ms, zéro listicle.

### S2 — Accent / typo
Taper `arret sur images` (sans accent), puis `mediapar`. Attendu : `Arrêt sur Images` et `Mediapart` apparaissent — `unaccent + pg_trgm` doivent matcher.

### S2-bis — Sources FR indépendantes hors catalog (pipeline externe)
Taper successivement `politis`, `disclose`, `le media`, `frustration magazine`, `mediacites`.
Attendu pour chacun : la pipeline externe (Brave + Google News + root-host fallback) doit retrouver le site officiel et résoudre son feed RSS. Pas de listicle. Premier résultat = la source attendue (politis.fr, disclose.ngo, lemediatv.fr, frustrationmagazine.fr, mediacites.fr).

### S3 — Requête thématique large (anti-listicle)
Taper `political news`. Attendu : **zéro** résultat type "60 Best…" / "Top 100…". Si rien n'est trouvable, liste vide + CTA "Élargir la recherche" plutôt que des articles SEO.

### S4 — YouTube handle
Taper `@HugoDecrypte`. Attendu : chaîne résolue (layer `youtube`), feed présent.

### S5 — Élargir la recherche
Taper `mediapart` puis tap sur "Élargir la recherche". Attendu : pipeline complet, mais toujours aucun résultat sans `feed_url`.

### S6 — Observabilité
SQL :
```sql
SELECT query_raw, layers_called, result_count, cache_hit, abandoned, latency_ms
FROM source_search_logs
ORDER BY created_at DESC LIMIT 10;
```
Attendu : une ligne par recherche jouée, `top_results` rempli, `cache_hit` cohérent. Si l'utilisateur ferme l'écran sans ajouter, la dernière ligne a `abandoned = true`.

## Critères d'acceptation

- [ ] Aucun résultat affiché sans `feed_url`
- [ ] Aucun listicle/aggregator dans le top 5 sur 5 requêtes thématiques (`political news`, `actualité écologie`, `tech europe`, `crypto news`, `climate`)
- [ ] Catalog ILIKE accent-insensible : `arret sur images` matche `Arrêt sur Images`
- [ ] Court-circuit catalog observable (`layers_called == ["catalog"]`, latence < 500 ms) sur 6 sources curated connues
- [ ] Table `source_search_logs` se remplit en prod
- [ ] `failed_source_attempts` continue à recevoir les abandons (rétrocompat)
