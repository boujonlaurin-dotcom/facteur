# Accès sécurisés pour les agents Claude

> Objectif : permettre à un agent Claude (local, Claude Code on the web,
> session déclenchée par GitHub Action) d'**investiguer** (logs, erreurs,
> schéma, analytics) sans jamais pouvoir **détruire** ni accéder à des
> données utilisateur non nécessaires.

Principes :
- **Least-privilege par défaut.** Chaque token a le scope minimal.
- **Read-only sauf exception explicite.** Les tokens d'écriture (déploiement,
  migrations) restent côté humain / CI, jamais côté agent.
- **Rotation trimestrielle** (label `Q1-2026` dans le nom du token pour
  traçabilité).
- **Aucune donnée PII** dans les dumps / logs partagés avec l'agent.

---

## 1. Panorama des accès (quoi donner à un agent, et pour quoi faire)

| Service | Besoin agent | Scope exact | Secret correspondant |
|---|---|---|---|
| **Supabase — MCP** | Explorer schéma, lancer SELECT | PAT perso **read-only** | `SUPABASE_ACCESS_TOKEN` |
| **Supabase — DB directe** | Lancer requêtes SQL (analytics, debug) | Rôle PG `claude_analytics_ro` (SELECT only) | `DATABASE_URL_RO` |
| **Railway** | Lire les logs prod, inspecter variables | Project Token scope **read-only** | `RAILWAY_TOKEN`, `RAILWAY_PROJECT_ID`, `RAILWAY_SERVICE_ID` |
| **Sentry** | Lire issues, events, session replay | Auth Token scope `event:read`, `project:read`, `org:read` | `SENTRY_AUTH_TOKEN`, `SENTRY_ORG`, `SENTRY_PROJECT` |
| **PostHog** | Lire insights, cohortes, events | Personal API key scope `insight:read`, `cohort:read`, `event:read` | `POSTHOG_PERSONAL_API_KEY`, `POSTHOG_PROJECT_ID`, `POSTHOG_HOST` |
| **GitHub** | PR, issues, checks | Déjà géré via MCP côté Claude (app installée sur le repo) | *(rien à faire côté dev)* |

**À NE JAMAIS donner à un agent :**
- `SUPABASE_SERVICE_ROLE_KEY` (bypass RLS, accès auth.users, destructif).
- Railway token scope "Full Access" (peut déployer, supprimer projet).
- `SENTRY_AUTH_TOKEN` avec scope `project:write` / `member:admin`.
- PostHog Personal API key avec scope `*:write`.
- Clé Stripe, clé OpenAI prod, credentials APNS/FCM.

---

## 2. Création des tokens — procédure par service

### 2.1 Supabase — PAT pour MCP (read-only)

1. app.supabase.com → **Account** → **Access Tokens** → *Generate new token*.
2. Nom : `claude-agent-readonly-Q1-2026`.
3. Copie la valeur → à coller dans `SUPABASE_ACCESS_TOKEN`.
4. Le MCP est déjà configuré en `--read-only` dans `.mcp.json` → pas d'action
   supplémentaire.

### 2.2 Supabase — Rôle PG `claude_analytics_ro` (SQL direct)

À faire **une fois** dans Supabase SQL Editor (prod) :

```sql
-- Rôle SELECT-only pour les requêtes analytics / debug d'agent
CREATE ROLE claude_analytics_ro NOINHERIT LOGIN PASSWORD '<pwd_fort>';

GRANT CONNECT ON DATABASE postgres TO claude_analytics_ro;
GRANT USAGE   ON SCHEMA public      TO claude_analytics_ro;
GRANT SELECT  ON
  analytics_events,
  user_profiles, user_streaks, user_subscriptions,
  user_content_status, user_personalization, user_topic_progress,
  digest_completions, daily_digest, daily_top3,
  sources, contents, collections
TO claude_analytics_ro;

-- Verrou : nouvelles tables non accessibles par défaut (doit être explicite).
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  REVOKE ALL ON TABLES FROM claude_analytics_ro;
```

URL à mettre dans `DATABASE_URL_RO` (le mot de passe est celui que tu as
défini à la ligne `PASSWORD` ci-dessus) :

- Host : `db.ykuadtelnzavrqzbfdve.supabase.co`
- Port : `5432`
- User : `claude_analytics_ro`
- Database : `postgres`
- SSL mode : `require`

Assemblage : URI PostgreSQL standard (voir
[doc officielle libpq](https://www.postgresql.org/docs/current/libpq-connect.html#LIBPQ-CONNSTRING))
en injectant les 4 valeurs ci-dessus plus le mot de passe choisi à la
ligne `PASSWORD` du SQL.

### 2.3 Railway — Project Token read-only

1. railway.app → ton projet → **Settings** → **Tokens** → *New Token*.
2. **Scope** : cocher uniquement `Read` (pas `Deploy`, pas `Full Access`).
3. Nom : `claude-agent-logs-Q1-2026`.
4. Copie dans `RAILWAY_TOKEN`.
5. Récupère `RAILWAY_PROJECT_ID` et `RAILWAY_SERVICE_ID` : `railway status`
   ou via l'URL `/project/<PROJECT_ID>/service/<SERVICE_ID>`.

Utilisation côté agent :
```bash
railway logs --project $RAILWAY_PROJECT_ID --service $RAILWAY_SERVICE_ID
railway variables --project $RAILWAY_PROJECT_ID --service $RAILWAY_SERVICE_ID
```

### 2.4 Sentry — Auth Token scope event/project read

1. sentry.io → **Settings** (user) → **Auth Tokens** → *Create New Token*.
2. Scopes à cocher : `event:read`, `project:read`, `org:read` — rien d'autre.
3. Nom : `claude-agent-sentry-Q1-2026`.
4. Copie dans `SENTRY_AUTH_TOKEN`.
5. `SENTRY_ORG` et `SENTRY_PROJECT` se trouvent dans l'URL Sentry
   (`sentry.io/organizations/<ORG>/projects/<PROJECT>/`).

L'agent pourra lancer :
```bash
sentry-cli issues list --project $SENTRY_PROJECT --org $SENTRY_ORG
sentry-cli events list --project $SENTRY_PROJECT --org $SENTRY_ORG --max-rows 10
```

### 2.5 PostHog — Personal API key scoped

1. eu.posthog.com → **Settings** → **Personal API keys** → *Create*.
2. Scopes : `insight:read`, `cohort:read`, `event:read`,
   `feature_flag:read` (facultatif). Rien d'autre.
3. Projet : sélectionne uniquement **Facteur Prod** (pas "All projects").
4. Nom : `claude-agent-analytics-Q1-2026`.
5. Copie dans `POSTHOG_PERSONAL_API_KEY`.
6. `POSTHOG_PROJECT_ID` : voir `Settings` → `Project` → `Project ID` (numérique).
7. `POSTHOG_HOST` = `https://eu.i.posthog.com` (déjà par défaut dans
   `.env.example`).

### 2.6 GitHub — déjà fait

Claude Code on the web utilise l'installation GitHub App configurée sur
`boujonlaurin-dotcom/facteur`. Les tools `mcp__github__*` sont déjà
autorisés au niveau session, pas de token à gérer.

---

## 3. Stocker les secrets pour que Claude les voie

Il y a **trois surfaces** où injecter les secrets selon comment l'agent est
déclenché.

### 3.1 Claude Code **local** (ton terminal) — fichier `.env`

1. `cp .env.example .env`
2. Remplis les 5 blocs (Supabase, DB_URL_RO, Railway, Sentry, PostHog).
3. **Jamais committer `.env`** — il est dans `.gitignore`, mais vérifie :
   ```bash
   git check-ignore .env    # doit afficher ".env"
   ```
4. Charge automatiquement les secrets dans la session :
   - Option A — manuel à chaque session : `export $(grep -v '^#' .env | xargs)`
   - Option B (recommandée) — **direnv** :
     ```bash
     # installation
     brew install direnv   # ou apt-get install direnv
     # hook shell (.zshrc / .bashrc) : eval "$(direnv hook zsh)"
     # dans le repo :
     echo "dotenv" > .envrc
     direnv allow
     ```
     Dès que tu `cd` dans `~/facteur`, tous les secrets sont exportés —
     et désactivés dès que tu sors.

### 3.2 Claude Code **on the web** (claude.ai/code) — secrets du repo

L'interface web de Claude Code lit les secrets du repo GitHub lorsque la
session est déclenchée sur ce repo.

1. GitHub → ton repo → **Settings** → **Secrets and variables** → **Actions**.
2. Clique **New repository secret**.
3. Crée **un secret par variable** (noms identiques à `.env.example`) :
   - `SUPABASE_ACCESS_TOKEN`
   - `DATABASE_URL_RO`
   - `RAILWAY_TOKEN`, `RAILWAY_PROJECT_ID`, `RAILWAY_SERVICE_ID`
   - `SENTRY_AUTH_TOKEN`, `SENTRY_ORG`, `SENTRY_PROJECT`
   - `POSTHOG_PERSONAL_API_KEY`, `POSTHOG_PROJECT_ID`, `POSTHOG_HOST`
4. (Pas dans Secrets mais dans **Variables**) : tout ce qui n'est **pas
   sensible** peut aller dans **Variables** plutôt que Secrets — ex.
   `POSTHOG_HOST`, `RAILWAY_PROJECT_ID`, `SENTRY_ORG`, `SUPABASE_URL`.
   Avantage : valeurs visibles dans les logs, plus faciles à debugger.

> **Règle du pouce** : si la fuite de la valeur est grave → Secret.
> Si ce n'est qu'un ID public → Variable.

### 3.3 Claude déclenché depuis un **GitHub Actions workflow**

Si tu veux qu'un workflow lance un agent Claude (ex : rapport d'usage
hebdo), il faut passer les secrets dans l'`env:` du job. Exemple :

```yaml
# .github/workflows/weekly-usage-report.yml
name: Weekly usage report
on:
  schedule: [{ cron: "0 6 * * 1" }]  # lundi 6h UTC
  workflow_dispatch:

jobs:
  run:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: anthropics/claude-code-action@v1    # ou équivalent
        env:
          SUPABASE_ACCESS_TOKEN:    ${{ secrets.SUPABASE_ACCESS_TOKEN }}
          DATABASE_URL_RO:          ${{ secrets.DATABASE_URL_RO }}
          RAILWAY_TOKEN:            ${{ secrets.RAILWAY_TOKEN }}
          RAILWAY_PROJECT_ID:       ${{ vars.RAILWAY_PROJECT_ID }}
          RAILWAY_SERVICE_ID:       ${{ vars.RAILWAY_SERVICE_ID }}
          SENTRY_AUTH_TOKEN:        ${{ secrets.SENTRY_AUTH_TOKEN }}
          SENTRY_ORG:               ${{ vars.SENTRY_ORG }}
          SENTRY_PROJECT:           ${{ vars.SENTRY_PROJECT }}
          POSTHOG_PERSONAL_API_KEY: ${{ secrets.POSTHOG_PERSONAL_API_KEY }}
          POSTHOG_PROJECT_ID:       ${{ vars.POSTHOG_PROJECT_ID }}
          POSTHOG_HOST:             ${{ vars.POSTHOG_HOST }}
        with:
          prompt: "Relance scripts/analytics/run_usage_queries.sh et commit le rapport dans docs/analytics/"
```

Remarques :
- `secrets.*` pour les vraies valeurs sensibles, `vars.*` pour les IDs publics.
- N'utilise **jamais** `${{ env.SECRET }}` dans un `run:` sans quoter : GH
  masque automatiquement les secrets dans les logs, mais une expression mal
  échappée peut fuiter.

### 3.4 Ordre de priorité côté agent

Quand l'agent s'exécute, il lit les variables dans cet ordre :
1. Variables d'environnement du process (injectées par GH Actions ou direnv).
2. Fichier `.env` local (uniquement si chargé explicitement — pas
   automatique côté session web).

Donc : **en web / CI, utilise les GitHub Secrets.**
**En local, utilise `.env` + direnv.**

---

## 4. Vérification (healthcheck 30 secondes)

Une fois les secrets en place, lance le healthcheck pour vérifier que chaque
service répond :

```bash
# Supabase DB read-only
psql "$DATABASE_URL_RO" -c "SELECT current_user, session_user;"
# → doit afficher "claude_analytics_ro | claude_analytics_ro"

# Supabase MCP (via CLI)
supabase projects list --access-token "$SUPABASE_ACCESS_TOKEN" | head -3

# Railway
railway status

# Sentry
sentry-cli info

# PostHog
curl -sf -H "Authorization: Bearer $POSTHOG_PERSONAL_API_KEY" \
  "$POSTHOG_HOST/api/projects/$POSTHOG_PROJECT_ID/" | jq -r .name
```

Si l'un retourne `permission denied` ou `401` → revoir le scope du token
correspondant.

---

## 5. Garde-fous actifs

1. **`scripts/analytics/run_usage_queries.sh`** refuse de tourner si
   `DATABASE_URL_RO` pointe vers `service_role` ou `postgres:postgres`.
2. **`.gitignore`** contient déjà `.env` — double-check via
   `git check-ignore .env`.
3. **`ALTER DEFAULT PRIVILEGES ... REVOKE ALL`** côté Supabase empêche
   `claude_analytics_ro` de gagner automatiquement l'accès aux nouvelles
   tables (ex : `payments`, `stripe_events` si ajoutées plus tard).
4. **Audit trimestriel** : liste les sessions actives
   ```sql
   SELECT usename, client_addr, query_start, state, query
   FROM pg_stat_activity WHERE usename = 'claude_analytics_ro';
   ```
   Si des requêtes douteuses apparaissent, rotate la password du rôle.

---

## 6. Rotation / révocation d'urgence

En cas de fuite suspectée :

| Service | Commande de révocation |
|---|---|
| Supabase PAT | app.supabase.com → Account → Access Tokens → *Revoke* |
| `claude_analytics_ro` | `ALTER ROLE claude_analytics_ro PASSWORD '<new>';` (SQL Editor) |
| Railway token | railway.app → Project → Tokens → *Delete* |
| Sentry token | sentry.io → Settings → Auth Tokens → *Remove* |
| PostHog PAK | eu.posthog.com → Settings → Personal API keys → *Delete* |

Après rotation :
1. Mets à jour `.env` local.
2. Mets à jour GitHub Secrets (même nom de secret, nouvelle valeur — pas
   besoin de changer les workflows).
3. Relance le healthcheck §4.

---

## 7. Checklist one-shot pour l'utilisateur

À faire **dans l'ordre** pour tout activer :

- [ ] Créer PAT Supabase → `SUPABASE_ACCESS_TOKEN`
- [ ] Lancer le SQL §2.2 → noter la `DATABASE_URL_RO`
- [ ] Créer Project Token Railway (scope Read) → `RAILWAY_TOKEN` + IDs
- [ ] Créer Auth Token Sentry (scopes read uniquement) → `SENTRY_AUTH_TOKEN`
- [ ] Créer Personal API key PostHog (read-only) → `POSTHOG_PERSONAL_API_KEY`
- [ ] Remplir `.env` local (copier depuis `.env.example`)
- [ ] `direnv allow` (ou `export $(grep -v '^#' .env | xargs)`)
- [ ] Lancer le healthcheck §4 → tous verts
- [ ] Dans GitHub → Settings → Secrets : créer les 6 secrets sensibles
- [ ] Dans GitHub → Settings → Variables : créer les 6 IDs/hosts non-sensibles
- [ ] (Optionnel) Ajouter le workflow weekly §3.3 pour automatiser le rapport
