# Claude Code — Accès sécurisé aux données analytics

> Permet à une session Claude Code (y compris web / triggered GitHub) de lire
> les données prod nécessaires aux rapports d'usage, **sans jamais** accéder
> en écriture ni à `auth.*`.

## Périmètre

| Ressource | Usage | Mode |
|---|---|---|
| Supabase DB | Lecture `analytics_events`, `user_*`, `sources`, `contents`, `digest_*` | **read-only** via rôle dédié |
| PostHog | Lecture events, cohortes, insights | **read-only** via personal API key scopée |
| Railway | Logs / metrics (optionnel) | **read-only** via token scope logs |
| Sentry | Déjà OK via `sentry-cli` | token existant |

## Étape 1 — Rôle Supabase read-only (1 fois)

Dans Supabase SQL Editor (prod) :

```sql
-- Rôle dédié Claude, SELECT-only
CREATE ROLE claude_analytics_ro NOINHERIT LOGIN PASSWORD '<password_fort>';

-- Accorde uniquement les tables analytics nécessaires
GRANT CONNECT ON DATABASE postgres TO claude_analytics_ro;
GRANT USAGE ON SCHEMA public TO claude_analytics_ro;
GRANT SELECT ON
  analytics_events,
  user_profiles,
  user_streaks,
  user_subscriptions,
  user_content_status,
  user_personalization,
  user_topic_progress,
  digest_completions,
  daily_digest,
  daily_top3,
  sources,
  contents,
  collections
TO claude_analytics_ro;

-- Verrou : pas d'accès aux nouvelles tables par défaut (révoque DEFAULT PRIVILEGES)
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM claude_analytics_ro;
```

Note la `DATABASE_URL_RO` au format :
```
postgresql://claude_analytics_ro:<password>@db.ykuadtelnzavrqzbfdve.supabase.co:5432/postgres?sslmode=require
```

## Étape 2 — Secrets dans la session Claude (GitHub → Actions/Codespaces)

Dans GitHub `Settings → Secrets and variables → Actions` :

| Secret | Valeur | Rotation |
|---|---|---|
| `SUPABASE_ACCESS_TOKEN` | PAT Supabase perso (scope : MCP read-only) | trimestrielle |
| `DATABASE_URL_RO` | URL du rôle `claude_analytics_ro` (étape 1) | trimestrielle |
| `POSTHOG_PERSONAL_API_KEY` | Personal API key PostHog **scoped read-only** sur le projet `Facteur Prod` | trimestrielle |
| `POSTHOG_PROJECT_ID` | ID numérique du projet PostHog (pas un secret en soi) | stable |
| `RAILWAY_TOKEN` | Token Railway scope **logs read-only** | trimestrielle |

Ces secrets sont injectés comme `env` dans les sessions Claude Code triggered
via GitHub Actions (ou via la config Claude Code on the web → "Repository secrets").

## Étape 3 — MCP Supabase (déjà déclaré)

Le fichier `.mcp.json` à la racine déclare le MCP Supabase en mode `--read-only` :

```json
{
  "mcpServers": {
    "supabase": {
      "command": "npx",
      "args": ["-y", "@supabase/mcp-server-supabase@latest",
               "--read-only", "--project-ref=ykuadtelnzavrqzbfdve"],
      "env": { "SUPABASE_ACCESS_TOKEN": "${SUPABASE_ACCESS_TOKEN}" }
    }
  }
}
```

Au prochain lancement de session, Claude Code chargera automatiquement ce MCP
si `SUPABASE_ACCESS_TOKEN` est présent dans l'env.

## Étape 4 — PostHog via API (pas besoin de MCP)

PostHog expose une REST API lisible directement via `curl` / `WebFetch`. Exemple
de requête DAU sur 30 jours :

```bash
curl -H "Authorization: Bearer $POSTHOG_PERSONAL_API_KEY" \
  "$POSTHOG_HOST/api/projects/$POSTHOG_PROJECT_ID/insights/trend/?events=[{\"id\":\"app_open\",\"math\":\"dau\"}]&date_from=-30d&interval=day"
```

Un helper `scripts/analytics/posthog_query.py` sera ajouté dans R03 (voir
roadmap du rapport d'usage).

## Étape 5 — Vérification

Test local :

```bash
# Depuis la racine du repo avec .env chargé
export $(grep -v '^#' .env | xargs)
bash scripts/analytics/run_usage_queries.sh | jq .
```

Devrait produire un JSON avec les 8 blocs de requêtes renseignés. Si une
requête échoue avec `permission denied for table X`, ajoute la table au GRANT
de l'étape 1 (et documente-la ici).

## Garde-fous

1. **Jamais de `service_role`** dans `DATABASE_URL_RO`. Le script
   `run_usage_queries.sh` refuse de tourner si c'est détecté.
2. **Révocation** : `ALTER DEFAULT PRIVILEGES ... REVOKE ALL` empêche
   claude_analytics_ro de gagner accès aux nouvelles tables automatiquement —
   chaque ajout est explicite.
3. **Audit** : active `pgaudit` ou consulte régulièrement
   `pg_stat_activity` filtré sur `usename = 'claude_analytics_ro'`.
4. **Scope PostHog** : la personal API key doit être créée avec scope
   `insight:read`, `cohort:read`, `event:read` uniquement — jamais `*:write`.
5. **Rotation** : rotation trimestrielle, automatisée via un calendrier
   partagé ou un reminder Linear.
