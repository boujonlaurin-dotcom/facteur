#!/bin/bash
# =============================================================================
# setup-cli-tools.sh — Installation des CLI Railway et Supabase
#
# À exécuter une fois sur une nouvelle machine de développement,
# ou dans un environnement CI/CD avec accès réseau.
#
# Prérequis : Node.js >= 18, npm >= 9
# =============================================================================

set -euo pipefail

echo "=== Facteur — Installation des CLI dev tools ==="
echo ""

# ─── Railway CLI ────────────────────────────────────────────────────────────
if command -v railway &>/dev/null; then
  echo "[OK] Railway CLI déjà installé: $(railway --version 2>/dev/null)"
else
  echo "[...] Installation Railway CLI (@railway/cli)..."
  npm install -g @railway/cli
  echo "[OK] Railway CLI installé: $(railway --version 2>/dev/null)"
fi

# ─── Supabase CLI ────────────────────────────────────────────────────────────
if command -v supabase &>/dev/null; then
  echo "[OK] Supabase CLI déjà installé: $(supabase --version 2>/dev/null)"
else
  echo "[...] Installation Supabase CLI (supabase)..."
  npm install -g supabase
  echo "[OK] Supabase CLI installé: $(supabase --version 2>/dev/null)"
fi

echo ""
echo "=== Variables d'environnement requises ==="
echo ""
echo "Copie .env.example vers .env et renseigne les valeurs :"
echo ""
echo "  RAILWAY_TOKEN              — Railway > Account Settings > Tokens"
echo "                               (scope: Full Access ou Read-only selon besoin)"
echo ""
echo "  SUPABASE_ACCESS_TOKEN      — supabase.com > Account > Access Tokens"
echo ""
echo "  RAILWAY_PROJECT_ID         — ID du projet Railway (optionnel pour CLI)"
echo "  RAILWAY_SERVICE_ID         — ID du service Railway (optionnel pour CLI)"
echo ""
echo "Documentation : docs/config/env-vars.md (si existant)"
echo ""

# ─── Vérification finale ──────────────────────────────────────────────────
echo "=== Vérification ==="
echo ""
ALL_OK=true

check_cmd() {
  if command -v "$1" &>/dev/null; then
    echo "[OK] $1"
  else
    echo "[MISSING] $1 — relance ce script avec accès réseau"
    ALL_OK=false
  fi
}

check_cmd railway
check_cmd supabase

echo ""
if [ "$ALL_OK" = true ]; then
  echo "Tout est installé. Les MCP servers Railway et Supabase sont prêts."
else
  echo "Certains outils manquent. Vérifie la connexion réseau et relance le script."
  exit 1
fi
