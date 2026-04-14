#!/bin/bash
# =============================================================================
# session-start.sh — Hook SessionStart Claude Code
#
# Auto-installe Railway CLI et Supabase CLI si absents.
# Non-bloquant : toujours exit 0 même en cas d'échec réseau.
# =============================================================================

install_if_missing() {
  local cmd="$1"
  local pkg="$2"

  if command -v "$cmd" &>/dev/null; then
    echo "[session-start] $cmd OK ($(${cmd} --version 2>/dev/null | head -1))"
  else
    echo "[session-start] $cmd absent — tentative d'installation de $pkg..."
    if npm install -g "$pkg" 2>&1; then
      echo "[session-start] $cmd installé."
    else
      echo "[session-start] WARN: Impossible d'installer $pkg (pas de réseau ?)"
      echo "[session-start] Lance 'bash scripts/setup-cli-tools.sh' manuellement."
    fi
  fi
}

install_if_missing railway "@railway/cli"
install_if_missing supabase "supabase"

exit 0  # Toujours non-bloquant
