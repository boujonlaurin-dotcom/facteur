# Investigation Playbook

**Quand un agent doit creuser un symptôme prod, ce doc est le point d'entrée unique.**
Tu trouveras ici : les outils disponibles par scénario, les commandes prêtes à copier, les pièges à éviter.

---

## 🟢 Prérequis — est-ce que mes accès marchent ?

Le hook `SessionStart` affiche automatiquement le résultat d'un healthcheck `--fast` au démarrage de la session. Scanne les lignes `[secrets]` dans les premiers messages :

```
[secrets] [OK]   connecté en tant que claude_analytics_ro
[secrets] [OK]   API Supabase répond 200 (PAT valide)
[secrets] [OK]   Railway GraphQL me{} OK (Account Token, user=...)
[secrets] [OK]   API Sentry /api/0/ répond 200 (token OK)
[secrets] [OK]   API PostHog OK (projet 129581)
```

Si tu vois des `[FAIL]`, **arrête-toi** avant d'investiguer : relance un healthcheck complet et corrige le token fautif (ou demande à l'utilisateur) :

```bash
bash scripts/healthcheck-agent-secrets.sh        # mode complet
```

Référence des secrets : [docs/infra/claude-access-setup.md](../infra/claude-access-setup.md).

---

## 📋 Scénarios fréquents

### 1. "Un bug prod à reproduire / diagnostiquer"

| Étape | Outil | Commande / MCP |
|-------|-------|----------------|
| Récupérer la stack trace + user impacté | Sentry API | `curl -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" "https://sentry.io/api/0/projects/$SENTRY_ORG/$SENTRY_PROJECT/issues/"` |
| Reproduire l'état user côté DB | Supabase MCP (read-only) | Via l'outil `mcp__supabase__*` — ne jamais exposer `service_role` |
| Regarder les logs du service | Railway CLI | `railway logs --service <service_id>` |

**Piège** : ne pas tenter de modifier l'état user pour "tester" sans autorisation explicite. Le rôle `claude_analytics_ro` est volontairement read-only.

---

### 2. "Comprendre l'usage d'une feature"

| Étape | Outil | Commande / MCP |
|-------|-------|----------------|
| Events produit (clicks, views) | PostHog API | `curl -H "Authorization: Bearer $POSTHOG_PERSONAL_API_KEY" "https://eu.i.posthog.com/api/projects/$POSTHOG_PROJECT_ID/events/"` |
| Agrégats DB (streaks, rétention) | `scripts/analytics/run_usage_queries.sh` | Lance toutes les requêtes T2.* et T3.* du framework R01/R02 |
| Nouvelle requête SQL ad-hoc | `psql "$DATABASE_URL_RO"` | Ou SQL Editor Supabase en UI |

**Piège** : le pooler Supabase utilise le username `claude_analytics_ro.ykuadtelnzavrqzbfdve` (avec le point — routing pgBouncer). Si tu vois "role does not exist", c'est ce détail.

---

### 3. "Une migration Alembic qui a mal tourné"

| Étape | Outil | Commande |
|-------|-------|----------|
| Identifier le head courant | Alembic local | `cd packages/api && alembic current` |
| Vérifier qu'il n'y a qu'un head | Hook auto | `bash .claude-hooks/post-edit-alembic-heads.sh` (lancé auto) |
| Appliquer un SQL de rattrapage | Supabase SQL Editor | Jamais `alembic upgrade` sur Railway — voir [CLAUDE.md](../../CLAUDE.md) |

**Piège** : Alembic est désactivé sur Railway par design. Les migrations passent par le SQL Editor Supabase avec validation manuelle.

---

### 4. "Un endpoint API répond mal en prod"

| Étape | Outil | Commande |
|-------|-------|----------|
| Status du déploiement courant | Railway CLI | `railway status --json` |
| Logs du service | Railway CLI | `railway logs` |
| Dernières erreurs Sentry | Sentry API | voir scénario 1 |
| Reproduire en local | `uvicorn` | `cd packages/api && uvicorn app.main:app --port 8080` |

---

### 5. "Auditer la sécurité d'un accès / d'une écriture"

| Question | Outil | Commande |
|----------|-------|----------|
| Qui peut faire quoi sur la DB ? | `psql` | `\dp schema.table` (permissions par table) |
| Tester que `claude_analytics_ro` ne peut pas écrire | `scripts/healthcheck-agent-secrets.sh` | Mode complet (le `--fast` skip l'UPDATE probe) |
| Vérifier un GRANT spécifique | Supabase SQL Editor | `SELECT * FROM information_schema.role_table_grants WHERE grantee='claude_analytics_ro';` |

---

## 🔐 Règles de sécurité (non négociables)

1. **Jamais** d'écriture via `DATABASE_URL_RO`. Si tu as besoin d'écrire, demande `service_role` à l'utilisateur avec justification.
2. **Jamais** imprimer un secret en sortie — les hooks GitHub masquent mais le script doit le faire aussi par défaut.
3. **Toujours** utiliser le Session Pooler (port 5432 sur `*.pooler.supabase.com`), pas le endpoint direct `db.*.supabase.co` (IPv6-only).
4. **Rotation** : si un token fuite, révoque immédiatement dans la console du service + update le secret GitHub + relance le healthcheck.

---

## 🧭 Outils à portée de main (aide-mémoire)

| Besoin | Outil de choix | Alternative |
|--------|----------------|-------------|
| Query SQL read-only | `psql "$DATABASE_URL_RO"` | Supabase MCP |
| Introspection projet Supabase | Supabase MCP (read-only) | `curl` sur api.supabase.com |
| Logs / déploiements Railway | `railway logs` / `railway status` | API GraphQL `backboard.railway.app/graphql/v2` |
| Issues Sentry | `sentry-cli issues list` | API `sentry.io/api/0/` |
| Analytics événements | API PostHog | — |

Pour toute commande nouvelle, **teste en mode dry-run si possible** et **commit l'ajout** dans `scripts/analytics/` ou `docs/qa/scripts/` pour que le prochain agent en bénéficie.
