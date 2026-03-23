#!/bin/bash
# E2E Mobile Setup — Launch API + Flutter for visual testing
#
# This script reads secrets from the SINGLE SOURCE OF TRUTH:
#   ~/.facteur-secrets (gitignored, never committed)
#
# Setup (one-time):
#   cat > ~/.facteur-secrets << 'EOF'
#   SUPABASE_URL=https://ykuadtelnzavrqzbfdve.supabase.co
#   SUPABASE_ANON_KEY=eyJ...your-real-anon-key...
#   SUPABASE_JWT_SECRET=2a8ad85e-...
#   DATABASE_URL=postgresql+psycopg://...
#   EOF
#   chmod 600 ~/.facteur-secrets
#
# Usage:
#   bash docs/qa/scripts/e2e_mobile_setup.sh

set -euo pipefail

SECRETS_FILE="$HOME/.facteur-secrets"
REPO_ROOT="$(git rev-parse --show-toplevel)"

# --- Load secrets ---
if [ ! -f "$SECRETS_FILE" ]; then
  echo "❌ Missing secrets file: $SECRETS_FILE"
  echo ""
  echo "Create it with:"
  echo "  cat > $SECRETS_FILE << 'EOF'"
  echo "  SUPABASE_URL=https://ykuadtelnzavrqzbfdve.supabase.co"
  echo "  SUPABASE_ANON_KEY=eyJ...your-real-anon-key..."
  echo "  SUPABASE_JWT_SECRET=..."
  echo "  DATABASE_URL=..."
  echo "  EOF"
  echo "  chmod 600 $SECRETS_FILE"
  exit 1
fi

source "$SECRETS_FILE"

# Validate required vars
for var in SUPABASE_URL SUPABASE_ANON_KEY; do
  if [ -z "${!var:-}" ] || [ "${!var}" = "your-anon-key" ]; then
    echo "❌ $var is missing or placeholder in $SECRETS_FILE"
    exit 1
  fi
done

echo "🔑 Secrets loaded from $SECRETS_FILE"

# --- Start API (if not running) ---
if curl -s http://localhost:8080/api/health > /dev/null 2>&1; then
  echo "✅ API already running on :8080"
else
  echo "🚀 Starting API..."

  # Find venv (worktree or main repo)
  VENV_PATH=""
  if [ -f "$REPO_ROOT/packages/api/venv/bin/activate" ]; then
    VENV_PATH="$REPO_ROOT/packages/api/venv/bin/activate"
  elif [ -f "/Users/laurinboujon/Desktop/Projects/Work Projects/Facteur/packages/api/venv/bin/activate" ]; then
    VENV_PATH="/Users/laurinboujon/Desktop/Projects/Work Projects/Facteur/packages/api/venv/bin/activate"
  fi

  if [ -z "$VENV_PATH" ]; then
    echo "❌ Python venv not found"
    exit 1
  fi

  # Copy .env to API dir if missing
  API_DIR="$REPO_ROOT/packages/api"
  if [ ! -f "$API_DIR/.env" ]; then
    echo "   Generating API .env from secrets..."
    cat > "$API_DIR/.env" << ENVEOF
DATABASE_URL=${DATABASE_URL:-}
SUPABASE_URL=$SUPABASE_URL
SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY
SUPABASE_JWT_SECRET=${SUPABASE_JWT_SECRET:-}
ENVEOF
  fi

  source "$VENV_PATH"
  PYTHONPATH="$API_DIR" nohup uvicorn app.main:app --port 8080 > /tmp/facteur-api.log 2>&1 &
  echo "   Waiting for API..."
  sleep 5

  if curl -s http://localhost:8080/api/health > /dev/null 2>&1; then
    echo "✅ API started on :8080"
  else
    echo "❌ API failed to start. Check /tmp/facteur-api.log"
    exit 1
  fi
fi

# --- Launch Flutter ---
echo "🚀 Starting Flutter (Chrome)..."
cd "$REPO_ROOT/apps/mobile"
flutter run -d chrome \
  --dart-define="API_BASE_URL=http://localhost:8080/api/" \
  --dart-define="SUPABASE_URL=$SUPABASE_URL" \
  --dart-define="SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY"
