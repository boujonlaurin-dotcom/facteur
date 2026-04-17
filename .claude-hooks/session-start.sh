#!/bin/bash
# =============================================================================
# session-start.sh — Hook SessionStart Claude Code
#
# Auto-installe Railway CLI, Supabase CLI et Sentry CLI si absents.
# Non-bloquant : toujours exit 0 même en cas d'échec réseau.
#
# Note : les CLIs nécessitent un accès réseau à github.com pour les binaires.
# Les MCP servers (@railway/mcp, @supabase/mcp-server-supabase) fonctionnent
# indépendamment via npx (npm registry accessible).
# =============================================================================

persist_path_in_bashrc() {
  local line="$1"
  local bashrc="$HOME/.bashrc"
  [ -f "$bashrc" ] || touch "$bashrc"
  grep -qxF "$line" "$bashrc" 2>/dev/null || echo "$line" >> "$bashrc"
}

install_railway_cli() {
  if command -v railway &>/dev/null; then
    echo "[session-start] railway OK ($(railway --version 2>/dev/null | head -1))"
    return 0
  fi

  echo "[session-start] railway absent — tentative d'installation via script officiel..."
  if command -v curl &>/dev/null; then
    # Script officiel Railway : https://railway.app/install.sh
    # Le script dépose souvent le binaire dans ~/.railway/bin/ sans toucher le PATH du shell courant.
    bash <(curl -fsSL https://railway.app/install.sh) 2>&1 || true

    if [ -x "$HOME/.railway/bin/railway" ]; then
      export PATH="$HOME/.railway/bin:$PATH"
      persist_path_in_bashrc 'export PATH="$HOME/.railway/bin:$PATH"'
    fi

    if command -v railway &>/dev/null; then
      echo "[session-start] railway installé ($(railway --version 2>/dev/null | head -1))."
    else
      echo "[session-start] WARN: railway install failed (PATH issue? check ~/.railway/bin)"
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
      tar -xzf "${tmp_dir}/supabase.tar.gz" -C "${tmp_dir}" 2>/dev/null || true
      mkdir -p "$HOME/.local/bin"
      install -m 755 "${tmp_dir}/supabase" /usr/local/bin/supabase 2>/dev/null \
        || cp "${tmp_dir}/supabase" "$HOME/.local/bin/supabase" 2>/dev/null \
        || true
      rm -rf "$tmp_dir"

      if [ -x "$HOME/.local/bin/supabase" ] && ! command -v supabase &>/dev/null; then
        export PATH="$HOME/.local/bin:$PATH"
        persist_path_in_bashrc 'export PATH="$HOME/.local/bin:$PATH"'
      fi

      if command -v supabase &>/dev/null; then
        echo "[session-start] supabase installé ($(supabase --version 2>/dev/null | head -1))."
      else
        echo "[session-start] WARN: supabase install failed (PATH issue? check ~/.local/bin)"
      fi
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

install_sentry_cli() {
  if command -v sentry-cli &>/dev/null; then
    echo "[session-start] sentry-cli OK ($(sentry-cli --version 2>/dev/null | head -1))"
    return 0
  fi

  echo "[session-start] sentry-cli absent — tentative d'installation via script officiel..."
  if command -v curl &>/dev/null; then
    # Script officiel Sentry : https://sentry.io/get-cli/
    # Installe dans /usr/local/bin par défaut, ou ~/.local/bin via INSTALL_DIR.
    if [ -w /usr/local/bin ]; then
      curl -sL https://sentry.io/get-cli/ | bash 2>&1 || true
    else
      mkdir -p "$HOME/.local/bin"
      curl -sL https://sentry.io/get-cli/ | INSTALL_DIR="$HOME/.local/bin" bash 2>&1 || true
      if [ -x "$HOME/.local/bin/sentry-cli" ] && ! command -v sentry-cli &>/dev/null; then
        export PATH="$HOME/.local/bin:$PATH"
        persist_path_in_bashrc 'export PATH="$HOME/.local/bin:$PATH"'
      fi
    fi

    if command -v sentry-cli &>/dev/null; then
      echo "[session-start] sentry-cli installé ($(sentry-cli --version 2>/dev/null | head -1))."
    else
      echo "[session-start] WARN: sentry-cli install failed (accès sentry.io requis)"
      echo "[session-start] → Lancer manuellement : bash scripts/setup-cli-tools.sh"
    fi
  else
    echo "[session-start] WARN: curl absent — impossible d'installer sentry-cli"
  fi
}

install_railway_cli
install_supabase_cli
install_sentry_cli

# Fallback idempotent : si l'un des CLI reste manquant après les tentatives
# individuelles, relancer le script de setup unifié. `|| true` neutralise le
# `set -euo pipefail` du script et préserve le contrat non-bloquant du hook.
if ! command -v railway &>/dev/null \
  || ! command -v supabase &>/dev/null \
  || ! command -v sentry-cli &>/dev/null; then
  echo "[session-start] Au moins un CLI manquant — fallback via setup-cli-tools.sh..."
  bash scripts/setup-cli-tools.sh 2>&1 | tail -20 || true
fi

exit 0  # Toujours non-bloquant
