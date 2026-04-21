#!/usr/bin/env bash
# healthcheck-agent-secrets.sh — Valide que les secrets d'agent sont fonctionnels.
#
# Usage local :
#   export $(grep -v '^#' .env | xargs)  # ou direnv auto
#   bash scripts/healthcheck-agent-secrets.sh
#
# Usage CI : appelé par .github/workflows/agent-secrets-healthcheck.yml
#
# Sortie :
#   - Un bloc par service avec OK/FAIL/SKIP
#   - Exit 0 si tous OK ou SKIP, exit 1 si un FAIL
#
# Jamais de secret imprimé dans la sortie.

set -u
pipefail_off=$-; set +e  # on veut continuer même si une check échoue

pass=0; fail=0; skip=0

ok()   { echo "  [OK]   $1"; pass=$((pass+1)); }
ko()   { echo "  [FAIL] $1"; fail=$((fail+1)); }
sk()   { echo "  [SKIP] $1 (variable absente)"; skip=$((skip+1)); }

hdr()  { echo; echo "─── $1 ───────────────────────────────────────────"; }

# ─── Supabase : DB read-only ─────────────────────────────────────────────────
hdr "Supabase — DB read-only (DATABASE_URL_RO)"
if [[ -z "${DATABASE_URL_RO:-}" ]]; then
  sk "DATABASE_URL_RO"
elif ! command -v psql &>/dev/null; then
  sk "psql absent — skip"
else
  # Diagnostic non-sensible sur l'URL (schéma/host/port/db, sans password).
  safe=$(printf '%s' "$DATABASE_URL_RO" \
         | sed -E 's#^(postgres(ql)?://)[^:]+:[^@]+@#\1***:***@#' \
         | sed -E 's/(password=)[^& ]+/\1***/g')
  echo "  (URL sans secret) $safe"

  conn_out=$(psql "$DATABASE_URL_RO" -X -A -t -c "SELECT current_user;" 2>&1)
  user=$(echo "$conn_out" | tail -1 | tr -d ' \r\n')
  if [[ "$user" == "claude_analytics_ro" ]]; then
    ok "connecté en tant que claude_analytics_ro"
  elif [[ "$conn_out" == *"ERROR"* || "$conn_out" == *"FATAL"* || "$conn_out" == *"could not"* || "$conn_out" == *"timeout"* ]]; then
    first=$(echo "$conn_out" | grep -iE "error|fatal|could not|timeout|denied" | head -1)
    ko "connexion impossible : ${first:-$conn_out}"
  elif [[ -n "$user" ]]; then
    ko "connecté mais en tant que '$user' — devrait être claude_analytics_ro"
  else
    ko "connexion impossible (sortie vide)"
  fi
  # Vérifie qu'au moins une table attendue est lisible
  sel_out=$(psql "$DATABASE_URL_RO" -X -A -t -c "SELECT COUNT(*) FROM user_profiles LIMIT 1;" 2>&1)
  n=$(echo "$sel_out" | tail -1 | tr -d ' \r\n')
  if [[ "$n" =~ ^[0-9]+$ ]]; then
    ok "SELECT sur user_profiles fonctionne ($n rows)"
  else
    first=$(echo "$sel_out" | grep -iE "error|fatal|denied" | head -1)
    ko "SELECT user_profiles impossible : ${first:-(sortie vide)}"
  fi
  # Sanity : refuse un write
  w=$(psql "$DATABASE_URL_RO" -X -A -t -c "UPDATE user_profiles SET onboarding_completed = onboarding_completed WHERE false;" 2>&1)
  if echo "$w" | grep -qi "permission denied"; then
    ok "UPDATE refusé comme attendu (least-privilege OK)"
  elif echo "$w" | grep -qiE "fatal|could not|timeout"; then
    ko "UPDATE non testable (connexion en échec amont)"
  else
    ko "UPDATE n'est PAS refusé — le rôle a trop de droits ! Vérifie le GRANT."
  fi
fi

# ─── Supabase : PAT (MCP) ────────────────────────────────────────────────────
hdr "Supabase — Personal Access Token (MCP)"
if [[ -z "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
  sk "SUPABASE_ACCESS_TOKEN"
else
  r=$(curl -sf -o /dev/null -w "%{http_code}" \
      -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
      https://api.supabase.com/v1/projects 2>/dev/null)
  if [[ "$r" == "200" ]]; then
    ok "API Supabase répond 200 (PAT valide)"
  else
    ko "API Supabase HTTP $r — PAT invalide ou révoqué"
  fi
fi

# ─── Railway ─────────────────────────────────────────────────────────────────
hdr "Railway (RAILWAY_TOKEN / RAILWAY_API_TOKEN)"
if [[ -z "${RAILWAY_TOKEN:-}" && -z "${RAILWAY_API_TOKEN:-}" ]]; then
  sk "RAILWAY_TOKEN et RAILWAY_API_TOKEN"
elif ! command -v railway &>/dev/null; then
  sk "CLI railway absente — lance scripts/setup-cli-tools.sh"
else
  # Diagnostic longueur pour détecter un copier/coller tronqué ou avec espaces.
  tok_len=${#RAILWAY_TOKEN}
  api_len=${#RAILWAY_API_TOKEN}
  echo "  (longueur tokens) RAILWAY_TOKEN=${tok_len}, RAILWAY_API_TOKEN=${api_len}"

  w=$(railway whoami 2>&1)
  if echo "$w" | grep -qiE "logged in|email|@"; then
    ok "Railway whoami OK ($(echo "$w" | head -1))"
  else
    ko "Railway whoami échoue : $(echo "$w" | head -2 | tr '\n' ' ')"
  fi
  if [[ -n "${RAILWAY_PROJECT_ID:-}" ]]; then
    s=$(railway status --json 2>&1)
    echo "$s" | grep -q "projectId" && ok "projet accessible" || ko "status échoue : $(echo "$s" | head -1)"
  fi
fi

# ─── Sentry ──────────────────────────────────────────────────────────────────
hdr "Sentry (SENTRY_AUTH_TOKEN)"
if [[ -z "${SENTRY_AUTH_TOKEN:-}" ]]; then
  sk "SENTRY_AUTH_TOKEN"
elif ! command -v sentry-cli &>/dev/null; then
  sk "sentry-cli absente"
else
  sent_len=${#SENTRY_AUTH_TOKEN}
  echo "  (longueur token) SENTRY_AUTH_TOKEN=${sent_len}"

  # Test API direct (source de vérité — indépendant d'un .sentryclirc)
  api_code=$(curl -sS -o /tmp/sentry_self.json -w "%{http_code}" \
      -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" \
      "https://sentry.io/api/0/" 2>/dev/null)
  if [[ "$api_code" == "200" ]]; then
    ok "API Sentry /api/0/ répond 200 (token OK)"
  else
    ko "API Sentry /api/0/ HTTP $api_code — token invalide / scopes manquants"
  fi

  # CLI check informel : échoue silencieusement si pas de default org/project
  # configurés, mais tant que l'API répond on considère le secret valide.
  i=$(sentry-cli info 2>&1)
  if echo "$i" | grep -qi "authenticated"; then
    ok "sentry-cli authentifié (bonus)"
  fi

  if [[ -n "${SENTRY_ORG:-}" && -n "${SENTRY_PROJECT:-}" ]]; then
    r=$(curl -sS -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" \
        "https://sentry.io/api/0/projects/$SENTRY_ORG/$SENTRY_PROJECT/" 2>/dev/null)
    [[ "$r" == "200" ]] && ok "projet Sentry accessible" || ko "projet Sentry HTTP $r (ORG='$SENTRY_ORG' PROJECT='$SENTRY_PROJECT')"
  fi
fi

# ─── PostHog ─────────────────────────────────────────────────────────────────
hdr "PostHog (POSTHOG_PERSONAL_API_KEY)"
if [[ -z "${POSTHOG_PERSONAL_API_KEY:-}" ]]; then
  sk "POSTHOG_PERSONAL_API_KEY"
else
  host="${POSTHOG_HOST:-https://eu.i.posthog.com}"
  pid="${POSTHOG_PROJECT_ID:-}"
  if [[ -z "$pid" ]]; then
    sk "POSTHOG_PROJECT_ID absent — check partiel"
  else
    r=$(curl -sf -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer $POSTHOG_PERSONAL_API_KEY" \
        "$host/api/projects/$pid/" 2>/dev/null)
    [[ "$r" == "200" ]] && ok "API PostHog OK (projet $pid)" || ko "PostHog HTTP $r"
  fi
fi

# ─── GitHub (session courante) ──────────────────────────────────────────────
hdr "GitHub"
if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
  ok "Exécution dans GitHub Actions — GITHUB_TOKEN auto-injecté"
else
  sk "hors GitHub Actions — GitHub géré via MCP côté Claude Code"
fi

# ─── Résumé ─────────────────────────────────────────────────────────────────
echo
echo "═════════════════════════════════════════════════════════════════"
echo "  Résumé : $pass OK · $fail FAIL · $skip SKIP"
echo "═════════════════════════════════════════════════════════════════"

[[ $fail -eq 0 ]] && exit 0 || exit 1
