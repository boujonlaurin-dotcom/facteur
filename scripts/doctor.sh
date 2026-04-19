#!/usr/bin/env bash
# =============================================================================
# doctor.sh — Vérification de l'environnement dev Facteur
#
# Affiche ✅ ou ❌ pour chaque composant, en langage clair pour un humain.
#
# Usage :
#   bash scripts/doctor.sh            # résumé compact
#   bash scripts/doctor.sh --verbose  # détails par composant (valeurs masquées)
#
# Exit code : 0 si tout est ✅, 1 sinon.
# =============================================================================

set -uo pipefail

# Résolution CWD-agnostique du repo root (marche depuis n'importe où).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

VERBOSE=0
if [ "${1:-}" = "--verbose" ] || [ "${1:-}" = "-v" ]; then
  VERBOSE=1
fi

# ─── Compteurs ────────────────────────────────────────────────────────────────
OK_COUNT=0
KO_COUNT=0

ok()   { printf "✅ %-28s %s\n" "$1" "${2:-}"; OK_COUNT=$((OK_COUNT+1)); }
ko()   { printf "❌ %-28s %s\n" "$1" "${2:-}"; KO_COUNT=$((KO_COUNT+1)); }
info() { [ "$VERBOSE" = "1" ] && printf "   %-28s %s\n" "" "$1"; }

mask() {
  # Masque une valeur sensible : garde 4 premiers + 4 derniers caractères.
  local v="$1"
  local n=${#v}
  if [ "$n" -le 10 ]; then
    printf "****"
  else
    printf "%s****%s (%d chars)" "${v:0:4}" "${v: -4}" "$n"
  fi
}

echo "=== Facteur Doctor ==="
echo ""

# ─── 1. Python 3.12 ───────────────────────────────────────────────────────────
PY_CMD=""
for candidate in python3.12 python3 python; do
  if command -v "$candidate" &>/dev/null; then
    ver=$("$candidate" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null)
    if [ "$ver" = "3.12" ]; then
      PY_CMD="$candidate"
      break
    fi
  fi
done

if [ -n "$PY_CMD" ]; then
  ok "Python 3.12" "($(command -v "$PY_CMD"))"
else
  ko "Python 3.12" "absent — macOS: 'brew install python@3.12' | Linux: 'apt install python3.12'"
fi

# ─── 2. Docker ────────────────────────────────────────────────────────────────
if command -v docker &>/dev/null; then
  if docker info &>/dev/null; then
    ok "Docker" "($(docker --version | awk '{print $3}' | tr -d ,))"
  else
    ko "Docker" "installé mais démon KO — démarre Docker Desktop"
  fi
else
  ko "Docker" "absent — macOS: installe Docker Desktop | Linux: 'apt install docker.io'"
fi

# ─── 3. Flutter SDK ───────────────────────────────────────────────────────────
FLUTTER_CMD=""
for candidate in flutter /opt/flutter/bin/flutter /opt/homebrew/bin/flutter "$HOME/fvm/default/bin/flutter" "$HOME/flutter/bin/flutter"; do
  if [ -x "$candidate" ] 2>/dev/null || command -v "$candidate" &>/dev/null; then
    FLUTTER_CMD="$candidate"
    break
  fi
done

if [ -n "$FLUTTER_CMD" ]; then
  fver=$("$FLUTTER_CMD" --version 2>/dev/null | head -1 | awk '{print $2}')
  ok "Flutter SDK" "($fver via $FLUTTER_CMD)"
else
  ko "Flutter SDK" "absent — https://docs.flutter.dev/get-started/install"
fi

# ─── 4. venv API ──────────────────────────────────────────────────────────────
if [ -f "$REPO_ROOT/packages/api/.venv/bin/pytest" ]; then
  ok "venv API" "(packages/api/.venv)"
else
  ko "venv API" "absent — lance: bash $REPO_ROOT/scripts/dev-bootstrap.sh"
fi

# ─── 5. .env (infra/tooling) ──────────────────────────────────────────────────
if [ -f "$REPO_ROOT/.env" ]; then
  ok ".env" "(repo root)"
else
  ko ".env" "absent — lance: cp .env.example .env  (ou: make bootstrap)"
fi

# ─── 6. DB test en cours d'exécution ──────────────────────────────────────────
if command -v docker &>/dev/null && docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^facteur-postgres-test$'; then
  TEST_PORT="${POSTGRES_TEST_PORT:-54322}"
  [ -f "$REPO_ROOT/.env" ] && TEST_PORT=$(grep -E '^POSTGRES_TEST_PORT=' "$REPO_ROOT/.env" | cut -d= -f2 || echo 54322)
  ok "DB test running" "(localhost:${TEST_PORT:-54322})"
else
  ko "DB test running" "éteinte — lance: make db-up"
fi

# ─── 6. ~/.facteur/.env.test ──────────────────────────────────────────────────
ENV_FILE="$HOME/.facteur/.env.test"
if [ -f "$ENV_FILE" ]; then
  # Compte variables définies et non vides
  COUNT=$(grep -E '^[A-Z_]+=.+' "$ENV_FILE" 2>/dev/null | wc -l | tr -d ' ')
  ok "~/.facteur/.env.test" "($COUNT variables définies)"

  if [ "$VERBOSE" = "1" ]; then
    while IFS='=' read -r key value; do
      [[ "$key" =~ ^[[:space:]]*# ]] && continue
      [ -z "$key" ] && continue
      if [ -z "$value" ]; then
        info "$key = (vide)"
      else
        info "$key = $(mask "$value")"
      fi
    done < "$ENV_FILE"
  fi
else
  ko "~/.facteur/.env.test" "absent — lance: bash $REPO_ROOT/scripts/setup-env-test.sh"
fi

# ─── 7. MCP tokens (env) ──────────────────────────────────────────────────────
if [ -n "${SENTRY_AUTH_TOKEN:-}" ]; then
  ok "MCP Sentry token" "(défini)"
else
  ko "MCP Sentry token" "manquant — ajoute SENTRY_AUTH_TOKEN dans .claude/settings.json"
fi

if [ -n "${RAILWAY_TOKEN:-}" ]; then
  ok "MCP Railway token" "(défini)"
else
  ko "MCP Railway token" "manquant — ajoute RAILWAY_TOKEN dans .claude/settings.json"
fi

# ─── Résumé ───────────────────────────────────────────────────────────────────
echo ""
TOTAL=$((OK_COUNT + KO_COUNT))
if [ "$KO_COUNT" = "0" ]; then
  echo "✅  $OK_COUNT/$TOTAL OK — tout est bon, tu peux lancer: bash scripts/test-api.sh"
  exit 0
else
  echo "⚠️   $OK_COUNT/$TOTAL OK, $KO_COUNT action(s) à résoudre ci-dessus."
  echo ""
  echo "Pour un bootstrap complet automatique: bash scripts/dev-bootstrap.sh"
  exit 1
fi
