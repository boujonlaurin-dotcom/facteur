#!/bin/bash
# =============================================================================
# setup-cli-tools.sh — Installation des CLI Railway et Supabase
#
# À exécuter une fois sur une machine de développement avec accès à github.com.
# Prérequis : curl, Node.js >= 18
#
# Usage :
#   bash scripts/setup-cli-tools.sh
# =============================================================================

set -euo pipefail

echo "=== Facteur — Installation des CLI dev tools ==="
echo ""

# ─── Railway CLI ──────────────────────────────────────────────────────────────
if command -v railway &>/dev/null; then
  echo "[OK] Railway CLI déjà installé: $(railway --version 2>/dev/null)"
else
  echo "[...] Installation Railway CLI via script officiel..."
  bash <(curl -fsSL https://railway.app/install.sh)
  echo "[OK] Railway CLI installé: $(railway --version 2>/dev/null)"
fi

# ─── Supabase CLI ─────────────────────────────────────────────────────────────
if command -v supabase &>/dev/null; then
  echo "[OK] Supabase CLI déjà installé: $(supabase --version 2>/dev/null)"
else
  echo "[...] Installation Supabase CLI (binaire officiel GitHub)..."

  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64)  ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    *)       echo "ERREUR: Architecture non supportée: $ARCH"; exit 1 ;;
  esac

  TMP=$(mktemp -d)
  URL="https://github.com/supabase/cli/releases/latest/download/supabase_linux_${ARCH}.tar.gz"

  echo "    Téléchargement depuis: $URL"
  curl -fsSL "$URL" -o "${TMP}/supabase.tar.gz"
  tar -xzf "${TMP}/supabase.tar.gz" -C "$TMP"

  # Installe dans /usr/local/bin si possible, sinon ~/.local/bin
  if [ -w /usr/local/bin ]; then
    install -m 755 "${TMP}/supabase" /usr/local/bin/supabase
  else
    mkdir -p ~/.local/bin
    install -m 755 "${TMP}/supabase" ~/.local/bin/supabase
    echo "    Ajouté dans ~/.local/bin — assure-toi que ce dossier est dans ton PATH"
  fi
  rm -rf "$TMP"

  echo "[OK] Supabase CLI installé: $(supabase --version 2>/dev/null)"
fi

# ─── Vérification finale ──────────────────────────────────────────────────────
echo ""
echo "=== Vérification ==="
echo ""

check_cmd() {
  if command -v "$1" &>/dev/null; then
    echo "[OK] $1"
  else
    echo "[MISSING] $1"
    return 1
  fi
}

all_ok=true
check_cmd railway   || all_ok=false
check_cmd supabase  || all_ok=false

echo ""
if [ "$all_ok" = true ]; then
  echo "Tous les CLI sont installés."
  echo ""
  echo "Variables d'environnement requises (voir .env.example) :"
  echo "  RAILWAY_TOKEN         → railway.app > Account Settings > Tokens"
  echo "  SUPABASE_ACCESS_TOKEN → app.supabase.com > Account > Access Tokens (PAT)"
else
  echo "ERREUR: Certains CLI n'ont pas pu être installés."
  echo "Vérification de l'accès réseau à github.com et réessaie."
  exit 1
fi
