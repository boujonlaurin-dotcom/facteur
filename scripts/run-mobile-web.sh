#!/usr/bin/env bash
# run-mobile-web.sh — Lance le mobile Flutter en Chrome avec dart-defines OK,
# pour usage avec Conductor Spotlight (depuis le repo root).
#
# Usage:
#   bash scripts/run-mobile-web.sh           # prod API (Railway)
#   bash scripts/run-mobile-web.sh --local   # local API (uvicorn :8080)
#   bash scripts/run-mobile-web.sh --clean   # flutter clean puis prod API
#
# Prérequis :
#   - Flutter installé et dans le PATH (flutter doctor)
#   - Chrome installé
#   - .env au repo root renseigné (ou fallbacks publics utilisés)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 1. Charge .env du repo root si présent
if [ -f "$REPO_ROOT/.env" ]; then
  set -a; source "$REPO_ROOT/.env"; set +a
fi

# 2. Fallbacks (mêmes valeurs que .vscode/launch.json — clés publiques anon)
: "${SUPABASE_URL:=https://ykuadtelnzavrqzbfdve.supabase.co}"
: "${SUPABASE_ANON_KEY:=sb_publishable_0L_kPMbe0Pk9eBdzeEsIZg_0pogzm3k}"

# 3. Choix API et flags
DO_CLEAN=false
USE_LOCAL=false
for arg in "$@"; do
  case "$arg" in
    --local) USE_LOCAL=true ;;
    --clean) DO_CLEAN=true ;;
  esac
done

if $USE_LOCAL; then
  API_BASE_URL="http://localhost:8080/api/"
  echo "→ Backend local (uvicorn :8080)"
else
  API_BASE_URL="${API_BASE_URL:-https://facteur-production.up.railway.app/api/}"
  echo "→ Backend prod (Railway)"
fi

# 4. Garde-fou clé Supabase
if [ -z "$SUPABASE_ANON_KEY" ]; then
  echo "✗ SUPABASE_ANON_KEY vide — vérifie $REPO_ROOT/.env" >&2
  exit 1
fi

echo "→ Supabase URL : $SUPABASE_URL"
echo "→ API Base URL : $API_BASE_URL"
echo "→ Port web fixe : 8081 (http://localhost:8081)"
echo ""

# 5. Nettoie le build si demandé OU si c'est la première fois qu'on passe
#    des dart-defines (Flutter peut rater l'invalidation du cache dans ce cas).
MOBILE_DIR="$REPO_ROOT/apps/mobile"
DEFINES_STAMP="$MOBILE_DIR/.dart_tool/.dart_defines_stamp"
CURRENT_DEFINES="${SUPABASE_URL}|${SUPABASE_ANON_KEY}|${API_BASE_URL}"

if $DO_CLEAN; then
  echo "→ flutter clean (demandé via --clean)…"
  (cd "$MOBILE_DIR" && flutter clean)
  rm -f "$DEFINES_STAMP"
elif [ ! -f "$DEFINES_STAMP" ] || [ "$(cat "$DEFINES_STAMP" 2>/dev/null)" != "$CURRENT_DEFINES" ]; then
  echo "→ Dart-defines changés — flutter clean automatique (évite le cache vide)…"
  (cd "$MOBILE_DIR" && flutter clean)
  echo "$CURRENT_DEFINES" > "$DEFINES_STAMP"
fi

echo ""
echo "  Hot reload : r   |   Hot restart : R   |   Quitter : q"
echo ""

# 6. Lance Flutter (exec remplace le shell → Ctrl+C arrête bien Flutter)
cd "$MOBILE_DIR"
exec flutter run \
  -d chrome \
  --web-port=8081 \
  --dart-define=API_BASE_URL="$API_BASE_URL" \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --web-browser-flag \
  --disable-web-security
