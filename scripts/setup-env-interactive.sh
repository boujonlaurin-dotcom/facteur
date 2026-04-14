#!/bin/bash
# =============================================================================
# setup-env-interactive.sh — Configure .env interactivement (une seule fois)
#
# Usage :
#   bash scripts/setup-env-interactive.sh
# =============================================================================

set -euo pipefail

echo "=== Configuration des variables d'environnement Facteur ==="
echo ""
echo "Ce script crée/met à jour .env (gitignored) avec tes tokens."
echo "Les valeurs sont sauvegardées une seule fois — réutilisées ensuite."
echo ""

# ─── Lire les valeurs actuelles si .env existe ─────────────────────────────
if [ -f .env ]; then
  echo "[i] .env détecté — lecture des valeurs existantes..."
  set +u  # Pas d'erreur si la variable n'existe pas
  source .env
  set -u
fi

# ─── Railway Token ──────────────────────────────────────────────────────────
echo ""
echo "1️⃣  RAILWAY_TOKEN"
echo "   Obtenir : railway.app > Account Settings > Tokens > Create"
echo ""
read -p "   Collle le token (ou laisse vide pour garder la valeur actuelle) : " railway_input
RAILWAY_TOKEN="${railway_input:-${RAILWAY_TOKEN:-}}"

if [ -z "$RAILWAY_TOKEN" ]; then
  echo "   ⚠️  RAILWAY_TOKEN vide — les commandes railway CLI ne fonctionneront pas"
else
  echo "   ✅ RAILWAY_TOKEN configuré"
fi

# ─── Supabase Access Token ──────────────────────────────────────────────────
echo ""
echo "2️⃣  SUPABASE_ACCESS_TOKEN (PAT — Personal Access Token)"
echo "   Obtenir : app.supabase.com > Account > Access Tokens > Generate"
echo "   ⚠️  PAS le JWT Secret du projet — c'est un token personnel"
echo ""
read -p "   Colle le token PAT (ou laisse vide pour garder la valeur actuelle) : " supabase_input
SUPABASE_ACCESS_TOKEN="${supabase_input:-${SUPABASE_ACCESS_TOKEN:-}}"

if [ -z "$SUPABASE_ACCESS_TOKEN" ]; then
  echo "   ⚠️  SUPABASE_ACCESS_TOKEN vide — le MCP Supabase ne fonctionnera pas"
else
  echo "   ✅ SUPABASE_ACCESS_TOKEN configuré"
fi

# ─── Générer le .env ───────────────────────────────────────────────────────
cat > .env <<EOF
# Railway
RAILWAY_TOKEN=$RAILWAY_TOKEN
RAILWAY_PROJECT_ID=
RAILWAY_SERVICE_ID=

# Supabase
SUPABASE_ACCESS_TOKEN=$SUPABASE_ACCESS_TOKEN
SUPABASE_URL=https://ykuadtelnzavrqzbfdve.supabase.co
SUPABASE_ANON_KEY=

# Sentry
SENTRY_AUTH_TOKEN=
SENTRY_ORG=
SENTRY_PROJECT=
EOF

echo ""
echo "✅ .env créé/mis à jour"
echo ""

# ─── Proposer d'ajouter au shell profile ────────────────────────────────────
echo "3️⃣  [Optionnel] Sourcer .env au démarrage du shell ?"
echo "   Ajoute la ligne à ~/.bashrc ou ~/.zshrc pour source .env automatiquement"
echo ""
read -p "   Quelle shell utilises-tu ? (bash/zsh/autre/non) : " shell_choice

case "$shell_choice" in
  bash)
    RC_FILE="$HOME/.bashrc"
    echo "   Ajout à $RC_FILE..."
    ;;
  zsh)
    RC_FILE="$HOME/.zshrc"
    echo "   Ajout à $RC_FILE..."
    ;;
  *)
    echo "   OK — tu devras sourcer manuellement : source .env"
    RC_FILE=""
    ;;
esac

if [ -n "$RC_FILE" ] && [ -f "$RC_FILE" ]; then
  # Vérifier si déjà présent
  if grep -q "source.*\.env" "$RC_FILE" 2>/dev/null; then
    echo "   (déjà configuré dans $RC_FILE)"
  else
    {
      echo ""
      echo "# Facteur — source .env"
      echo "[ -f \"\$(pwd)/.env\" ] && source \"\$(pwd)/.env\""
    } >> "$RC_FILE"
    echo "   ✅ Ajouté à $RC_FILE"
    echo ""
    echo "   Recharge ton shell : source $RC_FILE"
  fi
fi

echo ""
echo "=== ✅ Terminé ==="
echo ""
echo "Prochaines étapes :"
echo "  1. Recharge le shell : source $RC_FILE (ou ouvre un nouveau terminal)"
echo "  2. Vérifie les tokens : echo \$RAILWAY_TOKEN"
echo "  3. Test les CLIs :"
echo "     railway projects list"
echo "     supabase projects list"
