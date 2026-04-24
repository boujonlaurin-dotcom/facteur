#!/usr/bin/env bash
# =============================================================================
# dev-bootstrap.sh — Prépare l'environnement dev Facteur (idempotent)
#
# Effet :
#   1. Crée le venv Python 3.12 dans packages/api/.venv (si absent)
#   2. Installe les dépendances API (si manquantes)
#   3. Démarre la DB test Postgres dans Docker (si éteinte)
#   4. Applique les migrations Alembic
#   5. Récupère les dépendances Flutter (si Flutter présent)
#   6. Copie ~/.facteur/.env.test → packages/api/.env.test (si existe)
#
# Tout ça est ré-exécutable sans effet de bord. Utilise `doctor.sh`
# pour vérifier l'état.
#
# Usage :
#   bash scripts/dev-bootstrap.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

echo "=== Facteur Dev Bootstrap ==="
echo "Repo: $REPO_ROOT"
echo ""

# ─── 1. Python venv ───────────────────────────────────────────────────────────
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

if [ -z "$PY_CMD" ]; then
  echo "❌ Python 3.12 non trouvé. Installe-le avant de relancer ce script :"
  echo "   macOS   : brew install python@3.12"
  echo "   Linux   : apt install python3.12 python3.12-venv"
  exit 1
fi

if [ ! -d "packages/api/.venv" ]; then
  echo "[1/6] Création du venv Python 3.12…"
  "$PY_CMD" -m venv packages/api/.venv
else
  echo "[1/6] venv déjà présent ✓"
fi

# ─── 2. Install deps API ──────────────────────────────────────────────────────
# Source de vérité = requirements.txt (utilisé aussi par le Dockerfile prod).
# requirements-dev.txt ajoute les outils de test/lint non embarqués en prod.
echo "[2/6] Install dépendances API (requirements.txt + requirements-dev.txt)…"
packages/api/.venv/bin/pip install -q --upgrade pip
packages/api/.venv/bin/pip install -q -r packages/api/requirements.txt
packages/api/.venv/bin/pip install -q -r packages/api/requirements-dev.txt

# ─── 3. Docker test DB ────────────────────────────────────────────────────────
# Assure que .env existe (docker-compose le lit pour POSTGRES_TEST_*)
if [ ! -f "$REPO_ROOT/.env" ]; then
  cp "$REPO_ROOT/.env.example" "$REPO_ROOT/.env"
  echo "[3/6] .env créé depuis .env.example ✓"
fi

# Charge les valeurs test DB (pour alembic ci-dessous)
set -a
# shellcheck disable=SC1091
source "$REPO_ROOT/.env"
set +a

if ! command -v docker &>/dev/null; then
  echo "[3/6] Docker absent — skip DB test. Installe Docker Desktop pour activer."
else
  if docker ps --format '{{.Names}}' | grep -q '^facteur-postgres-test$'; then
    echo "[3/6] DB test déjà en cours ✓"
  else
    echo "[3/6] Démarrage DB test (docker compose)…"
    docker compose -f docker-compose.test.yml up -d --wait
  fi
fi

# ─── 4. Migrations Alembic ────────────────────────────────────────────────────
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^facteur-postgres-test$'; then
  echo "[4/6] Migrations Alembic…"
  (
    cd packages/api
    DATABASE_URL="postgresql+psycopg://${POSTGRES_TEST_USER}:${POSTGRES_TEST_PASSWORD}@localhost:${POSTGRES_TEST_PORT:-54322}/${POSTGRES_TEST_DB}" \
      .venv/bin/alembic upgrade head
  )
else
  echo "[4/6] DB non démarrée — skip migrations"
fi

# ─── 5. Flutter deps ──────────────────────────────────────────────────────────
FLUTTER_CMD=""
for candidate in flutter /opt/flutter/bin/flutter /opt/homebrew/bin/flutter "$HOME/fvm/default/bin/flutter" "$HOME/flutter/bin/flutter"; do
  if [ -x "$candidate" ] 2>/dev/null || command -v "$candidate" &>/dev/null; then
    FLUTTER_CMD="$candidate"
    break
  fi
done

if [ -n "$FLUTTER_CMD" ]; then
  echo "[5/6] Flutter pub get…"
  (cd apps/mobile && "$FLUTTER_CMD" pub get >/dev/null)
else
  echo "[5/6] Flutter absent — skip. Installe via: https://docs.flutter.dev/get-started/install"
fi

# ─── 6. Sync .env.test ────────────────────────────────────────────────────────
if [ -f "$HOME/.facteur/.env.test" ]; then
  cp "$HOME/.facteur/.env.test" packages/api/.env.test
  echo "[6/6] ~/.facteur/.env.test → packages/api/.env.test ✓"
else
  echo "[6/6] ~/.facteur/.env.test absent — lance: bash scripts/setup-env-test.sh"
fi

echo ""
echo "=== Bootstrap terminé ==="
echo ""
echo "Vérifier l'état : bash scripts/doctor.sh"
echo "Lancer les tests API : bash scripts/test-api.sh"
