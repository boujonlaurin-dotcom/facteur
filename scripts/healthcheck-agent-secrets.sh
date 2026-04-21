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
  user=$(psql "$DATABASE_URL_RO" -X -A -t -c "SELECT current_user;" 2>/dev/null)
  if [[ "$user" == "claude_analytics_ro" ]]; then
    ok "connecté en tant que claude_analytics_ro"
  elif [[ -n "$user" ]]; then
    ko "connecté mais en tant que '$user' — devrait être claude_analytics_ro"
  else
    ko "connexion impossible (vérifie password, sslmode, IP autorisée)"
  fi
  # Vérifie qu'au moins une table attendue est lisible
  n=$(psql "$DATABASE_URL_RO" -X -A -t -c "SELECT COUNT(*) FROM user_profiles LIMIT 1;" 2>/dev/null)
  [[ -n "$n" ]] && ok "SELECT sur user_profiles fonctionne" || ko "SELECT user_profiles impossible (GRANT manquant ?)"
  # Sanity : refuse un write
  w=$(psql "$DATABASE_URL_RO" -X -A -t -c "UPDATE user_profiles SET onboarding_completed = onboarding_completed WHERE false;" 2>&1)
  if echo "$w" | grep -qi "permission denied"; then
    ok "UPDATE refusé comme attendu (least-privilege OK)"
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
hdr "Railway (RAILWAY_TOKEN)"
if [[ -z "${RAILWAY_TOKEN:-}" ]]; then
  sk "RAILWAY_TOKEN"
elif ! command -v railway &>/dev/null; then
  sk "CLI railway absente — lance scripts/setup-cli-tools.sh"
else
  w=$(railway whoami 2>&1)
  if echo "$w" | grep -qiE "logged in|email"; then
    ok "Railway whoami OK"
  else
    ko "Railway whoami échoue : $(echo "$w" | head -1)"
  fi
  if [[ -n "${RAILWAY_PROJECT_ID:-}" ]]; then
    s=$(railway status --json 2>&1)
    echo "$s" | grep -q "projectId" && ok "projet accessible" || ko "status échoue"
  fi
fi

# ─── Sentry ──────────────────────────────────────────────────────────────────
hdr "Sentry (SENTRY_AUTH_TOKEN)"
if [[ -z "${SENTRY_AUTH_TOKEN:-}" ]]; then
  sk "SENTRY_AUTH_TOKEN"
elif ! command -v sentry-cli &>/dev/null; then
  sk "sentry-cli absente"
else
  i=$(sentry-cli info 2>&1)
  if echo "$i" | grep -qi "authenticated"; then
    ok "sentry-cli authentifié"
  else
    ko "sentry-cli info échoue"
  fi
  if [[ -n "${SENTRY_ORG:-}" && -n "${SENTRY_PROJECT:-}" ]]; then
    r=$(curl -sf -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" \
        "https://sentry.io/api/0/projects/$SENTRY_ORG/$SENTRY_PROJECT/" 2>/dev/null)
    [[ "$r" == "200" ]] && ok "projet Sentry accessible" || ko "projet Sentry HTTP $r"
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
