#!/bin/bash
# =============================================================================
# session-start.sh — Hook SessionStart Claude Code
#
# Auto-installe Railway CLI et Supabase CLI si absents.
# Non-bloquant : toujours exit 0 même en cas d'échec réseau.
#
# Note : les CLIs nécessitent un accès réseau à github.com pour les binaires.
# Les MCP servers (@railway/mcp, @supabase/mcp-server-supabase) fonctionnent
# indépendamment via npx (npm registry accessible).
# =============================================================================

install_railway_cli() {
  if command -v railway &>/dev/null; then
    echo "[session-start] railway OK ($(railway --version 2>/dev/null | head -1))"
    return 0
  fi

  echo "[session-start] railway absent — tentative d'installation via script officiel..."
  if command -v curl &>/dev/null; then
    # Script officiel Railway : https://railway.app/install.sh
    if bash <(curl -fsSL https://railway.app/install.sh) 2>&1; then
      echo "[session-start] railway installé."
    else
      echo "[session-start] WARN: Impossible d'installer railway (accès github.com requis)"
      echo "[session-start] → Lancer manuellement : bash scripts/setup-cli-tools.sh"
    fi
  else
    echo "[session-start] WARN: curl absent — impossible d'installer railway"
  fi
}

install_supabase_cli() {
  if command -v supabase &>/dev/null; then
    echo "[session-start] supabase OK ($(supabase --version 2>/dev/null | head -1))"
    return 0
  fi

  echo "[session-start] supabase absent — tentative d'installation du binaire officiel..."

  # Détection architecture
  local arch
  arch=$(uname -m)
  case "$arch" in
    x86_64)  arch="amd64" ;;
    aarch64) arch="arm64" ;;
    *)       echo "[session-start] WARN: Architecture non supportée: $arch"; return 1 ;;
  esac

  local tmp_dir
  tmp_dir=$(mktemp -d)
  local url="https://github.com/supabase/cli/releases/latest/download/supabase_linux_${arch}.tar.gz"

  if command -v curl &>/dev/null; then
    if curl -fsSL "$url" -o "${tmp_dir}/supabase.tar.gz" 2>&1; then
      tar -xzf "${tmp_dir}/supabase.tar.gz" -C "${tmp_dir}"
      install -m 755 "${tmp_dir}/supabase" /usr/local/bin/supabase 2>/dev/null \
        || cp "${tmp_dir}/supabase" ~/.local/bin/supabase 2>/dev/null \
        || echo "[session-start] WARN: Impossible d'installer supabase dans PATH"
      rm -rf "$tmp_dir"
      echo "[session-start] supabase installé."
    else
      rm -rf "$tmp_dir"
      echo "[session-start] WARN: Impossible de télécharger supabase (accès github.com requis)"
      echo "[session-start] → Lancer manuellement : bash scripts/setup-cli-tools.sh"
    fi
  else
    rm -rf "$tmp_dir"
    echo "[session-start] WARN: curl absent — impossible d'installer supabase"
  fi
}

install_railway_cli
install_supabase_cli

exit 0  # Toujours non-bloquant
