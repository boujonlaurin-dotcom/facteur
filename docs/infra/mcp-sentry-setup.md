# MCP Sentry — Activation & secrets

Le MCP Sentry (`mcp-servers/sentry/server.py`) expose les issues/events Sentry à Claude Code (agent perf-watch). Il est déclaré dans `.claude/settings.json` et lit 3 variables d'env : `SENTRY_AUTH_TOKEN`, `SENTRY_ORG`, `SENTRY_PROJECT`.

## 1. Générer le token

Sentry → Settings → Account → API → **Auth Tokens** → *Create New Token*.

**Scopes minimum requis** :
- `project:read`
- `event:read`
- `issue:read`

## 2. Peupler les secrets (CC-on-web)

Créer/éditer `.claude/settings.local.json` (gitignored, jamais committé) :

```json
{
  "env": {
    "SENTRY_AUTH_TOKEN": "<TOKEN>",
    "SENTRY_ORG": "<ORG_SLUG>",
    "SENTRY_PROJECT": "<PROJECT_SLUG>"
  }
}
```

Redémarrer la session Claude Code pour que les vars soient picked up.

## 3. Vérifier l'activation

```bash
python mcp-servers/sentry/server.py
```

Attendu sur **stderr** : `sentry_mcp_ready status=configured org=<slug> project=<slug>`. Si `status=missing_credentials`, le `.claude/settings.local.json` n'est pas chargé — vérifier la syntaxe JSON et redémarrer la session.

## 4. Renouvellement (90 jours)

Les tokens Sentry expirent. Cycle trimestriel :

1. Générer un nouveau token (étape 1) avec les mêmes scopes.
2. Remplacer `SENTRY_AUTH_TOKEN` dans `.claude/settings.local.json`.
3. Révoquer l'ancien token dans Sentry → Auth Tokens.
4. Redémarrer la session CC, re-vérifier le log readiness (étape 3).
