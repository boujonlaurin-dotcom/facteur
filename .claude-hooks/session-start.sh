#!/bin/bash
# =============================================================================
# session-start.sh — Hook SessionStart Claude Code
#
# Vérifie la présence des CLIs requis et avertit si manquants.
# Non-bloquant : toujours exit 0.
# Installation : brew bundle (voir Brewfile à la racine du repo)
# =============================================================================

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
missing=()

check_cli() {
  local cmd="$1"
  if command -v "$cmd" &>/dev/null; then
    echo "[session-start] $cmd OK"
  else
    missing+=("$cmd")
  fi
}

check_cli railway
check_cli supabase
check_cli sentry-cli

if [ ${#missing[@]} -gt 0 ]; then
  echo "[session-start] MISSING CLIs: ${missing[*]}"
  echo "[session-start] → Run: brew bundle --file=${REPO_ROOT}/Brewfile"
fi

# =============================================================================
# Connectivité des services (secrets d'agent)
# =============================================================================
if [ -f "${REPO_ROOT}/scripts/healthcheck-agent-secrets.sh" ]; then
  if [ -n "${DATABASE_URL_RO:-}${SUPABASE_ACCESS_TOKEN:-}${RAILWAY_TOKEN:-}${SENTRY_AUTH_TOKEN:-}${POSTHOG_PERSONAL_API_KEY:-}" ]; then
    echo "[secrets] vérification connectivité (--fast)..."
    bash "${REPO_ROOT}/scripts/healthcheck-agent-secrets.sh" --fast 2>&1 \
      | grep --extended-regexp '\[(OK|FAIL|SKIP)\]|Résumé' \
      | sed 's/^/[secrets] /' \
      || true
  else
    echo "[secrets] aucune variable d'infra définie (normal pour contributeur sans accès)"
  fi
fi

exit 0
